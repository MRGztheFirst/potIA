#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import logging
import random
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

import pandas as pd

BASE_DIR = Path(__file__).resolve().parent
DEFAULT_INPUT = BASE_DIR / "data" / "dados_receitas_brutos.csv"
DEFAULT_TRAIN = BASE_DIR / "data" / "potia_train.jsonl"
DEFAULT_VAL = BASE_DIR / "data" / "potia_val.jsonl"

SYSTEM_PROMPT = (
    "Você é a PotIA, uma assistente culinária brasileira simpática, paciente e precisa. "
    "Responda sempre em português do Brasil, em texto simples, sem Markdown (nada de #, ** ou tabelas).\n\n"
    "Ao passar uma receita, prefira a versão tradicional brasileira do prato, comece com uma frase curta "
    "e siga este formato:\n"
    "⏱️ Tempo de preparo: ...\n"
    "🍽️ Rendimento: ...\n\n"
    "Ingredientes:\n"
    "• quantidade e ingrediente\n\n"
    "Modo de preparo:\n"
    "1. passo\n\n"
    "Use medidas caseiras (xícara, colher de sopa) ou gramas. Se não tiver certeza de algo, diga isso com "
    "honestidade e sugira alternativas seguras. Se a pergunta não for sobre culinária, responda em poucas "
    "palavras e traga a conversa de volta para a cozinha."
)

logger = logging.getLogger("potia.dataset")


@dataclass
class RecipeRow:
    titulo: str
    tempo_preparo: str
    rendimento: str
    ingredientes: list[str]
    modo_preparo: list[str]

    @property
    def name_in_sentence(self) -> str:
        title = self.titulo
        if len(title) > 1 and title[0].isupper() and not title[1].isupper():
            return title[0].lower() + title[1:]
        return title

    @property
    def has_meta(self) -> bool:
        return bool(self.tempo_preparo or self.rendimento)


Q_FULL = [
    "Como fazer {nome}?",
    "Me ensina a fazer {nome}?",
    "Qual é a receita de {nome}?",
    "Quero preparar {nome}. Pode me passar a receita?",
    "Receita de {nome}, por favor!",
    "Como eu preparo {nome} em casa?",
    "Me dá o passo a passo completo de {nome}.",
]
Q_INGREDIENTS = [
    "Quais ingredientes eu preciso para fazer {nome}?",
    "O que vai na receita de {nome}?",
    "Me passa a lista de ingredientes de {nome}.",
    "Vou ao mercado. Do que preciso para fazer {nome}?",
]
Q_STEPS = [
    "Já separei os ingredientes. Qual é o modo de preparo de {nome}?",
    "Como é o passo a passo de {nome}?",
    "Me explica como montar {nome}, só o modo de preparo.",
]
Q_META = [
    "Quanto tempo leva para fazer {nome} e quanto rende?",
    "{nome_cap} demora muito? Serve quantas pessoas?",
    "Qual o tempo de preparo e o rendimento de {nome}?",
]
Q_PANTRY = [
    "Tenho {lista} em casa. O que posso cozinhar?",
    "O que dá para fazer com {lista}?",
    "Estou com {lista} sobrando. Alguma ideia de receita?",
]
Q_FOLLOW_UP = [
    "E quanto tempo isso demora?",
    "Legal! Quanto tempo leva e quanto rende?",
    "Show! Serve quantas pessoas?",
]

INTROS = [
    "Claro! Aqui está a receita de {nome}.",
    "Com certeza! Vamos preparar {nome} juntos.",
    "Ótima escolha! Veja como fazer {nome}.",
    "Vamos lá! Esta é a minha receita de {nome}.",
]
OUTROS = [
    "Bom apetite!",
    "Qualquer dúvida no preparo, é só me chamar!",
    "Espero que fique delicioso!",
    "Depois me conta como ficou!",
]

