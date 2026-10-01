#!/usr/bin/env python3
"""uipreview: renders approximate screenshots of a game's Roblox UI without Studio.

  python tools/uipreview/preview.py <game> [--state new|mid] [--screen pc|laptop|phone|tablet]
                                           [--open <window>] [--all] [--list-windows]

Writes docs/previews/<game>/<state>-<screen>[-<window>].png + .txt (findings).
See tools/uipreview/README.md.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import build_data  # noqa: E402
import findings as findings_mod  # noqa: E402
from layout import Layout  # noqa: E402
from render import Renderer  # noqa: E402

GAMES = ["anime-planet-clicker", "huerta-tycoon", "ki-warriors", "obby-sky-tower", "pet-tap-simulator", "ruleta-pvp"]

# Safe-area insets: topbar 58 px (2024+ Roblox topbar). Phone = iPhone 12-14 landscape
# notch/home-indicator insets. Tablet = iPad (no notch).
SCREENS = {
    "pc": {"w": 1920, "h": 1080, "touch": False, "insets": {"top": 58, "left": 0, "right": 0, "bottom": 0}},
    "laptop": {"w": 1366, "h": 768, "touch": False, "insets": {"top": 58, "left": 0, "right": 0, "bottom": 0}},
    "phone": {"w": 844, "h": 390, "touch": True, "insets": {"top": 58, "left": 47, "right": 47, "bottom": 21}},
    "tablet": {"w": 1180, "h": 820, "touch": True, "insets": {"top": 58, "left": 0, "right": 0, "bottom": 20}},
}
OUT_MAX_W = {"pc": 1280, "laptop": 1366, "phone": 844, "tablet": 1180}

CACHE = os.path.join(HERE, ".cache")


def find_tool(name):
    p = shutil.which(name)
    if p:
        return p
    for d in ("/tmp/tools", os.path.expanduser("~/.local/bin"), os.path.expanduser("~/.cargo/bin"), os.path.expanduser("~/.aftman/bin"), os.path.expanduser("~/.rokit/bin")):
        c = os.path.join(d, name)
        if os.path.exists(c):
            return c
    sys.exit(f"[uipreview] no encuentro '{name}' en el PATH (ver README: instalar Lune/Rojo)")


def sourcemap(game):
    os.makedirs(CACHE, exist_ok=True)
    out = os.path.join(CACHE, f"{game}.sourcemap.json")
    subprocess.run([find_tool("rojo"), "sourcemap", "default.project.json", "-o", out], cwd=os.path.join(REPO, game),
                   check=True, stdout=subprocess.DEVNULL)
    return out


FROM_CACHE = False


def run_runtime(game, state, screen, open_name, boot=None, locale="en-us", timeout=240, icons=False):
    if FROM_CACHE:
        tag = f"{game}-{state}-{screen}-{open_name or 'hud'}" + ("-icons" if icons else "")
        p = os.path.join(CACHE, tag + ".json")
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                dump = json.load(f)
            dump["_elapsed"] = 0.0
            return dump
    api = build_data.build_api()
    metrics = build_data.build_metrics()
    sm = sourcemap(game)
    fixture = os.path.join(HERE, "fixtures", f"{game}.luau")
    if not os.path.exists(fixture):
        fixture = os.path.join(HERE, "fixtures", "_empty.luau")
    tag = f"{game}-{state}-{screen}-{open_name or 'hud'}" + ("-icons" if icons else "")
    cfg = {
        "gameName": game,
        "repoRoot": REPO,
        "sourcemap": sm,
        "fixture": fixture,
        "state": state,
        "screen": dict(SCREENS[screen], name=screen),
        "open": open_name or "",
        "out": os.path.join(CACHE, tag + ".json"),
        "apiPath": api,
        "metricsPath": metrics,
        "locale": locale,
        "fakeIcons": bool(icons),
    }
    if boot:
        cfg["bootSeconds"] = boot
    cfg_path = os.path.join(CACHE, tag + ".cfg.json")
    with open(cfg_path, "w") as f:
        json.dump(cfg, f)
    t0 = time.time()
    res = subprocess.run([find_tool("lune"), "run", os.path.join(HERE, "runtime", "main.luau"), "--", cfg_path],
                         cwd=REPO, capture_output=True, text=True, timeout=timeout)
    if res.returncode != 0 or not os.path.exists(cfg["out"]):
        sys.stderr.write(res.stdout[-4000:] + "\n" + res.stderr[-4000:] + "\n")
        raise SystemExit(f"[uipreview] el runtime fallo para {tag}")
    with open(cfg["out"], encoding="utf-8") as f:
        dump = json.load(f)
    dump["_elapsed"] = time.time() - t0
    return dump


def parse_at(at):
    """--at 'YYYY-MM-DDTHH:MM' (UTC) -> unix time. Default: a fixed Wednesday 10:00 UTC (no weekend / sale-hour events), so runs repeat."""
    import datetime

    if not at:
        at = "2026-10-07T10:00"
    dt = datetime.datetime.fromisoformat(at)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=datetime.timezone.utc)
    return int(dt.timestamp())


def run_playtest_runtime(game, state, screen, minutes, seed, at=None, timeout=3000):
    """Runs runtime/main.luau in playtest mode and returns the result dict."""
    api = build_data.build_api()
    metrics = build_data.build_metrics()
    sm = sourcemap(game)
    fixture = os.path.join(HERE, "fixtures", f"{game}.luau")
    if not os.path.exists(fixture):
        fixture = os.path.join(HERE, "fixtures", "_empty.luau")
    bot = os.environ.get("UIPREVIEW_BOT") or os.path.join(HERE, "playtests", f"{game}.luau")
    if not os.path.exists(bot):
        raise SystemExit(f"[uipreview] no hay bot en {os.path.relpath(bot, REPO)}")
    tag = f"{game}-{state}-playtest"
    if FROM_CACHE and os.path.exists(os.path.join(CACHE, tag + ".json")):
        with open(os.path.join(CACHE, tag + ".json"), encoding="utf-8") as f:
            dump = json.load(f)
        dump["_elapsed"] = 0.0
        return dump
    cfg = {
        "gameName": game, "repoRoot": REPO, "sourcemap": sm, "fixture": fixture, "state": state,
        "screen": dict(SCREENS[screen], name=screen), "open": "", "out": os.path.join(CACHE, tag + ".json"),
        "apiPath": api, "metricsPath": metrics, "locale": "en-us", "fakeIcons": False,
        "playtest": True, "botPath": bot, "minutes": minutes, "seed": seed, "bootSeconds": 8,
        "epoch": parse_at(at),
    }
    cfg_path = os.path.join(CACHE, tag + ".cfg.json")
    with open(cfg_path, "w") as f:
        json.dump(cfg, f)
    if os.path.exists(cfg["out"]):
        os.remove(cfg["out"])
    t0 = time.time()
    res = subprocess.run([find_tool("lune"), "run", os.path.join(HERE, "runtime", "main.luau"), "--", cfg_path],
                         cwd=REPO, capture_output=True, text=True, timeout=timeout)
    if res.returncode != 0 or not os.path.exists(cfg["out"]):
        sys.stderr.write(res.stdout[-4000:] + "\n" + res.stderr[-6000:] + "\n")
        raise SystemExit(f"[uipreview] el runtime del playtest fallo para {game}")
    with open(cfg["out"], encoding="utf-8") as f:
        dump = json.load(f)
    dump["_elapsed"] = time.time() - t0
    return dump


def list_windows(game):
    """Window names declared in the fixture's `windows = { name = function(ctx) ... }` table."""
    import re

    fixture = os.path.join(HERE, "fixtures", f"{game}.luau")
    if not os.path.exists(fixture):
        return []
    src = open(fixture, encoding="utf-8").read()
    m = re.search(r"\bwindows\s*=\s*\{", src)
    if not m:
        return []
    depth, i, names = 1, m.end(), []
    line_start = True
    while i < len(src) and depth > 0:
        if depth == 1:
            mm = re.match(r"\s*\[?\"?([A-Za-z0-9_]+)\"?\]?\s*=\s*(?:function|[A-Za-z_][A-Za-z0-9_]*\()", src[i:])
            if mm and line_start and mm.group(1) not in names:
                names.append(mm.group(1))
        ch = src[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        elif ch == "-" and src[i:i + 2] == "--":
            j = src.find("\n", i)
            i = j if j > 0 else len(src)
            continue
        line_start = ch in "\n,{"
        i += 1
    return names


def fmt_findings(dump, lay, found, rt, out_name):
    lines = []
    sc = dump["screen"]
    lines.append(f"# uipreview {dump['game']} state={dump['state']} screen={sc['name']} ({sc['w']}x{sc['h']}{', touch' if sc['touch'] else ''})"
                 + (f" window={dump['open']} -> {dump.get('openResult')}" if dump.get("open") else ""))
    lines.append(f"# image: {out_name}  (coordinates below are in the full {sc['w']}x{sc['h']} screen space)")
    lines.append("# APPROXIMATION of Roblox layout: see tools/uipreview/README.md (limits).")
    lines.append("")
    lines.append(f"## Layout findings ({len(found)})")
    for f in found:
        rep = f" (x{f['repeat']} similar)" if f.get("repeat") else ""
        lines.append(f"[{f['sev']}] {f['kind']}: {f['path']} rect={f['rect']}{rep}")
        lines.append(f"    {f['msg']}")
        lines.append(f"    created at: {f['src']}")
    lines.append("")
    lines.append(f"## Runtime log ({len(rt)})")
    for e in rt:
        w = " < ".join(e["where"][:3]) if e["where"] else "?"
        cnt = f" x{e['count']}" if e.get("count", 1) > 1 else ""
        lines.append(f"[{e['kind']}] ({e.get('ctx', '?')}){cnt} {e['msg']}")
        lines.append(f"    at: {w}")
    other = [e for e in dump.get("log", []) if e.get("kind") in ("warn", "info", "print")]
    if other:
        lines.append("")
        lines.append(f"## Other log: warn/info/print ({len(other)}, first 60)")
        for e in other[:60]:
            w = e.get("where") or []
            if isinstance(w, dict):
                w = []
            cnt = f" x{e['count']}" if e.get("count", 1) > 1 else ""
            lines.append(f"[{e['kind']}] ({e.get('ctx', '?')}){cnt} {str(e.get('msg'))[:300]}" + (f"  @ {w[0]}" if w else ""))
    if lay.notes:
        lines.append("")
        lines.append("## Tool notes")
        lines.extend(lay.notes)
    return "\n".join(lines) + "\n"


def render_one(game, state, screen, open_name=None, outdir=None, annotate=False, boot=None, locale="en-us", quiet=False, icons=False):
    dump = run_runtime(game, state, screen, open_name, boot=boot, locale=locale, icons=icons)
    lay = Layout(dump).run()
    rend = Renderer(lay)
    img = rend.render()
    found = findings_mod.check(lay, rend)
    rt = findings_mod.runtime_findings(dump)
    if annotate:
        from PIL import ImageDraw

        d = ImageDraw.Draw(img)
        for i, f in enumerate(found):
            if f["rect"]:
                col = (255, 40, 40, 255) if f["sev"] == "high" else (255, 170, 0, 255)
                d.rectangle(f["rect"], outline=col, width=2)
                d.text((f["rect"][0] + 2, f["rect"][1] + 1), str(i + 1), fill=col)
    outdir = outdir or os.path.join(REPO, "docs", "previews", game)
    os.makedirs(outdir, exist_ok=True)
    base = f"{state}-{screen}" + (f"-{open_name}" if open_name else "") + ("-icons" if icons else "")
    png = os.path.join(outdir, base + ".png")
    out = img.convert("RGB")
    mw = OUT_MAX_W.get(screen, out.width)
    if out.width > mw:
        from PIL import Image

        out = out.resize((mw, int(out.height * mw / out.width)), Image.LANCZOS)
    out = out.quantize(colors=256, method=2, dither=0)
    out.save(png, optimize=True)
    txt = os.path.join(outdir, base + ".txt")
    with open(txt, "w", encoding="utf-8") as f:
        f.write(fmt_findings(dump, lay, found, rt, os.path.basename(png)))
    if not quiet:
        hi = sum(1 for f in found if f["sev"] == "high")
        errs = sum(1 for e in rt if e["kind"] == "error")
        print(f"{os.path.relpath(png, REPO)}: {len(found)} findings ({hi} high), {errs} runtime errors, {dump['_elapsed']:.1f}s"
              + (f", open={dump.get('openResult')}" if open_name else ""))
    return png, found, rt, dump


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game", choices=GAMES + ["all"])
    ap.add_argument("--state", choices=["new", "mid"], default="new")
    ap.add_argument("--screen", choices=list(SCREENS), default="pc")
    ap.add_argument("--open", dest="open_name", default=None, help="window name from the fixture (see --list-windows)")
    ap.add_argument("--all", action="store_true", help="new+mid on pc+phone, plus every window on pc+phone (mid state)")
    ap.add_argument("--list-windows", action="store_true")
    ap.add_argument("--annotate", action="store_true", help="draw numbered boxes around findings")
    ap.add_argument("--outdir", default=None)
    ap.add_argument("--boot", type=float, default=None, help="virtual seconds to run before capturing (default fixture/8)")
    ap.add_argument("--locale", default="en-us")
    ap.add_argument("--dump-json", action="store_true", help="keep the raw tree JSON next to the PNG")
    ap.add_argument("--from-cache", action="store_true", help="reuse the last runtime dump in .cache (only re-layout/render/check)")
    ap.add_argument("--playtest", action="store_true", help="PLAYTEST mode: a bot plays N virtual minutes and reports errors/stuck/invariants (docs/playtests/<game>.md)")
    ap.add_argument("--minutes", type=float, default=10.0, help="--playtest: virtual minutes (default 10)")
    ap.add_argument("--seed", type=int, default=1, help="--playtest: seed for the bot and for Random.new()/math.random")
    ap.add_argument("--at", default=None, help="--playtest: virtual UTC date/time to start at, 'YYYY-MM-DDTHH:MM' (default 2026-10-07T10:00, a Wednesday: no weekend events)")
    ap.add_argument("--icons", action="store_true", help="pretend assets/icons are uploaded (Icons.ids filled with fake ids)")
    a = ap.parse_args()
    global FROM_CACHE
    FROM_CACHE = a.from_cache
    games = GAMES if a.game == "all" else [a.game]
    for g in games:
        if a.playtest:
            import playtest as playtest_mod
            playtest_mod.main(lambda *x: run_playtest_runtime(*x, at=a.at), g, a.state, a.screen, a.minutes, a.seed, a.outdir)
            continue
        if a.list_windows:
            print(g + ": " + ", ".join(list_windows(g)))
            continue
        if a.all:
            for st in ("new", "mid"):
                for sc in ("pc", "phone"):
                    render_one(g, st, sc, None, a.outdir, a.annotate, a.boot, a.locale)
            for w in list_windows(g):
                for sc in ("pc", "phone"):
                    render_one(g, "mid", sc, w, a.outdir, a.annotate, a.boot, a.locale)
            for sc in ("pc", "phone"):
                render_one(g, "mid", sc, None, a.outdir, a.annotate, a.boot, a.locale, icons=True)
        else:
            png, *_ , dump = render_one(g, a.state, a.screen, a.open_name, a.outdir, a.annotate, a.boot, a.locale, icons=a.icons)
            if a.dump_json:
                with open(png[:-4] + ".json", "w") as f:
                    json.dump(dump, f)


if __name__ == "__main__":
    main()
