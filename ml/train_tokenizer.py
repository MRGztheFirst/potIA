#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import logging
import sys
import unicodedata
from pathlib import Path

from tokenizers import AddedToken, Regex, Tokenizer, decoders, normalizers, pre_tokenizers
from tokenizers.models import BPE
from tokenizers.trainers import BpeTrainer

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_CORPUS = BASE_DIR / "data" / "dados_receitas.txt"
DEFAULT_OUTPUT_DIR = BASE_DIR / "artifacts" / "tokenizer_potia"

SPACE_MARKER = "▁"

SPECIAL_TOKENS = ["<unk>", "<pad>", "<s>", "</s>", "<|im_start|>", "<|im_end|>"]

PRE_TOKENIZER_PATTERN = r"▁?[^▁\s.,;:!?()\"'/]+|▁?[.,;:!?()\"'/]|\s+|▁+"

INITIAL_ALPHABET = sorted(
    set(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        "áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÜÇ"
        "0123456789"
        ".,;:!?()/%°ºª+-'\"&"
        "\n" + SPACE_MARKER
    )
)

CULINARY_TERMS = [
    "colher de sopa", "colheres de sopa", "colher de chá", "colheres de chá",
    "colher de café", "colheres de café", "colher de sobremesa", "colheres de sobremesa",
    "xícara de chá", "xícaras de chá", "copo americano", "copos americanos",
    "dente de alho", "dentes de alho", "pitada de sal", "a gosto",
    "banho-maria", "fogo brando", "fogo baixo", "fogo médio", "fogo alto",
    "refogar", "refogue", "refogado", "refogada",
    "pré-aquecido", "pré-aqueça", "forno pré-aquecido",
    "ponto de fio", "ponto de bala", "ponto de neve", "claras em neve",
    "até dourar", "até ferver", "mexendo sempre", "sem parar", "em temperatura ambiente",
    "untar e enfarinhar", "unte e enfarinhe", "leve ao forno", "deixe esfriar",
    "papel-manteiga", "papel alumínio",
    "leite condensado", "creme de leite", "fermento em pó", "farinha de trigo", "amido de milho",
    "açúcar refinado", "açúcar mascavo", "manteiga sem sal", "azeite de oliva",
    "cheiro-verde", "pimenta-do-reino", "queijo parmesão", "chocolate em pó",
]

EVAL_SENTENCES = [
    "Adicione 2 colheres de sopa de açúcar e misture em fogo brando.",
    "Asse em banho-maria, no forno pré-aquecido a 180 °C, por 40 minutos.",
    "Refogue a cebola no azeite de oliva até dourar e tempere com sal a gosto.",
    "Bata as claras em neve e junte 1 xícara de chá de farinha de trigo.",
]

logger = logging.getLogger("potia.tokenizer")


def build_tokenizer() -> Tokenizer:
    tokenizer = Tokenizer(BPE(unk_token="<unk>"))
    tokenizer.normalizer = normalizers.Sequence([normalizers.NFC(), normalizers.Replace(" ", SPACE_MARKER)])
    tokenizer.pre_tokenizer = pre_tokenizers.Split(Regex(PRE_TOKENIZER_PATTERN), behavior="isolated")
    tokenizer.decoder = decoders.Replace(SPACE_MARKER, " ")
    return tokenizer


def term_variants(terms: list[str]) -> list[str]:
    variants: list[str] = []
    for term in terms:
        capitalized = term[:1].upper() + term[1:]
        for variant in (f" {term}", f" {capitalized}", capitalized):
            if variant not in variants:
                variants.append(variant)
    return variants


def add_culinary_tokens(tokenizer: Tokenizer, terms: list[str]) -> int:
    tokens = [AddedToken(v, normalized=True, special=False) for v in term_variants(terms)]
    return tokenizer.add_tokens(tokens)


def read_corpus(path: Path) -> list[str]:
    text = unicodedata.normalize("NFC", path.read_text(encoding="utf-8"))
    return [block.strip() for block in text.split("\n\n") if block.strip()]


def train(blocks: list[str], vocab_size: int, min_frequency: int) -> Tokenizer:
    tokenizer = build_tokenizer()
    trainer = BpeTrainer(
        vocab_size=vocab_size,
        min_frequency=min_frequency,
        special_tokens=SPECIAL_TOKENS,
        initial_alphabet=INITIAL_ALPHABET,
        show_progress=True,
    )
    tokenizer.train_from_iterator(blocks, trainer=trainer, length=len(blocks))
    return tokenizer


def count_tokens(tokenizer: Tokenizer, blocks: list[str]) -> int:
    return sum(len(encoding.ids) for encoding in tokenizer.encode_batch(blocks))


