#!/usr/bin/env python3
from __future__ import annotations

import argparse
import gzip
import html
import json
import logging
import random
import re
import sys
import time
import unicodedata
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator
from urllib import robotparser
from urllib.parse import urlparse

import pandas as pd
import requests
from bs4 import BeautifulSoup
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_OUTPUT_DIR = BASE_DIR / "data"
SAMPLE_FILE = BASE_DIR / "amostras" / "receitas_exemplo.json"
CSV_NAME = "dados_receitas_brutos.csv"
TXT_NAME = "dados_receitas.txt"
CSV_COLUMNS = ["titulo", "tempo_preparo", "rendimento", "ingredientes", "modo_preparo", "url_fonte"]

USER_AGENT = "PotIA-Bot/1.0 (projeto educacional de NLP; respeita robots.txt)"

logger = logging.getLogger("potia.scraper")


@dataclass
class Recipe:
    titulo: str
    tempo_preparo: str = ""
    rendimento: str = ""
    ingredientes: list[str] = field(default_factory=list)
    modo_preparo: list[str] = field(default_factory=list)
    url_fonte: str = ""

    def is_valid(self) -> bool:
        return bool(self.titulo) and len(self.ingredientes) >= 2 and len(self.modo_preparo) >= 1

    def merged_with(self, other: "Recipe") -> "Recipe":
        return Recipe(
            titulo=self.titulo or other.titulo,
            tempo_preparo=self.tempo_preparo or other.tempo_preparo,
            rendimento=self.rendimento or other.rendimento,
            ingredientes=self.ingredientes or other.ingredientes,
            modo_preparo=self.modo_preparo or other.modo_preparo,
            url_fonte=self.url_fonte or other.url_fonte,
        )

    def to_text(self) -> str:
        lines = [f"Receita: {self.titulo}"]
        if self.tempo_preparo:
            lines.append(f"Tempo de preparo: {self.tempo_preparo}")
        if self.rendimento:
            lines.append(f"Rendimento: {self.rendimento}")
        lines.append("Ingredientes:")
        lines.extend(f"- {item}" for item in self.ingredientes)
        lines.append("Modo de preparo:")
        lines.extend(f"{n}. {step}" for n, step in enumerate(self.modo_preparo, start=1))
        return "\n".join(lines)


_HTML_TAG_RE = re.compile(r"<\s*/?\s*[a-zA-Z][^>]*>")
_HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.DOTALL)

_MOJIBAKE_RE = re.compile(
    "[ÃÂ][\u0080-¿ŒœŠšŸŽžƒ"
    "ˆ˜–—‘-„†-•…‰‹›€™]"
)

_INVISIBLE_RE = re.compile("[­​-‏⁠﻿︎️]")

_EMOJI_RE = re.compile("[\U0001f000-\U0001faff☀-➿⬀-⯿\U0001f1e6-\U0001f1ff]")

_CHAR_TRANSLATION = str.maketrans(
    {
        " ": " ", " ": " ", " ": " ", " ": " ", " ": " ", " ": " ",
        "‘": "'", "’": "'", "‚": "'", "“": '"', "”": '"', "„": '"',
        "«": '"', "»": '"',
        "‐": "-", "‑": "-", "–": "-", "—": "-", "−": "-",
        "…": "...",
        "½": " 1/2", "⅓": " 1/3", "⅔": " 2/3", "¼": " 1/4", "¾": " 3/4", "⅛": " 1/8", "⅕": " 1/5",
        "⁄": "/",
        "×": "x",
    }
)

_DISALLOWED_RE = re.compile(r"[^\w\s.,;:!?()/%°ºª+\-'\"&]")

_REPEATED_PUNCT_RE = re.compile(r"([!?,;:])\1+")
_MANY_DOTS_RE = re.compile(r"\.{4,}")
_SPACE_BEFORE_PUNCT_RE = re.compile(r"[ \t]+([.,;:!?)%])")
_SPACE_AFTER_PAREN_RE = re.compile(r"\([ \t]+")
_EMPTY_PARENS_RE = re.compile(r"\(\s*\)")
_MISSING_SPACE_RE = re.compile(r"([,;:])(?=[^\s\d/)])")
_GLUED_SENTENCE_RE = re.compile(r"(?<=[a-zà-ÿ])\.(?=[A-ZÀ-Ý])")

