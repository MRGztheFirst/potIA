#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import gc
import inspect
import json
import logging
import math
import sys
import time
from pathlib import Path
from typing import Any

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_TRAIN_FILE = BASE_DIR / "data" / "potia_train.jsonl"
DEFAULT_VAL_FILE = BASE_DIR / "data" / "potia_val.jsonl"
DEFAULT_OUTPUT_DIR = BASE_DIR / "artifacts" / "potia-qwen2.5-7b"

DEFAULT_BASE_MODEL = "Qwen/Qwen2.5-7B-Instruct"

LORA_TARGET_MODULES = ["q_proj", "k_proj", "v_proj", "o_proj", "gate_proj", "up_proj", "down_proj"]

HARDWARE_PROFILES: dict[str, dict[str, int]] = {
    "t4": {"max_length": 1024, "batch_size": 2, "grad_accum": 8},
    "rtx": {"max_length": 1536, "batch_size": 2, "grad_accum": 8},
    "a100": {"max_length": 2048, "batch_size": 8, "grad_accum": 2},
}

SMOKE_TEST_QUESTION = "Como fazer brigadeiro de panela?"

logger = logging.getLogger("potia.train")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="PotIA — Fase 3: fine-tuning QLoRA.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--base-model", default=DEFAULT_BASE_MODEL, help="ID no Hugging Face ou pasta local.")
    parser.add_argument("--train-file", type=Path, default=DEFAULT_TRAIN_FILE)
    parser.add_argument("--val-file", type=Path, default=DEFAULT_VAL_FILE)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--profile", choices=sorted(HARDWARE_PROFILES), default="t4", help="Perfil de hardware.")

    hp = parser.add_argument_group("hiperparâmetros")
    hp.add_argument("--epochs", type=float, default=3.0, help="Passadas completas pelo dataset.")
    hp.add_argument("--learning-rate", type=float, default=2e-4, help="LR típica para LoRA (maior que no full fine-tuning).")
    hp.add_argument("--batch-size", type=int, help="Exemplos por GPU por passo (padrão: do perfil).")
    hp.add_argument("--grad-accum", type=int, help="Passos acumulados antes de atualizar os pesos (padrão: do perfil).")
    hp.add_argument("--max-length", type=int, help="Tokens máximos por exemplo (padrão: do perfil).")
    hp.add_argument("--max-steps", type=int, default=-1, help="Limita os passos (útil para testes). -1 = usa --epochs.")
    hp.add_argument("--warmup-ratio", type=float, default=0.03)
    hp.add_argument("--lora-r", type=int, default=16, help="Posto (rank) das matrizes LoRA.")
    hp.add_argument("--lora-alpha", type=int, default=32, help="Escala do LoRA (costuma ser 2×r).")
    hp.add_argument("--lora-dropout", type=float, default=0.05)
    hp.add_argument("--seed", type=int, default=42)

    run = parser.add_argument_group("execução")
    run.add_argument("--no-quantization", action="store_true", help="Desliga o 4-bit (CPU/depuração ou GPUs grandes).")
    run.add_argument("--resume", action="store_true", help="Retoma do último checkpoint em output-dir/checkpoints.")
    run.add_argument("--merge", action="store_true", help="Após treinar, mescla o LoRA nos pesos completos.")
    run.add_argument("--merge-only", action="store_true", help="Apenas mescla um adaptador já treinado.")
    run.add_argument("--skip-smoke-test", action="store_true", help="Não gera a resposta de teste ao final.")
    args = parser.parse_args(argv)

    profile = HARDWARE_PROFILES[args.profile]
    args.batch_size = args.batch_size or profile["batch_size"]
    args.grad_accum = args.grad_accum or profile["grad_accum"]
    args.max_length = args.max_length or profile["max_length"]
    return args


CONFIG_ALIASES = {
    "max_length": ["max_seq_length"],
    "eval_strategy": ["evaluation_strategy"],
    "warmup_ratio": ["warmup_steps"],
}


