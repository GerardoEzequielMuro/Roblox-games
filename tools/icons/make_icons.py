"""Shared icon pack for the 6 games (replaces the emoji glyphs in the HUDs).

Every icon is a stack of layers; each layer gets the same treatment so the whole
set reads as one family: soft drop shadow, thick dark outline, vertical gradient
fill and a glossy highlight clipped to the shape (the look of 2025-26 simulator HUDs).

Run:  python tools/icons/make_icons.py            -> assets/icons/*.png (512 px) + contact sheet
Needs: pip install cairosvg pillow
"""

from __future__ import annotations

import colorsys
import math
import pathlib

import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "icons"
SIZE = 512
VIEW = 256


# ---------- color helpers ----------

def _rgb(hexs: str) -> tuple[float, float, float]:
    hexs = hexs.lstrip("#")
    return tuple(int(hexs[i:i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore[return-value]


def _hex(rgb: tuple[float, float, float]) -> str:
    return "#" + "".join(f"{max(0, min(255, round(c * 255))):02x}" for c in rgb)


def shade(hexs: str, light: float = 0.0, sat: float = 0.0) -> str:
    h, l, s = colorsys.rgb_to_hls(*_rgb(hexs))
    return _hex(colorsys.hls_to_rgb(h, max(0, min(1, l + light)), max(0, min(1, s + sat))))


# ---------- geometry helpers (all in a 256 box) ----------

def circle(cx: float, cy: float, r: float) -> str:
    return f'<circle cx="{cx}" cy="{cy}" r="{r}"/>'


def ellipse(cx: float, cy: float, rx: float, ry: float, rot: float = 0) -> str:
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" transform="rotate({rot} {cx} {cy})"/>'


def rrect(x: float, y: float, w: float, h: float, r: float, rot: float = 0) -> str:
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" '
            f'transform="rotate({rot} {x + w / 2} {y + h / 2})"/>')


def poly(pts: list[tuple[float, float]]) -> str:
    return '<polygon points="' + " ".join(f"{x:.1f},{y:.1f}" for x, y in pts) + '"/>'


def path(d: str) -> str:
    return f'<path d="{d}"/>'


def star_pts(cx: float, cy: float, r1: float, r2: float, n: int = 5, rot: float = -90) -> list[tuple[float, float]]:
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def gear_path(cx: float, cy: float, r_out: float, r_in: float, teeth: int, hole: float) -> str:
    d = []
    step = 360 / teeth
    for i in range(teeth):
        a0 = math.radians(i * step - step * 0.22)
        a1 = math.radians(i * step + step * 0.22)
        a2 = math.radians(i * step + step * 0.30)
        a3 = math.radians((i + 1) * step - step * 0.30)
        p = [(cx + r_out * math.cos(a0), cy + r_out * math.sin(a0)),
             (cx + r_out * math.cos(a1), cy + r_out * math.sin(a1)),
             (cx + r_in * math.cos(a2), cy + r_in * math.sin(a2)),
             (cx + r_in * math.cos(a3), cy + r_in * math.sin(a3))]
        for j, (x, y) in enumerate(p):
            d.append(("M" if i == 0 and j == 0 else "L") + f"{x:.1f},{y:.1f}")
    d.append("Z")
    # inner hole (evenodd)
    d.append(f"M{cx + hole},{cy} A{hole},{hole} 0 1,0 {cx - hole},{cy} A{hole},{hole} 0 1,0 {cx + hole},{cy} Z")
    return f'<path fill-rule="evenodd" d="{" ".join(d)}"/>'


def arc_arrow(cx: float, cy: float, r: float, a0: float, a1: float, w: float, head: float) -> str:
    """Thick circular arrow from angle a0 to a1 (degrees, clockwise), arrowhead at a1."""
    ri, ro = r - w / 2, r + w / 2
    large = 1 if (a1 - a0) % 360 > 180 else 0

    def pt(rr: float, a: float) -> str:
        return f"{cx + rr * math.cos(math.radians(a)):.1f},{cy + rr * math.sin(math.radians(a)):.1f}"

    tip_a = a1 + head * 0.9
    d = (f"M{pt(ro, a0)} A{ro},{ro} 0 {large},1 {pt(ro, a1)} "
         f"L{pt(ro + head * 0.55, a1)} L{pt(r, tip_a)} L{pt(ri - head * 0.55, a1)} "
         f"L{pt(ri, a1)} A{ri},{ri} 0 {large},0 {pt(ri, a0)} Z")
    return path(d)


# ---------- renderer ----------

class Icon:
    def __init__(self, name: str) -> None:
        self.name = name
        self.layers: list[tuple[str, str, dict]] = []  # (geometry, color, opts)

    def add(self, geom: str, color: str, **opts) -> "Icon":
        self.layers.append((geom, color, opts))
        return self

    def svg(self) -> str:
        defs, body = [], []
        # one shadow for the whole silhouette
        all_geom = "".join(g for g, _, o in self.layers if not o.get("flat"))
        defs.append('<filter id="sh" x="-20%" y="-20%" width="140%" height="140%">'
                    '<feGaussianBlur stdDeviation="5"/></filter>')
        body.append(f'<g transform="translate(0 9)" fill="#000" opacity="0.35" filter="url(#sh)" '
                    f'stroke="#000" stroke-width="18" stroke-linejoin="round">{all_geom}</g>')
        # outlines first (so inner layers never get cut by a neighbour's stroke)
        for geom, color, o in self.layers:
            if o.get("flat") or o.get("no_outline"):
                continue
            ol = o.get("outline") or shade(color, -0.36, 0.05)
            body.append(f'<g fill="{ol}" stroke="{ol}" stroke-width="{o.get("sw", 16)}" '
                        f'stroke-linejoin="round" stroke-linecap="round">{geom}</g>')
        for i, (geom, color, o) in enumerate(self.layers):
            if o.get("flat"):
                body.append(f'<g fill="{color}" opacity="{o.get("opacity", 1)}">{geom}</g>')
                continue
            top, bot = shade(color, 0.14, 0.05), shade(color, -0.12, 0.05)
            defs.append(f'<linearGradient id="g{i}" x1="0" y1="0" x2="0" y2="1">'
                        f'<stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bot}"/></linearGradient>')
            defs.append(f'<clipPath id="c{i}">{geom}</clipPath>')
            body.append(f'<g fill="url(#g{i})">{geom}</g>')
            if not o.get("no_gloss"):
                # glossy band on the upper part + a thin rim light at the bottom
                body.append(f'<g clip-path="url(#c{i})">'
                            f'<ellipse cx="128" cy="{o.get("gy", 40)}" rx="170" ry="{o.get("gr", 78)}" fill="#fff" opacity="0.30"/>'
                            f'</g>')
                body.append(f'<g clip-path="url(#c{i})" fill="none" stroke="#fff" stroke-opacity="0.35" '
                            f'stroke-width="7" transform="translate(0 -5)">{geom}</g>')
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" viewBox="0 0 {VIEW} {VIEW}">'
                f'<defs>{"".join(defs)}</defs>{"".join(body)}</svg>')


# ---------- palette ----------
GOLD, GREEN, BLUE, CYAN, PURPLE, PINK, RED, ORANGE = "#ffc21a", "#48d45a", "#2f8cff", "#26d3f0", "#9b5cff", "#ff5fa8", "#ff4545", "#ff8a1f"
WHITE, GREY, BROWN, DARK = "#f4f6ff", "#9aa3b8", "#b0703a", "#3b3f55"


def build() -> list[Icon]:
    icons: list[Icon] = []

    def new(name: str) -> Icon:
        ic = Icon(name)
        icons.append(ic)
        return ic

    # currencies
    new("coin").add(circle(128, 128, 92), GOLD).add(circle(128, 128, 64), shade(GOLD, -0.06), sw=10, gy=70, gr=40) \
        .add(path("M112,88 h32 l-6,22 h18 l-44,62 l8,-40 h-18 z"), shade(GOLD, 0.12), sw=9, no_gloss=True)
    new("gem").add(poly([(128, 34), (206, 98), (128, 224), (50, 98)]), CYAN) \
        .add(poly([(128, 34), (168, 98), (128, 224), (88, 98)]), shade(CYAN, 0.12), sw=6, no_gloss=True) \
        .add(poly([(50, 98), (206, 98), (168, 98), (128, 34), (88, 98)]), shade(CYAN, 0.2), sw=6)
    new("cash").add(rrect(34, 66, 188, 124, 18, -8), GREEN).add(circle(128, 128, 34), shade(GREEN, 0.18), sw=9) \
        .add(circle(128, 128, 16), shade(GREEN, -0.1), sw=6, no_gloss=True)
    new("ticket").add(path("M36,86 h184 v28 a14,14 0 0,0 0,28 v28 h-184 v-28 a14,14 0 0,0 0,-28 z"), PINK) \
        .add(star_pts(128, 128, 30, 13) and poly(star_pts(128, 128, 30, 13)), shade(PINK, 0.3), sw=8, no_gloss=True)

    # progression
    new("rebirth").add(arc_arrow(128, 128, 72, 200, 330, 34, 24), PURPLE).add(arc_arrow(128, 128, 72, 20, 150, 34, 24), PURPLE)
    new("upgrade").add(poly([(128, 28), (214, 122), (164, 122), (164, 222), (92, 222), (92, 122), (42, 122)]), GREEN)
    new("star").add(poly(star_pts(128, 132, 104, 46)), GOLD, gy=60)
    new("trophy").add(path("M70,44 h116 v54 a58,58 0 0,1 -116,0 z"), GOLD) \
        .add(path("M70,58 h-26 a30,30 0 0,0 36,48 M186,58 h26 a30,30 0 0,1 -36,48"), GOLD, flat=True) \
        .add(rrect(112, 150, 32, 34, 6), shade(GOLD, -0.08)).add(rrect(76, 184, 104, 34, 10), BROWN)
    new("crown").add(path("M40,190 L52,80 L96,124 L128,60 L160,124 L204,80 L216,190 Z"), GOLD) \
        .add(circle(128, 150, 16), RED, sw=8, no_gloss=True).add(circle(82, 162, 11), BLUE, sw=7, no_gloss=True) \
        .add(circle(174, 162, 11), GREEN, sw=7, no_gloss=True)
    new("lock").add(path("M84,114 v-26 a44,44 0 0,1 88,0 v26 h-22 v-26 a22,22 0 0,0 -44,0 v26 z"), GREY) \
        .add(rrect(58, 110, 140, 112, 22), GOLD).add(path("M128,146 a14,14 0 0,1 8,26 l6,26 h-28 l6,-26 a14,14 0 0,1 8,-26 z"), DARK, flat=True)
    new("check").add(path("M40,132 l36,-36 l34,34 l72,-80 l36,34 l-108,118 z"), GREEN)
    new("close").add(path("M62,96 l34,-34 l32,32 l32,-32 l34,34 l-32,32 l32,32 l-34,34 l-32,-32 l-32,32 l-34,-34 l32,-32 z"), RED)
    new("clock").add(circle(128, 132, 94), WHITE, outline="#5a6180").add(path("M122,72 h12 v58 l40,24 l-6,11 l-46,-28 z"), DARK, flat=True)
    new("calendar").add(rrect(40, 56, 176, 164, 22), WHITE, outline="#5a6180").add(rrect(40, 56, 176, 50, 22), RED) \
        .add(rrect(76, 34, 18, 44, 8), GREY).add(rrect(162, 34, 18, 44, 8), GREY) \
        .add(poly(star_pts(128, 162, 36, 16)), GOLD, sw=8, no_gloss=True)

    # menus
    new("shop").add(path("M34,64 h34 l26,102 h98 l22,-78 h-114"), GREY, flat=True) \
        .add(path("M60,52 h30 l30,110 h82 l24,-84 h-118 l-6,-26 h-42 z"), BLUE) \
        .add(circle(116, 196, 18), DARK).add(circle(186, 196, 18), DARK)
    new("gift").add(rrect(46, 108, 164, 110, 14), PINK).add(rrect(36, 82, 184, 40, 12), shade(PINK, 0.06)) \
        .add(rrect(114, 82, 28, 136, 4), GOLD, sw=8, no_gloss=True) \
        .add(path("M128,82 c-20,-44 -74,-40 -58,-8 c8,14 40,10 58,8 c18,2 50,6 58,-8 c16,-32 -38,-36 -58,8 z"), GOLD, sw=10)
    new("settings").add(gear_path(128, 128, 104, 80, 8, 32), GREY)
    new("book").add(path("M128,64 c-30,-20 -70,-22 -92,-12 v150 c22,-10 62,-8 92,12 z"), BLUE) \
        .add(path("M128,64 c30,-20 70,-22 92,-12 v150 c-22,-10 -62,-8 -92,12 z"), shade(BLUE, 0.08))
    new("quest").add(rrect(52, 48, 152, 180, 18), "#f2d49b", outline="#7b5a2a").add(rrect(96, 30, 64, 36, 12), GREY) \
        .add(path("M78,108 h100 v14 h-100 z M78,142 h100 v14 h-100 z M78,176 h64 v14 h-64 z"), "#7b5a2a", flat=True)
    new("invite").add(circle(96, 88, 36), ORANGE).add(path("M36,210 a60,60 0 0,1 120,0 z"), ORANGE) \
        .add(circle(186, 150, 42), GREEN).add(path("M178,122 h16 v20 h20 v16 h-20 v20 h-16 v-20 h-20 v-16 h20 z"), WHITE, flat=True)
    new("group").add(circle(78, 96, 28), BLUE).add(path("M32,196 a46,46 0 0,1 92,0 z"), BLUE) \
        .add(circle(178, 96, 28), BLUE).add(path("M132,196 a46,46 0 0,1 92,0 z"), BLUE) \
        .add(circle(128, 84, 36), ORANGE).add(path("M66,214 a62,62 0 0,1 124,0 z"), ORANGE)
    new("teleport").add(ellipse(128, 128, 70, 100), PURPLE).add(ellipse(128, 128, 42, 70), shade(PURPLE, 0.25), sw=8) \
        .add(ellipse(128, 128, 18, 36), WHITE, sw=6, no_gloss=True)
    new("map").add(poly([(34, 64), (94, 44), (162, 64), (222, 44), (222, 192), (162, 212), (94, 192), (34, 212)]), "#e8d7a8", outline="#7b5a2a") \
        .add(path("M150,90 a22,22 0 0,1 22,22 c0,20 -22,44 -22,44 c0,0 -22,-24 -22,-44 a22,22 0 0,1 22,-22 z"), RED, sw=10)

    # boosts / stats
    new("bolt").add(poly([(150, 24), (54, 146), (116, 146), (98, 232), (202, 104), (138, 104), (164, 24)]), GOLD)
    new("luck").add(circle(96, 98, 40), GREEN).add(circle(160, 98, 40), GREEN).add(circle(96, 158, 40), GREEN) \
        .add(circle(160, 158, 40), GREEN).add(path("M122,150 q10,50 40,76 l-12,8 q-30,-26 -40,-80 z"), shade(GREEN, -0.1))
    new("rocket").add(path("M128,24 c46,30 58,86 44,142 h-88 c-14,-56 -2,-112 44,-142 z"), WHITE, outline="#5a6180") \
        .add(circle(128, 104, 22), CYAN, sw=10).add(path("M84,140 l-36,42 l44,-6 z M172,140 l36,42 l-44,-6 z"), RED) \
        .add(path("M100,172 h56 l-10,40 l-18,-14 l-18,14 z"), ORANGE)
    new("fist").add(rrect(58, 78, 132, 120, 40), "#ffc59a", outline="#8a4a2a").add(rrect(52, 58, 34, 58, 16), "#ffc59a", outline="#8a4a2a") \
        .add(rrect(88, 50, 34, 60, 16), "#ffc59a", outline="#8a4a2a").add(rrect(124, 50, 34, 60, 16), "#ffc59a", outline="#8a4a2a") \
        .add(rrect(160, 58, 34, 58, 16), "#ffc59a", outline="#8a4a2a").add(rrect(78, 196, 92, 36, 10), RED)
    new("heart").add(path("M128,218 C42,160 26,112 40,82 C56,48 104,44 128,82 C152,44 200,48 216,82 C230,112 214,160 128,218 Z"), RED)
    new("shield").add(path("M128,26 L212,58 C212,148 180,200 128,230 C76,200 44,148 44,58 Z"), BLUE) \
        .add(path("M128,56 L186,78 C184,142 162,180 128,202 Z"), shade(BLUE, 0.14), sw=6, no_gloss=True)
    new("sword").add(poly([(196, 28), (228, 28), (228, 60), (112, 176), (80, 144)]), WHITE, outline="#5a6180") \
        .add(rrect(56, 120, 26, 110, 10, 45), GOLD).add(rrect(40, 176, 40, 40, 12), BROWN)
    new("flame").add(path("M128,232 c-58,0 -86,-44 -72,-96 c10,-36 40,-50 44,-94 c34,22 44,52 40,78 c14,-10 20,-26 18,-46 c36,32 56,76 44,110 c-10,30 -38,48 -74,48 z"), ORANGE) \
        .add(path("M128,226 c-28,0 -42,-22 -34,-48 c6,-18 22,-26 26,-50 c26,22 50,48 42,72 c-4,16 -16,26 -34,26 z"), GOLD, sw=8, no_gloss=True)
    new("auto").add(circle(128, 128, 96), CYAN).add(arc_arrow(128, 128, 60, 210, 470, 22, 18), WHITE, outline="#1b6f86", sw=10, no_gloss=True) \
        .add(poly([(112, 102), (160, 128), (112, 154)]), WHITE, outline="#1b6f86", sw=8, no_gloss=True)
    new("magnet").add(path("M52,40 h52 v96 a24,24 0 0,0 48,0 v-96 h52 v96 a76,76 0 0,1 -152,0 z"), RED) \
        .add(rrect(52, 40, 52, 32, 6), WHITE, outline="#5a6180").add(rrect(152, 40, 52, 32, 6), WHITE, outline="#5a6180")

    # game themed
    new("paw").add(ellipse(128, 164, 58, 50), ORANGE).add(ellipse(66, 106, 22, 30, -20), ORANGE).add(ellipse(106, 70, 22, 30, -6), ORANGE) \
        .add(ellipse(150, 70, 22, 30, 6), ORANGE).add(ellipse(190, 106, 22, 30, 20), ORANGE)
    new("egg").add(path("M128,22 C188,22 216,120 212,160 C208,206 172,234 128,234 C84,234 48,206 44,160 C40,120 68,22 128,22 Z"), "#fff4d6", outline="#8a6a3a") \
        .add(path("M58,140 l24,-18 l24,18 l22,-18 l22,18 l24,-18 l24,18 l-4,22 l-20,-14 l-24,18 l-22,-18 l-22,18 l-24,-18 l-22,14 z"), PINK, sw=8, no_gloss=True)
    new("sprout").add(path("M120,232 v-96 h16 v96 z"), shade(GREEN, -0.1)) \
        .add(path("M128,140 C124,86 84,60 34,70 C38,122 78,146 128,140 Z"), GREEN) \
        .add(path("M128,120 C136,62 176,36 222,48 C218,104 178,128 128,120 Z"), shade(GREEN, 0.06)) \
        .add(ellipse(128, 226, 70, 16), BROWN)
    new("planet").add(circle(128, 128, 72), PURPLE, gy=74, gr=40) \
        .add(path("M26,150 C10,120 88,94 170,84 C242,76 248,104 226,118 C212,108 196,104 170,108 C110,116 52,138 40,160 Z"), GOLD, sw=10, no_gloss=True)
    new("pickaxe").add(rrect(116, 70, 24, 170, 10, 40), BROWN) \
        .add(path("M30,104 C76,30 176,20 232,60 L214,88 C170,62 110,64 60,126 Z"), GREY, gy=60, gr=30)
    new("orb").add(circle(128, 128, 94), ORANGE, gy=58, gr=50).add(poly(star_pts(128, 136, 34, 14)), RED, sw=8, no_gloss=True)
    new("aura").add(path("M128,236 C44,220 26,150 58,96 C60,132 78,150 92,154 C74,110 86,56 128,20 C170,56 182,110 164,154 C178,150 196,132 198,96 C230,150 212,220 128,236 Z"), CYAN) \
        .add(circle(128, 170, 38), WHITE, outline="#1b6f86", sw=10)
    new("cloud").add(path("M60,196 a44,44 0 0,1 0,-88 a58,58 0 0,1 108,-18 a48,48 0 0,1 30,106 z"), "#ffe46a", outline="#b07a10")
    new("wheel").add(circle(128, 128, 98), GOLD).add(circle(128, 128, 78), RED, sw=8, no_gloss=True) \
        .add(path("M128,128 L128,50 A78,78 0 0,1 195,89 Z M128,128 L195,167 A78,78 0 0,1 128,206 Z M128,128 L61,167 A78,78 0 0,1 61,89 Z"), WHITE, flat=True) \
        .add(circle(128, 128, 18), GOLD, sw=8).add(poly([(112, 12), (144, 12), (128, 44)]), WHITE, outline="#5a6180", sw=8)
    new("skull").add(path("M128,30 C188,30 216,72 212,122 C210,146 196,158 186,164 V198 H70 V164 C60,158 46,146 44,122 C40,72 68,30 128,30 Z"), WHITE, outline="#5a6180") \
        .add(ellipse(96, 118, 20, 24), DARK, flat=True).add(ellipse(160, 118, 20, 24), DARK, flat=True) \
        .add(poly([(128, 144), (138, 164), (118, 164)]), DARK, flat=True) \
        .add(path("M92,198 v-20 h14 v20 z M121,198 v-20 h14 v20 z M150,198 v-20 h14 v20 z"), DARK, flat=True)
    new("target").add(circle(128, 128, 96), RED).add(circle(128, 128, 64), WHITE, sw=8, no_gloss=True, outline="#9a2a2a") \
        .add(circle(128, 128, 34), RED, sw=8, no_gloss=True)
    new("sound").add(path("M40,96 h40 l56,-46 v156 l-56,-46 h-40 z"), GREY) \
        .add(path("M160,92 a52,52 0 0,1 0,72 l-12,-12 a36,36 0 0,0 0,-48 z"), GREY, sw=10) \
        .add(path("M186,64 a92,92 0 0,1 0,128 l-13,-13 a74,74 0 0,0 0,-102 z"), GREY, sw=10)
    new("tap").add(path("M92,36 L92,196 L128,160 L154,222 L182,210 L156,150 L206,150 Z"), WHITE, outline="#2b3050") \
        .add(path("M52,60 l-26,-10 l4,-14 l26,10 z M60,26 l-8,-22 l14,-4 l8,22 z M44,98 l-26,8 l-4,-14 l26,-8 z"), GOLD, sw=8, no_gloss=True)
    return icons


def contact_sheet(names: list[str]) -> None:
    cols, cell = 8, 150
    rows = math.ceil(len(names) / cols)
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 24)), (36, 40, 58, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()
    for i, n in enumerate(names):
        im = Image.open(OUT / f"{n}.png").resize((120, 120), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * (cell + 24)
        sheet.alpha_composite(im, (x + 15, y + 10))
        draw.text((x + 15, y + 134), n, fill=(230, 230, 240, 255), font=font)
    sheet.save(OUT.parent / "icons_sheet.png")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    icons = build()
    for ic in icons:
        cairosvg.svg2png(bytestring=ic.svg().encode(), write_to=str(OUT / f"{ic.name}.png"),
                         output_width=SIZE, output_height=SIZE)
    contact_sheet([ic.name for ic in icons])
    print(f"{len(icons)} icons -> {OUT}")


if __name__ == "__main__":
    main()