_BULLET_RE = re.compile(r"^\s*(?:[-+*]+\s*)+")
_STEP_NUMBER_RE = re.compile(r"^\s*(?:passo\s*\d+\s*[:.)\-]?|\d{1,2}\s*[.)º°]\s*|\d{1,2}\s*-\s+)", re.IGNORECASE)

_JUNK_LINES = {"publicidade", "anúncio", "anuncio", "continua após a publicidade", "veja também"}


_MEASURE_KIND = {"sopa": "sopa", "cha": "chá", "chá": "chá", "cafe": "café", "café": "café", "sobremesa": "sobremesa"}

_QTY = r"(?P<qty>\b\d+(?:[.,/]\d+)?(?:\s+(?:e\s+)?\d+/\d+)?\s+)?"

_SPOON_RE = re.compile(
    _QTY
    + r"\b(?P<word>colher(?P<plural>es)?|colh\.|col\.|c\.)\s*(?:\(\s*)?(?:de\s+)?"
    + r"(?P<kind>sopa|ch[aá]|caf[eé]|sobremesa)\b(?:\s*\))?",
    re.IGNORECASE,
)

_CUP_RE = re.compile(
    _QTY
    + r"\b(?P<word>x[ií]caras?|x[ií]c\.|x[ií]c\b)"
    + r"(?:\s*\(\s*(?:de\s+)?(?P<kind>ch[aá]|caf[eé])\s*\)|\s+de\s+(?P<kind2>ch[aá]|caf[eé])\b)?",
    re.IGNORECASE,
)

_UNIT_RE = re.compile(r"\b(\d+(?:[.,]\d+)?)\s*(kg|g|mg|ml|l)\b", re.IGNORECASE)

_SIMPLE_CULINARY_RULES: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\bbanho\s*-?\s*maria\b", re.IGNORECASE), "banho-maria"),
    (re.compile(r"\bcheiro\s*-?\s*verde\b", re.IGNORECASE), "cheiro-verde"),
    (re.compile(r"\bpapel\s*-?\s*manteiga\b", re.IGNORECASE), "papel-manteiga"),
    (re.compile(r"\bpr[eé]\s*-?\s*aquec", re.IGNORECASE), "pré-aquec"),
    (re.compile(r"\bq\.\s?b\.?(?!\w)", re.IGNORECASE), "a gosto"),
    (re.compile(r"\b(\d+)\s*(?:grs?|gramas?)\b", re.IGNORECASE), r"\1 g"),
    (re.compile(r"\b(\d+)\s*[º°]\s*C\b", re.IGNORECASE), r"\1 °C"),
    (re.compile(r"\b(\d+)\s*graus(?:\s+celsius)?\b", re.IGNORECASE), r"\1 °C"),
    (re.compile(r"\bpct\.?(?=\s|$)", re.IGNORECASE), "pacote"),
    (re.compile(r"\bcx\.?(?=\s|$)", re.IGNORECASE), "caixa"),
    (re.compile(r"\baprox\.?(?=\s|$)", re.IGNORECASE), "aproximadamente"),
]


def _quantity_value(qty: str) -> float | None:
    total = 0.0
    for part in qty.strip().replace(",", ".").split():
        if part == "e":
            continue
        try:
            if "/" in part:
                num, _, den = part.partition("/")
                total += float(num) / float(den)
            else:
                total += float(part)
        except (ValueError, ZeroDivisionError):
            return None
    return total


def _is_plural(qty: str, fallback: bool) -> bool:
    value = _quantity_value(qty) if qty.strip() else None
    return fallback if value is None else value >= 2


def _keep_initial_case(original: str, replacement: str) -> str:
    if original[:1].isupper():
        return replacement[:1].upper() + replacement[1:]
    return replacement