def build_config(config_cls: type, wanted: dict[str, Any]) -> Any:
    accepted = {f.name for f in dataclasses.fields(config_cls)}
    kwargs: dict[str, Any] = {}
    for name, value in wanted.items():
        for candidate in [name, *CONFIG_ALIASES.get(name, [])]:
            if candidate in accepted:
                kwargs[candidate] = value
                break
        else:
            logger.warning("'%s' não existe nesta versão de %s — ignorado.", name, config_cls.__name__)
    return config_cls(**kwargs)


def dtype_kwarg(dtype: Any) -> dict[str, Any]:
    import transformers
    from packaging.version import Version

    key = "dtype" if Version(transformers.__version__) >= Version("4.56.0") else "torch_dtype"
    return {key: dtype}


def free_memory() -> None:
    import torch

    gc.collect()
    if torch.cuda.is_available():
        torch.cuda.empty_cache()


def to_prompt_completion(example: dict[str, Any]) -> dict[str, Any]:
    messages = example["messages"]
    return {"prompt": messages[:-1], "completion": [messages[-1]]}


def load_conversations(path: Path, tokenizer: Any, max_length: int) -> Any:
    from datasets import load_dataset

    dataset = load_dataset("json", data_files=str(path), split="train")
    if "messages" not in dataset.column_names:
        raise ValueError(f"{path} não tem a coluna 'messages'. Gere o arquivo com format_dataset.py.")

    def fits(example: dict[str, Any]) -> bool:
        text = tokenizer.apply_chat_template(example["messages"], tokenize=False)
        return len(tokenizer(text, add_special_tokens=False)["input_ids"]) <= max_length

    before = len(dataset)
    dataset = dataset.filter(fits, desc="Filtrando exemplos longos")
    if len(dataset) < before:
        logger.warning("%d de %d exemplos excedem %d tokens e foram descartados.", before - len(dataset), before, max_length)
    return dataset.map(to_prompt_completion, remove_columns=dataset.column_names, desc="Formatando")


def read_system_prompt(path: Path) -> str:
    with path.open(encoding="utf-8") as handle:
        first = json.loads(handle.readline())
    messages = first["messages"]
    return messages[0]["content"] if messages and messages[0]["role"] == "system" else ""


def load_tokenizer(model_id: str) -> Any:
    from transformers import AutoTokenizer

    tokenizer = AutoTokenizer.from_pretrained(model_id)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token
    tokenizer.padding_side = "right"
    return tokenizer


def load_base_model(model_id: str, quantize: bool, compute_dtype: Any) -> Any:
    import torch
    from transformers import AutoModelForCausalLM, BitsAndBytesConfig

    kwargs: dict[str, Any] = {**dtype_kwarg(compute_dtype), "attn_implementation": "sdpa"}
    if quantize:
        kwargs["quantization_config"] = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True,
            bnb_4bit_compute_dtype=compute_dtype,
        )
        kwargs["device_map"] = {"": torch.cuda.current_device()}
    elif torch.cuda.is_available():
        kwargs["device_map"] = "auto"

    model = AutoModelForCausalLM.from_pretrained(model_id, **kwargs)
    model.config.use_cache = False
    return model


