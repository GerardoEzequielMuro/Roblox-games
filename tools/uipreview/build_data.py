"""Genera los datos que usa el runtime de Luau (se corre solo, desde preview.py):

- data/api.json: el API dump de Roblox compactado (clases, superclase, propiedades con
  tipo y si son de solo lectura, funciones, eventos y callbacks).
- data/metrics.json: anchos de avance por caracter de cada fuente que usa el renderer,
  para que TextService:GetTextSize y TextBounds en el runtime midan con las mismas
  fuentes con las que despues se dibuja.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
API_URL = "https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json"


def build_api(force: bool = False) -> str:
    out = os.path.join(DATA, "api.json")
    if os.path.exists(out) and not force:
        return out
    os.makedirs(DATA, exist_ok=True)
    raw_path = os.path.join(DATA, "API-Dump.json")
    if not os.path.exists(raw_path):
        print("[uipreview] bajando API-Dump.json ...", file=sys.stderr)
        subprocess.run(["curl", "-sSfL", "-o", raw_path, API_URL], check=True)
    with open(raw_path, encoding="utf-8") as f:
        dump = json.load(f)
    classes = {}
    for c in dump["Classes"]:
        props, funcs, events, callbacks = {}, [], [], []
        for m in c.get("Members", []):
            mt = m["MemberType"]
            name = m["Name"]
            tags = m.get("Tags") or []
            sec = m.get("Security")
            if isinstance(sec, dict):
                rsec = sec.get("Read", "None")
                wsec = sec.get("Write", "None")
            else:
                rsec = wsec = sec or "None"
            if mt == "Property":
                vt = m.get("ValueType", {})
                props[name] = {
                    "t": vt.get("Name"),
                    "c": vt.get("Category"),
                    "ro": ("ReadOnly" in tags) or wsec not in ("None", "PluginSecurity"),
                    "ns": "NotScriptable" in tags or rsec not in ("None", "PluginSecurity"),
                    "dep": "Deprecated" in tags,
                }
            elif mt == "Function":
                funcs.append(name)
            elif mt == "Event":
                events.append(name)
            elif mt == "Callback":
                callbacks.append(name)
        classes[c["Name"]] = {
            "s": c.get("Superclass"),
            "p": props,
            "f": funcs,
            "e": events,
            "cb": callbacks,
            "svc": "Service" in (c.get("Tags") or []),
            "nc": "NotCreatable" in (c.get("Tags") or []),
        }
    enums = {e["Name"]: {i["Name"]: i["Value"] for i in e.get("Items", [])} for e in dump.get("Enums", [])}
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"classes": classes, "enums": enums}, f, separators=(",", ":"))
    try:
        os.remove(raw_path)  # 7 MB; only the compact file is kept
    except OSError:
        pass
    return out


def build_metrics(force: bool = False) -> str:
    out = os.path.join(DATA, "metrics.json")
    if os.path.exists(out) and not force:
        return out
    sys.path.insert(0, HERE)
    import fonts  # noqa: E402

    os.makedirs(DATA, exist_ok=True)
    chars = [chr(c) for c in range(32, 0x250)]
    chars += list("•…–—‘’“”✓✔✗✕×★☆→←↑↓▶◀▲▼⚡❤♥♦♣♠°±·¡¿€£¥™©®")
    result = {}
    for key in fonts.FONT_KEYS:
        font = fonts.get_font(key, 100)
        adv = {}
        for ch in chars:
            try:
                adv[ch] = round(font.getlength(ch) / 100, 4)
            except Exception:
                pass
        avg = sum(adv.get(c, 0.5) for c in "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJ0123456789") / 47
        result[key] = {"adv": adv, "avg": round(avg, 4)}
    with open(out, "w", encoding="utf-8") as f:
        json.dump({"fonts": result, "emoji": 1.2, "map": fonts.FAMILY_MAP}, f, ensure_ascii=False, separators=(",", ":"))
    return out


if __name__ == "__main__":
    force = "--force" in sys.argv
    print(build_api(force))
    print(build_metrics(force))