def _spoon_repl(match: re.Match[str]) -> str:
    qty = match.group("qty") or ""
    kind = _MEASURE_KIND[match.group("kind").lower()]
    plural = _is_plural(qty, fallback=bool(match.group("plural")))
    return _keep_initial_case(match.group(0), f"{qty}{'colheres' if plural else 'colher'} de {kind}")


def _cup_repl(match: re.Match[str]) -> str:
    qty = match.group("qty") or ""
    kind = match.group("kind") or match.group("kind2")
    plural = _is_plural(qty, fallback=match.group("word").lower().endswith("s"))
    suffix = f" de {_MEASURE_KIND[kind.lower()]}" if kind else ""
    return _keep_initial_case(match.group(0), f"{qty}{'xícaras' if plural else 'xícara'}{suffix}")


def _unit_repl(match: re.Match[str]) -> str:
    unit = match.group(2).lower()
    return f"{match.group(1)} {'L' if unit == 'l' else unit}"


def normalize_culinary_terms(text: str) -> str:
    text = _SPOON_RE.sub(_spoon_repl, text)
    text = _CUP_RE.sub(_cup_repl, text)
    text = _UNIT_RE.sub(_unit_repl, text)
    for pattern, replacement in _SIMPLE_CULINARY_RULES:
        text = pattern.sub(lambda m, r=replacement: _keep_initial_case(m.group(0), m.expand(r)), text)
    return text


def _fix_mojibake(text: str) -> str:
    if not _MOJIBAKE_RE.search(text):
        return text
    for encoding in ("cp1252", "latin-1"):
        try:
            return text.encode(encoding).decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            continue
    return text


def _strip_html(text: str) -> str:
    if "<" not in text:
        return text
    text = _HTML_COMMENT_RE.sub(" ", text)
    if _HTML_TAG_RE.search(text):
        text = BeautifulSoup(text, "html.parser").get_text("\n")
    return text


def _collapse_whitespace(text: str, keep_newlines: bool) -> str:
    if keep_newlines:
        text = re.sub(r"[ \t\r\f\v]+", " ", text)
        text = re.sub(r" *\n *", "\n", text)
        text = re.sub(r"\n{3,}", "\n\n", text)
    else:
        text = re.sub(r"\s+", " ", text)
    return text.strip()


def clean_text(text: Any, *, keep_newlines: bool = False, normalize_culinary: bool = True) -> str:
    if text is None:
        return ""
    if isinstance(text, float) and text != text:
        return ""
    text = str(text)

    text = html.unescape(html.unescape(text))
    text = _strip_html(text)

    text = _fix_mojibake(text)
    text = unicodedata.normalize("NFC", text)
    text = _INVISIBLE_RE.sub("", text)

    text = text.translate(_CHAR_TRANSLATION)
    text = _EMOJI_RE.sub(" ", text)
    text = text.replace("_", " ")
    text = _DISALLOWED_RE.sub(" ", text)

    text = _REPEATED_PUNCT_RE.sub(r"\1", text)
    text = _MANY_DOTS_RE.sub("...", text)
    text = _EMPTY_PARENS_RE.sub(" ", text)
    text = _SPACE_AFTER_PAREN_RE.sub("(", text)
    text = _SPACE_BEFORE_PUNCT_RE.sub(r"\1", text)
    text = _MISSING_SPACE_RE.sub(r"\1 ", text)
    text = _GLUED_SENTENCE_RE.sub(". ", text)

    if normalize_culinary:
        text = normalize_culinary_terms(text)

    return _collapse_whitespace(text, keep_newlines)


def _capitalize_first(text: str) -> str:
    return text[:1].upper() + text[1:] if text else text


def clean_list_item(raw: Any, kind: str) -> str:
    text = clean_text(raw)
    text = _BULLET_RE.sub("", text)
    if kind == "step":
        text = _STEP_NUMBER_RE.sub("", text)
        text = _capitalize_first(text.strip())
        if text and text[-1].isalnum():
            text += "."
    else:
        text = text.rstrip(" ;.")
    return text.strip()


def clean_items(raw_items: Iterable[Any], kind: str) -> list[str]:
    items: list[str] = []
    for raw in raw_items:
        item = clean_list_item(raw, kind)
        if len(item) < 2 or item.lower().rstrip(":") in _JUNK_LINES:
            continue
        if items and items[-1].lower() == item.lower():
            continue
        items.append(item)
    return items