def attach_lora(model: Any, args: argparse.Namespace, quantize: bool) -> Any:
    from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training

    if quantize:
        model = prepare_model_for_kbit_training(
            model, use_gradient_checkpointing=True, gradient_checkpointing_kwargs={"use_reentrant": False}
        )
    lora_config = LoraConfig(
        r=args.lora_r,
        lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        target_modules=LORA_TARGET_MODULES,
        bias="none",
        task_type="CAUSAL_LM",
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()
    return model


def build_sft_config(args: argparse.Namespace, use_cuda: bool, use_bf16: bool, has_eval: bool) -> Any:
    from trl import SFTConfig

    effective_batch = args.batch_size * args.grad_accum
    logger.info("Batch efetivo: %d × %d = %d", args.batch_size, args.grad_accum, effective_batch)
    wanted = {
        "output_dir": str(args.output_dir / "checkpoints"),
        "num_train_epochs": args.epochs,
        "max_steps": args.max_steps,
        "learning_rate": args.learning_rate,
        "lr_scheduler_type": "cosine",
        "warmup_ratio": args.warmup_ratio,
        "weight_decay": 0.0,
        "max_grad_norm": 0.3,
        "optim": "paged_adamw_8bit" if use_cuda else "adamw_torch",
        "per_device_train_batch_size": args.batch_size,
        "per_device_eval_batch_size": args.batch_size,
        "gradient_accumulation_steps": args.grad_accum,
        "gradient_checkpointing": use_cuda,
        "gradient_checkpointing_kwargs": {"use_reentrant": False},
        "bf16": use_cuda and use_bf16,
        "fp16": use_cuda and not use_bf16,
        "max_length": args.max_length,
        "packing": False,
        "completion_only_loss": True,
        "logging_steps": 5,
        "eval_strategy": "epoch" if has_eval else "no",
        "save_strategy": "epoch",
        "save_total_limit": 2,
        "load_best_model_at_end": has_eval,
        "metric_for_best_model": "eval_loss" if has_eval else None,
        "greater_is_better": False,
        "report_to": "none",
        "seed": args.seed,
    }
    if args.max_steps > 0:
        wanted.update(eval_strategy="no", save_strategy="no", load_best_model_at_end=False, metric_for_best_model=None)
    return build_config(SFTConfig, wanted)


def build_trainer(model: Any, tokenizer: Any, config: Any, train_ds: Any, eval_ds: Any) -> Any:
    from trl import SFTTrainer

    kwargs: dict[str, Any] = {"model": model, "args": config, "train_dataset": train_ds, "eval_dataset": eval_ds}
    params = inspect.signature(SFTTrainer.__init__).parameters
    kwargs["processing_class" if "processing_class" in params else "tokenizer"] = tokenizer
    return SFTTrainer(**kwargs)


def smoke_test(model: Any, tokenizer: Any, system_prompt: str) -> str:
    import torch

    model.eval()
    messages = [{"role": "system", "content": system_prompt}] if system_prompt else []
    messages.append({"role": "user", "content": SMOKE_TEST_QUESTION})
    text = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
    inputs = tokenizer(text, return_tensors="pt", add_special_tokens=False).to(model.device)
    with torch.inference_mode():
        output = model.generate(
            **inputs,
            max_new_tokens=300,
            do_sample=True,
            temperature=0.7,
            top_p=0.9,
            repetition_penalty=1.05,
            pad_token_id=tokenizer.pad_token_id,
            use_cache=True,
        )
    return tokenizer.decode(output[0, inputs["input_ids"].shape[1]:], skip_special_tokens=True)


def merge_adapter(base_model_id: str, adapter_dir: Path, merged_dir: Path) -> None:
    import torch
    from peft import PeftModel
    from transformers import AutoModelForCausalLM, AutoTokenizer

    if not (adapter_dir / "adapter_config.json").exists():
        raise FileNotFoundError(f"Adaptador LoRA não encontrado em {adapter_dir}")

    use_bf16 = torch.cuda.is_available() and torch.cuda.get_device_capability()[0] >= 8
    dtype = torch.bfloat16 if use_bf16 else torch.float16
    offload_dir = merged_dir.parent / "offload_tmp"
    logger.info("Carregando %s em %s para a mescla...", base_model_id, dtype)
    base = AutoModelForCausalLM.from_pretrained(
        base_model_id,
        **dtype_kwarg(dtype),
        device_map="auto",
        low_cpu_mem_usage=True,
        offload_folder=str(offload_dir),
    )
    model = PeftModel.from_pretrained(base, str(adapter_dir))
    model = model.merge_and_unload()

    merged_dir.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(str(merged_dir), safe_serialization=True, max_shard_size="2GB")
    AutoTokenizer.from_pretrained(str(adapter_dir)).save_pretrained(str(merged_dir))
    logger.info("Modelo mesclado salvo em %s", merged_dir)

    del model, base
    free_memory()


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s | %(levelname)-7s | %(message)s", datefmt="%H:%M:%S")
    args = parse_args(argv)

    adapter_dir = args.output_dir / "adapter"
    merged_dir = args.output_dir / "merged"

    try:
        import torch
    except ImportError:
        logger.error("PyTorch não encontrado. Instale com: pip install -r requirements-train.txt")
        return 1

    if args.merge_only:
        merge_adapter(args.base_model, adapter_dir, merged_dir)
        return 0

    for path in (args.train_file,):
        if not path.exists():
            logger.error("Arquivo %s não encontrado. Rode antes: python format_dataset.py", path)
            return 1

    use_cuda = torch.cuda.is_available()
    quantize = use_cuda and not args.no_quantization
    if not use_cuda:
        logger.warning("Nenhuma GPU CUDA detectada: treinando em CPU (só serve para testes com modelos minúsculos).")
        if not args.no_quantization:
            logger.warning("A quantização 4-bit exige GPU; seguindo sem quantização.")
    use_bf16 = use_cuda and torch.cuda.get_device_capability()[0] >= 8
    compute_dtype = torch.bfloat16 if use_bf16 else (torch.float16 if use_cuda else torch.float32)
    if use_cuda:
        name = torch.cuda.get_device_name()
        vram = torch.cuda.get_device_properties(0).total_memory / 1024**3
        logger.info("GPU: %s (%.1f GB) | precisão: %s | 4-bit: %s", name, vram, compute_dtype, quantize)

    from transformers import set_seed

    set_seed(args.seed)

    logger.info("Carregando tokenizer e dataset...")
    tokenizer = load_tokenizer(args.base_model)
    train_ds = load_conversations(args.train_file, tokenizer, args.max_length)
    eval_ds = load_conversations(args.val_file, tokenizer, args.max_length) if args.val_file.exists() else None
    if eval_ds is not None and len(eval_ds) == 0:
        eval_ds = None
    logger.info("Exemplos: %d treino | %d validação", len(train_ds), len(eval_ds) if eval_ds else 0)
    if len(train_ds) == 0:
        logger.error("Nenhum exemplo de treino restou após o filtro de tamanho.")
        return 1

    logger.info("Carregando modelo base %s...", args.base_model)
    model = load_base_model(args.base_model, quantize, compute_dtype)
    model = attach_lora(model, args, quantize)

    config = build_sft_config(args, use_cuda, use_bf16, has_eval=eval_ds is not None)
    trainer = build_trainer(model, tokenizer, config, train_ds, eval_ds)

    checkpoint_dir = args.output_dir / "checkpoints"
    resume = args.resume and checkpoint_dir.exists() and any(checkpoint_dir.glob("checkpoint-*"))
    start = time.time()
    try:
        train_result = trainer.train(resume_from_checkpoint=True if resume else None)
    except torch.cuda.OutOfMemoryError:
        logger.error(
            "Sem memória na GPU. Tente: --batch-size 1 --grad-accum 16, --max-length menor "
            "ou um modelo menor (--base-model Qwen/Qwen2.5-3B-Instruct)."
        )
        return 1
    elapsed = time.time() - start

    metrics: dict[str, Any] = dict(train_result.metrics)
    metrics["tempo_minutos"] = round(elapsed / 60, 1)
    if eval_ds is not None:
        eval_metrics = trainer.evaluate()
        metrics.update(eval_metrics)
        if "eval_loss" in eval_metrics:
            metrics["eval_perplexity"] = round(math.exp(eval_metrics["eval_loss"]), 3)
    logger.info("Métricas: %s", json.dumps(metrics, ensure_ascii=False))

    trainer.save_model(str(adapter_dir))
    tokenizer.save_pretrained(str(adapter_dir))
    summary = {"base_model": args.base_model, "args": {k: str(v) for k, v in vars(args).items()}, "metrics": metrics}
    (args.output_dir / "training_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    logger.info("Adaptador LoRA salvo em %s", adapter_dir)

    if not args.skip_smoke_test:
        answer = smoke_test(trainer.model, tokenizer, read_system_prompt(args.train_file))
        print(f"\n=== Teste: {SMOKE_TEST_QUESTION} ===\n{answer}\n")

    del trainer, model
    free_memory()

    if args.merge:
        merge_adapter(args.base_model, adapter_dir, merged_dir)
    else:
        logger.info("Para gerar o modelo completo: python train_potia_model.py --merge-only --base-model %s", args.base_model)
    return 0


if __name__ == "__main__":
    sys.exit(main())
