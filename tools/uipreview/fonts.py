"""Fuentes aproximadas para las fuentes de Roblox y medicion de texto.

Roblox -> archivo local (tools/uipreview/fonts):
  FredokaOne            -> Fredoka (variable, peso 600; muy parecida a FredokaOne)
  LuckiestGuy           -> LuckiestGuy
  Bangers               -> Bangers
  Gotham / GothamSSm    -> Montserrat (variable, peso segun FontWeight)
  el resto (Legacy, SourceSans, Arial, BuilderSans, Roboto...) -> Source Sans 3
Emoji: Noto Color Emoji del sistema si existe (si no, se dibuja una cajita).
"""
from __future__ import annotations

import functools
import os
import re

from PIL import ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.join(HERE, "fonts")

# key -> (file, variation axes or None)
_FILES = {
    "fredoka": ("Fredoka-Variable.ttf", {"Weight": 600, "Width": 100}),
    "luckiest": ("LuckiestGuy-Regular.ttf", None),
    "bangers": ("Bangers-Regular.ttf", None),
    "gotham400": ("Montserrat-Variable.ttf", {"Weight": 500}),
    "gotham700": ("Montserrat-Variable.ttf", {"Weight": 700}),
    "gotham900": ("Montserrat-Variable.ttf", {"Weight": 900}),
    "sans400": ("SourceSans3-Variable.ttf", {"Weight": 400}),
    "sans700": ("SourceSans3-Variable.ttf", {"Weight": 700}),
}
FONT_KEYS = list(_FILES)

# family (from rbxasset://fonts/families/<X>.json) -> base key
FAMILY_MAP = {
    "FredokaOne": "fredoka",
    "LuckiestGuy": "luckiest",
    "Bangers": "bangers",
    "GothamSSm": "gotham",
    "Gotham": "gotham",
    "Montserrat": "gotham",
}

EMOJI_PATHS = [
    os.path.join(FONT_DIR, "NotoColorEmoji.ttf"),
    "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
    "/usr/share/fonts/noto/NotoColorEmoji.ttf",
]

WEIGHTS = {"Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500,
           "SemiBold": 600, "Bold": 700, "ExtraBold": 800, "Heavy": 900}


def resolve(family: str | None, weight: str | None) -> str:
    fam = family or "SourceSansPro"
    m = re.search(r"families/([A-Za-z0-9]+)\.json", fam)
    if m:
        fam = m.group(1)
    base = FAMILY_MAP.get(fam, "sans")
    w = WEIGHTS.get(weight or "Regular", 400)
    if base == "gotham":
        return "gotham400" if w <= 500 else ("gotham700" if w <= 700 else "gotham900")
    if base == "sans":
        return "sans400" if w < 600 else "sans700"
    return base


@functools.lru_cache(maxsize=512)
def get_font(key: str, size: int) -> ImageFont.FreeTypeFont:
    size = max(1, int(round(size)))
    fname, axes = _FILES.get(key, _FILES["sans400"])
    font = ImageFont.truetype(os.path.join(FONT_DIR, fname), size)
    if axes:
        try:
            names = [a["name"].decode() if isinstance(a["name"], bytes) else a["name"] for a in font.get_variation_axes()]
            vals = []
            for a, n in zip(font.get_variation_axes(), names):
                vals.append(axes.get(n, a["default"]))
            font.set_variation_by_axes(vals)
        except Exception:
            pass
    return font


@functools.lru_cache(maxsize=1)
def emoji_font():
    for p in EMOJI_PATHS:
        if os.path.exists(p):
            try:
                return ImageFont.truetype(p, 109)
            except Exception:
                continue
    return None


_EMOJI_RE = re.compile(
    "["
    "\U0001F000-\U0001FAFF"
    "☀-➿"
    "⬀-⯿"
    "⌀-⏿"
    "️‍"
    "\U000E0020-\U000E007F"
    "]"
)


def is_emoji_char(ch: str) -> bool:
    return bool(_EMOJI_RE.match(ch))


FALLBACK_PATHS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
]


@functools.lru_cache(maxsize=16)
def _cmap(key: str):
    """set of codepoints the font for `key` has (None = unknown, assume all)"""
    try:
        from fontTools.ttLib import TTFont
    except Exception:
        return None
    fname = _FILES.get(key, _FILES["sans400"])[0]
    try:
        return set(TTFont(os.path.join(FONT_DIR, fname), lazy=True).getBestCmap().keys())
    except Exception:
        return None


@functools.lru_cache(maxsize=64)
def fallback_font(size: int):
    for p in FALLBACK_PATHS:
        if os.path.exists(p):
            return ImageFont.truetype(p, max(1, int(size)))
    return None


def has_glyph(key: str, ch: str) -> bool:
    cm = _cmap(key)
    return True if cm is None else ord(ch) in cm


def split_runs(text: str, key: str | None = None):
    """[(kind, str)] runs, kind = "text" | "emoji" | "fallback" (glyph missing in the font:
    Roblox falls back to a system font, we use DejaVu Sans)."""
    runs = []
    cur, cur_k = "", None
    for ch in text:
        if is_emoji_char(ch) and not (key and has_glyph(key, ch) and ch in "✓✔✗✕★☆→←↑↓▶◀▲▼"):
            k = "emoji"
            if ch in "✓✔✗✕★☆→←↑↓▶◀▲▼":
                k = "fallback"
        elif key and not ch.isspace() and not has_glyph(key, ch):
            k = "fallback"
        else:
            k = "text"
        # joiners / variation selectors stay with the emoji run
        if ch in "\uFE0F\u200D" and cur_k == "emoji":
            k = "emoji"
        if cur_k is None or k == cur_k:
            cur += ch
            cur_k = k
        else:
            runs.append((cur_k, cur))
            cur, cur_k = ch, k
    if cur:
        runs.append((cur_k, cur))
    return runs


def emoji_clusters(s: str):
    """Split an emoji run into visible clusters (joins ZWJ/VS16/skin tones/tags/flag pairs)."""
    VS, ZWJ = "\ufe0f", "\u200d"
    out = []
    for ch in s:
        cp = ord(ch)
        ri = 0x1F1E6 <= cp <= 0x1F1FF
        prev_ri = bool(out) and len(out[-1]) == 1 and 0x1F1E6 <= ord(out[-1]) <= 0x1F1FF
        if out and (ch in (VS, ZWJ) or out[-1].endswith(ZWJ) or 0x1F3FB <= cp <= 0x1F3FF or 0xE0020 <= cp <= 0xE007F or (ri and prev_ri)):
            out[-1] += ch
        else:
            out.append(ch)
    return [c for c in out if c.strip(VS + ZWJ)]


EMOJI_EM = 1.2  # width of one emoji, in ems (same value as data/metrics.json)


def text_width(key: str, size: float, text: str) -> float:
    isz = max(1, int(round(size)))
    font = get_font(key, isz)
    w = 0.0
    for kind, run in split_runs(text, key):
        if kind == "emoji":
            w += len(emoji_clusters(run)) * EMOJI_EM * size
        elif kind == "fallback":
            ff = fallback_font(isz)
            w += ff.getlength(run) if ff else font.getlength(run)
        else:
            w += font.getlength(run)
    return w