_TITLE_PREFIX_RE = re.compile(r"^receita\s+(?:de|da|do)\s+", re.IGNORECASE)


def clean_title(raw: Any, *, from_page_title: bool = False) -> str:
    text = clean_text(raw, normalize_culinary=False)
    if from_page_title:
        text = re.split(r"\s+[|\-]\s+", text)[0]
    text = _TITLE_PREFIX_RE.sub("", text).strip(" .:-")
    return _capitalize_first(text)


_ISO_DURATION_RE = re.compile(
    r"^P(?:(?P<d>\d+)D)?(?:T(?:(?P<h>\d+)H)?(?:(?P<m>\d+)M)?(?:(?P<s>\d+(?:\.\d+)?)S)?)?$",
    re.IGNORECASE,
)
_TEXT_HOUR_MIN_RE = re.compile(r"(\d+)\s*h\s*(\d{1,2})(?!\s*(?:h|\d))", re.IGNORECASE)
_TEXT_HOURS_RE = re.compile(r"(\d+)\s*(?:h|hr|hrs|hora|horas)\b", re.IGNORECASE)
_TEXT_MINUTES_RE = re.compile(r"(\d+)\s*(?:min|mins|minuto|minutos|m)\b", re.IGNORECASE)


def parse_duration_minutes(value: Any) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return int(value) if value > 0 else None
    text = str(value).strip()

    match = _ISO_DURATION_RE.match(text)
    if match and any(match.groupdict().values()):
        days, hours, minutes, seconds = (float(match.group(k) or 0) for k in "dhms")
        total = round(days * 1440 + hours * 60 + minutes + seconds / 60)
        return total or None

    compact = _TEXT_HOUR_MIN_RE.search(text)
    if compact:
        return int(compact.group(1)) * 60 + int(compact.group(2))

    total = sum(int(h) for h in _TEXT_HOURS_RE.findall(text)) * 60
    total += sum(int(m) for m in _TEXT_MINUTES_RE.findall(text))
    return total or None


def format_minutes(total: int) -> str:
    hours, minutes = divmod(total, 60)
    if hours and minutes:
        return f"{hours} h {minutes} min"
    if hours:
        return f"{hours} h"
    return f"{minutes} min"


def extract_prep_time(node: dict[str, Any]) -> str:
    total = parse_duration_minutes(node.get("totalTime"))
    if not total:
        prep = parse_duration_minutes(node.get("prepTime")) or 0
        cook = parse_duration_minutes(node.get("cookTime")) or 0
        total = prep + cook
    return format_minutes(total) if total else ""


def normalize_yield(value: Any) -> str:
    if value is None or value == "":
        return ""
    if isinstance(value, (list, tuple)):
        candidates = [clean_text(v) for v in value if v not in (None, "")]
        textual = [c for c in candidates if re.search(r"[^\W\d_]", c)]
        value = (textual or candidates or [""])[0]
    text = clean_text(value)
    if re.fullmatch(r"\d+(?:[.,]\d+)?", text):
        text = f"{text} porção" if text == "1" else f"{text} porções"
    return text


def _type_matches(node: dict[str, Any], wanted: str) -> bool:
    types = node.get("@type")
    if types is None:
        return False
    if isinstance(types, str):
        types = [types]
    wanted = wanted.lower()
    return any(
        isinstance(t, str) and t.rsplit("/", 1)[-1].rsplit(":", 1)[-1].lower() == wanted for t in types
    )


def _walk_json(node: Any) -> Iterator[dict[str, Any]]:
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk_json(value)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_json(item)


def _load_json_lenient(raw: str) -> Any | None:
    raw = raw.strip()
    if not raw:
        return None
    raw = re.sub(r"^\s*(?://\s*)?<!\[CDATA\[|(?://\s*)?\]\]>\s*$", "", raw)
    without_controls = re.sub(r"[\x00-\x1f]+", " ", raw)
    without_trailing_commas = re.sub(r",\s*([}\]])", r"\1", without_controls)
    for candidate in (raw, without_controls, without_trailing_commas):
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    return None