_PANTRY_STAPLES = ("sal", "água", "agua", "óleo", "oleo", "pimenta", "azeite", "fermento")
_QUANTITY_PREFIX_RE = re.compile(
    r"^(?:[\d\s/.,]+|uma?|meia|meio|duas|dois|três)?\s*"
    r"(?:(?:colheres|colher|xícaras|xícara|copos?|kg|g|mg|ml|L|litros?|gramas?|latas?|caixas?|caixinhas?|"
    r"pacotes?|pitadas?|dentes?|fatias?|ramos?|maços?|unidades?|tabletes?|potes?|envelopes?|sachês?)\b"
    r"(?:\s+(?:de\s+)?(?:sopa|chá|café|sobremesa))?(?:\s+americanos?)?\s*)?"
    r"(?:de\s+|da\s+|do\s+)?",
    re.IGNORECASE,
)


_DESCRIPTOR_SPLIT_RE = re.compile(
    r"[,(]|\s(?:a gosto|para|em|sem casca|picad\w*|ralad\w*|descascad\w*|amassad\w*|médi\w*|"
    r"grand\w*|pequen\w*|cozid\w*|derretid\w*|fervent\w*|fresc\w*|madur\w*)\b",
    re.IGNORECASE,
)
_ARTICLES = ("a", "o", "as", "os")


def _join_pt(items: list[str]) -> str:
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " e " + items[-1]


def main_ingredients(recipe: RecipeRow, limit: int = 3) -> list[str]:
    names: list[str] = []
    for item in recipe.ingredientes:
        if item.endswith(":"):
            continue
        name = _QUANTITY_PREFIX_RE.sub("", item).strip()
        name = _DESCRIPTOR_SPLIT_RE.split(name, maxsplit=1)[0].strip()
        words = name.split()
        if not words or words[0].lower() in _PANTRY_STAPLES + _ARTICLES:
            continue
        name = " ".join(words[:3]).lower()
        if len(name) > 2 and name not in names:
            names.append(name)
        if len(names) == limit:
            break
    return names


def meta_lines(recipe: RecipeRow) -> list[str]:
    lines = []
    if recipe.tempo_preparo:
        lines.append(f"⏱️ Tempo de preparo: {recipe.tempo_preparo}")
    if recipe.rendimento:
        lines.append(f"🍽️ Rendimento: {recipe.rendimento}")
    return lines


def ingredient_lines(recipe: RecipeRow) -> list[str]:
    lines: list[str] = []
    for item in recipe.ingredientes:
        if item.endswith(":"):
            lines += ([""] if lines else []) + [item]
        else:
            lines.append(f"• {item}")
    return lines


def ingredients_block(recipe: RecipeRow) -> list[str]:
    return ["Ingredientes:"] + ingredient_lines(recipe)


def steps_block(recipe: RecipeRow) -> list[str]:
    return ["Modo de preparo:"] + [f"{n}. {step}" for n, step in enumerate(recipe.modo_preparo, start=1)]


def recipe_body(recipe: RecipeRow) -> str:
    parts: list[str] = []
    if recipe.has_meta:
        parts += meta_lines(recipe) + [""]
    parts += ingredients_block(recipe) + [""] + steps_block(recipe)
    return "\n".join(parts)


def answer_full(recipe: RecipeRow, rng: random.Random) -> str:
    intro = rng.choice(INTROS).format(nome=recipe.name_in_sentence)
    return f"{intro}\n\n{recipe_body(recipe)}\n\n{rng.choice(OUTROS)}"


def answer_ingredients(recipe: RecipeRow, rng: random.Random) -> str:
    lines = [f"Para fazer {recipe.name_in_sentence} você vai precisar de:", ""]
    lines += ingredient_lines(recipe)
    if recipe.rendimento:
        lines += ["", f"Essa receita rende {recipe.rendimento}."]
    lines += ["", "Se quiser, também te passo o modo de preparo!"]
    return "\n".join(lines)


def answer_steps(recipe: RecipeRow, rng: random.Random) -> str:
    lines = [f"Perfeito! Este é o modo de preparo de {recipe.name_in_sentence}:", ""]
    lines += [f"{n}. {step}" for n, step in enumerate(recipe.modo_preparo, start=1)]
    lines += ["", rng.choice(OUTROS)]
    return "\n".join(lines)