def evaluate(base: Tokenizer, final: Tokenizer, blocks: list[str], terms: list[str]) -> dict:
    base_total = count_tokens(base, blocks)
    final_total = count_tokens(final, blocks)
    saving = 1 - final_total / base_total if base_total else 0.0

    unk_id = final.token_to_id("<unk>")
    unknown = sum(enc.ids.count(unk_id) for enc in final.encode_batch(blocks))

    print("\n=== Economia de contexto no corpus ===")
    print(f"Tokens sem termos culinários: {base_total:>10,}")
    print(f"Tokens com termos culinários: {final_total:>10,}")
    print(f"Economia:                     {saving:>10.1%}")
    print(f"Tokens <unk> no corpus:       {unknown:>10,}")

    print("\n=== Exemplos ===")
    roundtrip_ok = True
    for sentence in EVAL_SENTENCES:
        encoding = final.encode(sentence)
        decoded = final.decode(encoding.ids)
        ok = decoded == sentence
        roundtrip_ok &= ok
        print(f"\n{sentence}")
        print(f"  base  ({len(base.encode(sentence).ids):>2} tokens): {base.encode(sentence).tokens}")
        print(f"  final ({len(encoding.ids):>2} tokens): {encoding.tokens}")
        print(f"  decodificação idêntica ao original: {'sim' if ok else 'NÃO → ' + repr(decoded)}")

    broken = [t for t in terms if len(final.encode(f"Use {t} aqui").ids) != len(final.encode("Use aqui").ids) + 1]
    if broken:
        logger.warning("Termos que NÃO viraram token único: %s", broken)
    else:
        print(f"\nTodos os {len(terms)} termos culinários viraram token único. ✓")

    return {
        "tokens_base": base_total,
        "tokens_final": final_total,
        "economia": round(saving, 4),
        "tokens_desconhecidos": unknown,
        "roundtrip_ok": roundtrip_ok,
        "termos_quebrados": broken,
    }


def save(tokenizer: Tokenizer, output_dir: Path, stats: dict) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    tokenizer.save(str(output_dir / "tokenizer.json"))
    (output_dir / "termos_culinarios.json").write_text(
        json.dumps(CULINARY_TERMS, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    (output_dir / "estatisticas.json").write_text(json.dumps(stats, ensure_ascii=False, indent=2), encoding="utf-8")

    try:
        from transformers import PreTrainedTokenizerFast
    except ImportError:
        logger.info("transformers não instalado: salvo apenas o tokenizer.json.")
        return
    try:
        hf_tokenizer = PreTrainedTokenizerFast(
            tokenizer_object=tokenizer,
            unk_token="<unk>",
            pad_token="<pad>",
            bos_token="<s>",
            eos_token="<|im_end|>",
        )
        hf_tokenizer.chat_template = (
            "{% for message in messages %}"
            "{{ '<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>' + '\n' }}"
            "{% endfor %}"
            "{% if add_generation_prompt %}{{ '<|im_start|>assistant\n' }}{% endif %}"
        )
        hf_tokenizer.save_pretrained(str(output_dir))
    except Exception as exc:
        logger.warning("Não foi possível salvar no formato Hugging Face: %s", exc)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PotIA — Fase 2a: treina um tokenizer BPE culinário.")
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS, help="Corpus gerado na Fase 1.")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--vocab-size", type=int, default=8000, help="Tamanho alvo do vocabulário BPE.")
    parser.add_argument("--min-frequency", type=int, default=2, help="Frequência mínima para um par virar token.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    args = parse_args(argv)

    if not args.corpus.exists():
        logger.error("Corpus não encontrado em %s. Rode antes: python scraper_potia.py --sample", args.corpus)
        return 1
    blocks = read_corpus(args.corpus)
    if not blocks:
        logger.error("O corpus está vazio.")
        return 1
    logger.info("Treinando BPE com %d receitas (vocabulário alvo: %d)...", len(blocks), args.vocab_size)

    tokenizer = train(blocks, args.vocab_size, args.min_frequency)
    base = Tokenizer.from_str(tokenizer.to_str())
    added = add_culinary_tokens(tokenizer, CULINARY_TERMS)
    logger.info("Vocabulário BPE: %d | termos culinários adicionados: %d", base.get_vocab_size(), added)

    stats = evaluate(base, tokenizer, blocks, CULINARY_TERMS)
    stats["vocab_size"] = tokenizer.get_vocab_size()
    save(tokenizer, args.output_dir, stats)
    print(f"\nTokenizer salvo em: {args.output_dir}")
    return 0 if stats["roundtrip_ok"] else 2


if __name__ == "__main__":
    sys.exit(main())