def find_recipe_jsonld(soup: BeautifulSoup) -> dict[str, Any] | None:
    for script in soup.find_all("script", attrs={"type": re.compile(r"ld\+json", re.IGNORECASE)}):
        data = _load_json_lenient(script.string or script.get_text() or "")
        if data is None:
            continue
        for node in _walk_json(data):
            if _type_matches(node, "Recipe"):
                return node
    return None


def _flatten_instructions(node: Any) -> list[str]:
    if node is None:
        return []
    if isinstance(node, str):
        text = node
        if _HTML_TAG_RE.search(text):
            soup = BeautifulSoup(text, "html.parser")
            items = [el.get_text(" ", strip=True) for el in soup.find_all(["li", "p"])]
            items = [item for item in items if item]
            if items:
                return items
            text = soup.get_text("\n")
        parts = [p for p in re.split(r"\n+", text) if p.strip()]
        if len(parts) == 1:
            parts = [p for p in re.split(r"\s+(?=\d{1,2}[.)]\s)", parts[0]) if p.strip()]
        return parts
    if isinstance(node, list):
        steps: list[str] = []
        for item in node:
            steps.extend(_flatten_instructions(item))
        return steps
    if isinstance(node, dict):
        if _type_matches(node, "HowToSection") or "itemListElement" in node:
            steps = _flatten_instructions(node.get("itemListElement"))
            section = clean_text(node.get("name"), normalize_culinary=False)
            if section and steps and _type_matches(node, "HowToSection"):
                steps[0] = f"{section.rstrip(':')}: {steps[0]}"
            return steps
        text = node.get("text") or node.get("name") or node.get("description")
        return _flatten_instructions(text) if text else []
    return []


def recipe_from_jsonld(node: dict[str, Any], url: str = "") -> Recipe:
    ingredients = node.get("recipeIngredient") or node.get("ingredients") or []
    if isinstance(ingredients, str):
        ingredients = re.split(r"\n+", _strip_html(ingredients))
    return Recipe(
        titulo=clean_title(node.get("name") or node.get("headline") or ""),
        tempo_preparo=extract_prep_time(node),
        rendimento=normalize_yield(node.get("recipeYield") or node.get("yield")),
        ingredientes=clean_items(ingredients, "ingredient"),
        modo_preparo=clean_items(_flatten_instructions(node.get("recipeInstructions")), "step"),
        url_fonte=url,
    )


_INGREDIENT_SELECTORS = [
    "[itemprop=recipeIngredient]",
    "[itemprop=ingredients]",
    "[class*=ingredient] li",
    "[id*=ingredient] li",
    "[class*=ingrediente] li",
    "[id*=ingrediente] li",
]
_STEP_SELECTORS = [
    "[itemprop=recipeInstructions] li",
    "[itemprop=recipeInstructions] p",
    "[class*=instruction] li",
    "[class*=preparo] li",
    "[id*=preparo] li",
    "[class*=direction] li",
    "[class*=method] li",
    "[class*=step] li",
]


def _select_texts(soup: BeautifulSoup, selectors: list[str]) -> list[str]:
    for selector in selectors:
        try:
            elements = soup.select(selector)
        except Exception:
            continue
        texts = [el.get_text(" ", strip=True) for el in elements]
        texts = [t for t in texts if t]
        if texts:
            return texts
    return []