def answer_meta(recipe: RecipeRow, rng: random.Random) -> str:
    name = recipe.name_in_sentence
    if recipe.tempo_preparo and recipe.rendimento:
        return f"O preparo de {name} leva cerca de {recipe.tempo_preparo} e a receita rende {recipe.rendimento}."
    if recipe.tempo_preparo:
        return f"O preparo de {name} leva cerca de {recipe.tempo_preparo}. O rendimento varia conforme o tamanho das porções."
    return f"A receita de {name} rende {recipe.rendimento}. O tempo de preparo depende do seu fogão e dos utensílios."


def answer_pantry(recipe: RecipeRow, rng: random.Random, available: list[str]) -> str:
    return (
        f"Com {_join_pt(available)} dá para fazer {recipe.name_in_sentence}! "
        f"Confira a lista completa, porque a receita leva mais alguns itens:\n\n"
        f"{recipe_body(recipe)}\n\n{rng.choice(OUTROS)}"
    )


Messages = list[dict[str, str]]


def _conversation(*turns: tuple[str, str]) -> Messages:
    return [{"role": "system", "content": SYSTEM_PROMPT}] + [{"role": r, "content": c} for r, c in turns]


def _question(templates: list[str], recipe: RecipeRow, rng: random.Random, **extra: str) -> str:
    nome = recipe.name_in_sentence
    return rng.choice(templates).format(nome=nome, nome_cap=nome[:1].upper() + nome[1:], **extra)


def build_examples(recipe: RecipeRow, rng: random.Random, samples_per_recipe: int) -> list[Messages]:
    def full() -> Messages:
        return _conversation(("user", _question(Q_FULL, recipe, rng)), ("assistant", answer_full(recipe, rng)))

    def ingredients() -> Messages:
        return _conversation(
            ("user", _question(Q_INGREDIENTS, recipe, rng)), ("assistant", answer_ingredients(recipe, rng))
        )

    def steps() -> Messages:
        return _conversation(("user", _question(Q_STEPS, recipe, rng)), ("assistant", answer_steps(recipe, rng)))

    def meta() -> Messages:
        return _conversation(("user", _question(Q_META, recipe, rng)), ("assistant", answer_meta(recipe, rng)))

    def pantry() -> Messages:
        available = main_ingredients(recipe)
        question = rng.choice(Q_PANTRY).format(lista=_join_pt(available))
        return _conversation(("user", question), ("assistant", answer_pantry(recipe, rng, available)))

    def follow_up() -> Messages:
        return _conversation(
            ("user", _question(Q_FULL, recipe, rng)),
            ("assistant", answer_full(recipe, rng)),
            ("user", rng.choice(Q_FOLLOW_UP)),
            ("assistant", answer_meta(recipe, rng)),
        )

    optional: list[Callable[[], Messages]] = [ingredients, steps]
    if recipe.has_meta:
        optional += [meta, follow_up]
    if len(main_ingredients(recipe)) >= 2:
        optional.append(pantry)
    rng.shuffle(optional)
    tasks = [full] + optional[: max(0, samples_per_recipe - 1)]
    return [task() for task in tasks]


def validate_example(messages: Messages) -> None:
    if not messages or messages[0]["role"] != "system":
        raise ValueError("a conversa deve começar com a mensagem de sistema")
    turns = messages[1:]
    if len(turns) < 2 or len(turns) % 2:
        raise ValueError("a conversa deve ter pares user/assistant")
    for index, message in enumerate(turns):
        expected = "user" if index % 2 == 0 else "assistant"
        if message["role"] != expected:
            raise ValueError(f"papel inesperado na posição {index + 1}: {message['role']}")
        if not isinstance(message["content"], str) or not message["content"].strip():
            raise ValueError("mensagem vazia")