def recipe_from_html(soup: BeautifulSoup, url: str = "") -> Recipe:
    title_el = soup.select_one("[itemprop=name]") or soup.find("h1")
    title = clean_title(title_el.get_text(" ", strip=True)) if title_el else ""
    if not title:
        og_title = soup.find("meta", attrs={"property": "og:title"})
        raw = og_title.get("content", "") if og_title else (soup.title.get_text() if soup.title else "")
        title = clean_title(raw, from_page_title=True)

    steps = _select_texts(soup, _STEP_SELECTORS)
    if not steps:
        block = soup.select_one("[itemprop=recipeInstructions]")
        if block:
            steps = block.get_text("\n").split("\n")

    time_value = ""
    for prop in ("totalTime", "prepTime", "cookTime"):
        el = soup.select_one(f"[itemprop={prop}]")
        if el:
            minutes = parse_duration_minutes(el.get("content") or el.get("datetime") or el.get_text(" ", strip=True))
            if minutes:
                time_value = format_minutes(minutes)
                break

    yield_el = soup.select_one("[itemprop=recipeYield]")
    yield_value = (yield_el.get("content") or yield_el.get_text(" ", strip=True)) if yield_el else ""

    return Recipe(
        titulo=title,
        tempo_preparo=time_value,
        rendimento=normalize_yield(yield_value),
        ingredientes=clean_items(_select_texts(soup, _INGREDIENT_SELECTORS), "ingredient"),
        modo_preparo=clean_items(steps, "step"),
        url_fonte=url,
    )


def parse_recipe_html(content: bytes | str, url: str = "") -> Recipe | None:
    soup = BeautifulSoup(content, "html.parser")

    node = find_recipe_jsonld(soup)
    primary = recipe_from_jsonld(node, url) if node else None
    if primary and primary.is_valid():
        return primary

    for tag in soup(["script", "style", "noscript", "iframe", "svg", "nav", "footer", "aside"]):
        tag.decompose()
    fallback = recipe_from_html(soup, url)
    return primary.merged_with(fallback) if primary else fallback


class RecipeScraper:
    def __init__(self, delay: float = 2.0, timeout: float = 20.0, user_agent: str = USER_AGENT) -> None:
        self.delay = delay
        self.timeout = timeout
        self.user_agent = user_agent
        self.session = self._build_session()
        self._robots: dict[str, robotparser.RobotFileParser] = {}
        self._last_request_at: dict[str, float] = {}

    def _build_session(self) -> requests.Session:
        session = requests.Session()
        retry = Retry(
            total=3,
            backoff_factor=1.5,
            status_forcelist=(429, 500, 502, 503, 504),
            allowed_methods=("GET", "HEAD"),
            respect_retry_after_header=True,
            raise_on_status=False,
        )
        adapter = HTTPAdapter(max_retries=retry)
        session.mount("http://", adapter)
        session.mount("https://", adapter)
        session.headers.update(
            {
                "User-Agent": self.user_agent,
                "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "Accept-Language": "pt-BR,pt;q=0.9",
            }
        )
        return session

    def _robots_for(self, url: str) -> robotparser.RobotFileParser:
        parsed = urlparse(url)
        base = f"{parsed.scheme}://{parsed.netloc}"
        if base in self._robots:
            return self._robots[base]

        parser = robotparser.RobotFileParser()
        robots_url = f"{base}/robots.txt"
        try:
            response = self.session.get(robots_url, timeout=self.timeout)
            if response.status_code >= 500:
                parser.disallow_all = True
            elif response.status_code >= 400:
                parser.allow_all = True
            else:
                parser.parse(response.text.splitlines())
        except requests.RequestException as exc:
            logger.warning("Não foi possível ler %s (%s). O domínio será ignorado.", robots_url, exc)
            parser.disallow_all = True

        self._robots[base] = parser
        return parser

    def can_fetch(self, url: str) -> bool:
        return self._robots_for(url).can_fetch(self.user_agent, url)

    def _wait_politely(self, url: str) -> None:
        domain = urlparse(url).netloc
        crawl_delay = self._robots_for(url).crawl_delay(self.user_agent) or 0
        delay = max(self.delay, float(crawl_delay))
        elapsed = time.monotonic() - self._last_request_at.get(domain, float("-inf"))
        wait = delay * random.uniform(0.8, 1.3) - elapsed
        if wait > 0:
            time.sleep(wait)
        self._last_request_at[domain] = time.monotonic()

    def fetch(self, url: str, *, expect_html: bool = True) -> bytes | None:
        if not self.can_fetch(url):
            logger.warning("robots.txt não permite acessar %s — pulando.", url)
            return None
        self._wait_politely(url)
        try:
            response = self.session.get(url, timeout=self.timeout)
        except requests.RequestException as exc:
            logger.error("Falha de rede em %s: %s", url, exc)
            return None
        if response.status_code != 200:
            logger.error("HTTP %s em %s", response.status_code, url)
            return None
        content_type = response.headers.get("Content-Type", "")
        if expect_html and content_type and "html" not in content_type:
            logger.warning("Conteúdo não-HTML (%s) em %s — pulando.", content_type, url)
            return None
        return response.content

    def scrape(self, url: str) -> Recipe | None:
        content = self.fetch(url)
        if content is None:
            return None
        recipe = parse_recipe_html(content, url)
        if recipe is None or not recipe.is_valid():
            logger.warning("Nenhuma receita completa encontrada em %s", url)
            return None
        return recipe

    def discover_from_sitemap(
        self,
        sitemap_url: str,
        pattern: str | None = None,
        limit: int = 100,
        *,
        max_child_sitemaps: int = 20,
        _depth: int = 0,
    ) -> list[str]:
        if _depth > 3 or limit <= 0:
            return []
        content = self.fetch(sitemap_url, expect_html=False)
        if content is None:
            return []
        if content[:2] == b"\x1f\x8b":
            try:
                content = gzip.decompress(content)
            except OSError as exc:
                logger.error("Sitemap compactado inválido em %s: %s", sitemap_url, exc)
                return []
        try:
            root = ET.fromstring(content)
        except ET.ParseError as exc:
            logger.error("XML inválido em %s: %s", sitemap_url, exc)
            return []

        def local_name(tag: str) -> str:
            return tag.rsplit("}", 1)[-1].lower()

        locs = [el.text.strip() for el in root.iter() if local_name(el.tag) == "loc" and el.text]
        regex = re.compile(pattern) if pattern else None
        urls: list[str] = []

        if local_name(root.tag) == "sitemapindex":
            for child in locs[:max_child_sitemaps]:
                if len(urls) >= limit:
                    break
                urls.extend(
                    self.discover_from_sitemap(
                        child, pattern, limit - len(urls), max_child_sitemaps=max_child_sitemaps, _depth=_depth + 1
                    )
                )
        else:
            for loc in locs:
                if regex is None or regex.search(loc):
                    urls.append(loc)
                    if len(urls) >= limit:
                        break
        return urls