def load_recipes(path: Path) -> list[RecipeRow]:
    df = pd.read_csv(path, encoding="utf-8-sig", dtype=str, keep_default_na=False)
    missing = {"titulo", "ingredientes", "modo_preparo"} - set(df.columns)
    if missing:
        raise ValueError(f"colunas ausentes no CSV: {sorted(missing)}")

    recipes: list[RecipeRow] = []
    for line_number, row in enumerate(df.to_dict("records"), start=2):
        try:
            recipe = RecipeRow(
                titulo=row["titulo"].strip(),
                tempo_preparo=row.get("tempo_preparo", "").strip(),
                rendimento=row.get("rendimento", "").strip(),
                ingredientes=json.loads(row["ingredientes"] or "[]"),
                modo_preparo=json.loads(row["modo_preparo"] or "[]"),
            )
        except json.JSONDecodeError as exc:
            logger.warning("Linha %d ignorada (JSON inválido): %s", line_number, exc)
            continue
        if recipe.titulo and recipe.ingredientes and recipe.modo_preparo:
            recipes.append(recipe)
    return recipes


def split_recipes(recipes: list[RecipeRow], val_ratio: float, rng: random.Random) -> tuple[list[RecipeRow], list[RecipeRow]]:
    shuffled = recipes[:]
    rng.shuffle(shuffled)
    n_val = round(len(shuffled) * val_ratio) if len(shuffled) >= 2 else 0
    n_val = max(1, n_val) if val_ratio > 0 and len(shuffled) >= 2 else n_val
    return shuffled[n_val:], shuffled[:n_val]


def write_jsonl(path: Path, conversations: list[Messages]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for messages in conversations:
            handle.write(json.dumps({"messages": messages}, ensure_ascii=False) + "\n")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="PotIA — Fase 2b: gera o dataset ChatML/JSONL.")
    parser.add_argument("--input", type=Path, default=DEFAULT_INPUT, help="CSV gerado na Fase 1.")
    parser.add_argument("--train-output", type=Path, default=DEFAULT_TRAIN)
    parser.add_argument("--val-output", type=Path, default=DEFAULT_VAL)
    parser.add_argument("--samples-per-recipe", type=int, default=3, help="Conversas geradas por receita (1 a 6).")
    parser.add_argument("--val-ratio", type=float, default=0.1, help="Fração das receitas reservada para validação.")
    parser.add_argument("--seed", type=int, default=42, help="Semente para resultados reproduzíveis.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    logging.basicConfig(level=logging.INFO, format="%(levelname)s | %(message)s")
    args = parse_args(argv)

    if not args.input.exists():
        logger.error("CSV não encontrado em %s. Rode antes a Fase 1 (scraper_potia.py).", args.input)
        return 1
    if not 0 <= args.val_ratio < 1:
        logger.error("--val-ratio deve estar entre 0 e 1.")
        return 1

    rng = random.Random(args.seed)
    recipes = load_recipes(args.input)
    if not recipes:
        logger.error("Nenhuma receita válida no CSV.")
        return 1

    train_recipes, val_recipes = split_recipes(recipes, args.val_ratio, rng)
    samples = max(1, min(args.samples_per_recipe, 6))

    datasets: dict[str, list[Messages]] = {"train": [], "val": []}
    for split, split_recipes_ in (("train", train_recipes), ("val", val_recipes)):
        for recipe in split_recipes_:
            for messages in build_examples(recipe, rng, samples):
                try:
                    validate_example(messages)
                except ValueError as exc:
                    logger.warning("Exemplo descartado (%s): %s", recipe.titulo, exc)
                    continue
                datasets[split].append(messages)
        rng.shuffle(datasets[split])

    write_jsonl(args.train_output, datasets["train"])
    write_jsonl(args.val_output, datasets["val"])

    logger.info("Receitas: %d treino / %d validação", len(train_recipes), len(val_recipes))
    logger.info("Conversas: %d treino → %s", len(datasets["train"]), args.train_output)
    logger.info("Conversas: %d validação → %s", len(datasets["val"]), args.val_output)
    if datasets["train"]:
        print("\n=== Exemplo de conversa gerada ===")
        print(json.dumps(datasets["train"][0], ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