def load_sample_recipes(path: Path = SAMPLE_FILE) -> list[Recipe]:
    if not path.exists():
        logger.error("Arquivo de exemplo não encontrado: %s", path)
        return []
    documents = json.loads(path.read_text(encoding="utf-8"))
    recipes = []
    for document in documents:
        node = next((n for n in _walk_json(document) if _type_matches(n, "Recipe")), None)
        if node:
            recipes.append(recipe_from_jsonld(node, node.get("url", "")))
    return [r for r in recipes if r.is_valid()]


def read_urls_file(path: Path) -> list[str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    return [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]


def load_recipes_csv(path: Path) -> list[Recipe]:
    df = pd.read_csv(path, encoding="utf-8-sig", dtype=str, keep_default_na=False)
    recipes = []
    for row in df.to_dict("records"):
        recipes.append(
            Recipe(
                titulo=row.get("titulo", ""),
                tempo_preparo=row.get("tempo_preparo", ""),
                rendimento=row.get("rendimento", ""),
                ingredientes=json.loads(row.get("ingredientes") or "[]"),
                modo_preparo=json.loads(row.get("modo_preparo") or "[]"),
                url_fonte=row.get("url_fonte", ""),
            )
        )
    return recipes


def _dedupe_key(text: str) -> str:
    no_accents = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return re.sub(r"\W+", " ", no_accents).strip().lower()


def deduplicate(recipes: Iterable[Recipe]) -> list[Recipe]:
    seen: set[str] = set()
    unique: list[Recipe] = []
    for recipe in recipes:
        content_key = _dedupe_key(recipe.titulo) + "|" + "|".join(sorted(map(_dedupe_key, recipe.ingredientes)))
        url_key = recipe.url_fonte.strip().rstrip("/").lower()
        keys = {content_key} | ({url_key} if url_key else set())
        if keys & seen:
            continue
        seen |= keys
        unique.append(recipe)
    return unique


def save_outputs(recipes: list[Recipe], output_dir: Path, *, append: bool = False) -> tuple[Path, Path, int]:
    output_dir.mkdir(parents=True, exist_ok=True)
    csv_path = output_dir / CSV_NAME
    txt_path = output_dir / TXT_NAME

    if append and csv_path.exists():
        recipes = load_recipes_csv(csv_path) + recipes
    recipes = deduplicate(recipes)

    df = pd.DataFrame([asdict(r) for r in recipes], columns=CSV_COLUMNS)
    for column in ("ingredientes", "modo_preparo"):
        df[column] = df[column].apply(lambda items: json.dumps(items, ensure_ascii=False))
    df.to_csv(csv_path, index=False, encoding="utf-8-sig")

    corpus = "\n\n".join(r.to_text() for r in recipes)
    txt_path.write_text(corpus + "\n", encoding="utf-8")
    return csv_path, txt_path, len(recipes)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="PotIA — Fase 1: raspagem e limpeza de receitas em português.",
    )
    parser.add_argument("--urls", nargs="*", default=[], help="URLs de páginas de receitas.")
    parser.add_argument("--urls-file", type=Path, help="Arquivo .txt com uma URL por linha (# = comentário).")
    parser.add_argument("--sitemap", help="URL de um sitemap.xml para descobrir receitas automaticamente.")
    parser.add_argument("--pattern", default="receita", help="Regex que a URL do sitemap precisa conter.")
    parser.add_argument("--limit", type=int, default=100, help="Máximo de URLs descobertas via sitemap.")
    parser.add_argument("--sample", action="store_true", help="Inclui as receitas de exemplo locais (funciona offline).")
    parser.add_argument("--delay", type=float, default=2.0, help="Segundos mínimos entre requisições ao mesmo domínio.")
    parser.add_argument("--timeout", type=float, default=20.0, help="Timeout de cada requisição (s).")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR, help="Pasta de saída.")
    parser.add_argument("--append", action="store_true", help="Acrescenta ao CSV existente em vez de sobrescrever.")
    parser.add_argument("-v", "--verbose", action="store_true", help="Logs detalhados.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s | %(levelname)-7s | %(message)s",
        datefmt="%H:%M:%S",
    )

    scraper = RecipeScraper(delay=args.delay, timeout=args.timeout)
    urls: list[str] = list(args.urls)
    if args.urls_file:
        if not args.urls_file.exists():
            logger.error("Arquivo de URLs não encontrado: %s", args.urls_file)
            return 1
        urls += read_urls_file(args.urls_file)
    if args.sitemap:
        logger.info("Descobrindo URLs no sitemap %s ...", args.sitemap)
        discovered = scraper.discover_from_sitemap(args.sitemap, args.pattern, args.limit)
        logger.info("%d URLs encontradas no sitemap.", len(discovered))
        urls += discovered
    urls = list(dict.fromkeys(urls))

    if not urls and not args.sample:
        logger.error("Nada para fazer. Informe --urls, --urls-file, --sitemap ou --sample.")
        return 1

    recipes: list[Recipe] = []
    if args.sample:
        samples = load_sample_recipes()
        logger.info("%d receitas de exemplo carregadas.", len(samples))
        recipes.extend(samples)

    failures = 0
    for index, url in enumerate(urls, start=1):
        logger.info("[%d/%d] %s", index, len(urls), url)
        try:
            recipe = scraper.scrape(url)
        except Exception:
            logger.exception("Erro inesperado ao processar %s", url)
            recipe = None
        if recipe:
            recipes.append(recipe)
            logger.info("   ✓ %s (%d ingredientes, %d passos)", recipe.titulo, len(recipe.ingredientes), len(recipe.modo_preparo))
        else:
            failures += 1

    if not recipes:
        logger.error("Nenhuma receita válida foi coletada.")
        return 1

    csv_path, txt_path, total = save_outputs(recipes, args.output_dir, append=args.append)
    logger.info("Concluído: %d receitas salvas (%d páginas falharam).", total, failures)
    logger.info("CSV:   %s", csv_path)
    logger.info("Texto: %s", txt_path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
