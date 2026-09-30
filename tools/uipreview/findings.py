"""Automatic checks over a laid-out tree + the runtime log."""
from __future__ import annotations

from layout import BUTTONS, TEXT, Box, Layout

MIN_TOUCH = 44
MIN_SCALED_TEXT = 9


def src_of(box: Box) -> str:
    src = box.node.get("src") or []
    if isinstance(src, dict):
        src = []
    return " < ".join(src[:3]) if src else "?"


def label(box: Box) -> str:
    t = box.props.get("Text")
    extra = ""
    if t:
        t = str(t).replace("\n", " ")
        extra = f' "{t[:40]}"'
    return f"{box.cls} {box.path}{extra}"


def is_interactive(box: Box) -> bool:
    if box.cls in BUTTONS or box.cls == "TextBox":
        return box.props.get("Active", True) is not False and box.props.get("Interactable", True) is not False
    return False


def draws_something(box: Box) -> bool:
    p = box.props
    if float(p.get("BackgroundTransparency", 0) or 0) < 0.95:
        return True
    if box.cls in TEXT and box.text_lines and float(p.get("TextTransparency", 0) or 0) < 0.95:
        return True
    if box.cls in ("ImageLabel", "ImageButton") and p.get("Image") and float(p.get("ImageTransparency", 0) or 0) < 0.95:
        return True
    return False


def rect_inter(a, b):
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1, y1 = min(a[2], b[2]), min(a[3], b[3])
    if x1 <= x0 or y1 <= y0:
        return None
    return (x0, y0, x1, y1)


def area(r):
    return max(0, r[2] - r[0]) * max(0, r[3] - r[1])


def visible_rect(box: Box):
    r = box.rect()
    if box.clip is not None:
        r = rect_inter(r, box.clip)
    return r


def is_ancestor(a: Box, b: Box) -> bool:
    cur = b.parent
    while cur is not None:
        if cur is a:
            return True
        cur = cur.parent
    return False


def check(lay: Layout, renderer=None):
    out = []
    W, H = lay.W, lay.H
    touch = lay.dump["screen"].get("touch", False)
    boxes = [b for b in lay.all_boxes() if getattr(b, "effective_visible", True)]
    screen = (0, 0, W, H)

    def add(sev, kind, box, msg):
        out.append({
            "sev": sev,
            "kind": kind,
            "path": box.path if box else "",
            "rect": [round(v) for v in box.rect()] if box else None,
            "msg": msg,
            "src": src_of(box) if box else "",
        })

    # draw order + occlusion by later, opaque, non-related boxes (e.g. a modal window over the HUD)
    order = {id(b): i for i, b in enumerate(lay.draw_list())}
    opaque = [o for o in boxes if float(o.props.get("BackgroundTransparency", 0) or 0) <= 0.2
              and o.w * o.h >= 1500 and o.cls != "ScreenGui"]
    screen_area = W * H

    def occluded(b):
        vr = visible_rect(b)
        if vr is None:
            return True
        ib = order.get(id(b), -1)
        for o in opaque:
            if order.get(id(o), -1) <= ib or o is b or is_ancestor(o, b) or is_ancestor(b, o):
                continue
            orr = visible_rect(o)
            if orr and orr[0] <= vr[0] + 1 and orr[1] <= vr[1] + 1 and orr[2] >= vr[2] - 1 and orr[3] >= vr[3] - 1:
                return True
        return False

    def covered(rect, lower):
        """rect (part of `lower`) is hidden under a later opaque box unrelated to `lower`"""
        il = order.get(id(lower), -1)
        for o in opaque:
            if order.get(id(o), -1) <= il or o is lower or is_ancestor(o, lower) or is_ancestor(lower, o):
                continue
            orr = visible_rect(o)
            if orr and orr[0] <= rect[0] + 1 and orr[1] <= rect[1] + 1 and orr[2] >= rect[2] - 1 and orr[3] >= rect[3] - 1:
                return True
        return False

    def lower_of(a, b):
        return a if order.get(id(a), -1) < order.get(id(b), -1) else b

    def backdrop(b):
        return b.w * b.h >= 0.35 * screen_area

    shown = []
    for b in boxes:
        vr = visible_rect(b)
        if vr is None or area(vr) < 1:
            continue
        if b.cls not in ("Frame", "ScrollingFrame", "CanvasGroup") and occluded(b):
            continue
        shown.append(b)
        # --- text overflow
        if b.cls in TEXT and b.text_overflow and b.text_lines:
            tw, th, aw, ah = b.text_overflow
            what = []
            if tw > aw + 2:
                what.append(f"width {tw:.0f}>{aw:.0f}")
            if th > ah + 2:
                what.append(f"height {th:.0f}>{ah:.0f}")
            add("high" if tw > aw * 1.15 or th > ah * 1.3 else "med", "text-overflow", b,
                f"text does not fit its box at TextSize {b.text_size:.0f}px ({', '.join(what)}; wrapped={bool(b.props.get('TextWrapped'))})")
        # --- tiny scaled text
        if b.cls in TEXT and b.props.get("TextScaled") and b.text_lines and b.text_size < MIN_SCALED_TEXT:
            add("high" if b.text_size < 7 else "med", "tiny-text", b, f"TextScaled resolves to {b.text_size:.0f}px (< {MIN_SCALED_TEXT}px, unreadable)")
        elif b.cls in TEXT and b.text_lines and not b.props.get("TextScaled") and b.text_size < MIN_SCALED_TEXT:
            raw = b.props.get("TextSize")
            add("high" if (isinstance(raw, (int, float)) and raw < 1) else "med", "tiny-text", b,
                f"TextSize={raw} -> {b.text_size:.1f}px on screen after UIScale (< {MIN_SCALED_TEXT}px)"
                + (" (Roblox clamps TextSize < 1 to 1: the text is invisible)" if isinstance(raw, (int, float)) and raw < 1 else ""))
        # --- off screen
        if (draws_something(b) or is_interactive(b)) and not (b.w * b.h >= 0.8 * screen_area):
            r = b.rect()
            inter = rect_inter(r, screen)
            a = area(r)
            if a > 4:
                if inter is None:
                    if b.in_scroll is None:
                        add("high" if is_interactive(b) else "low", "offscreen", b, "element is completely outside the screen")
                else:
                    lost = 1 - area(inter) / a
                    if lost > 0.02 and max(r[0] - 0, 0) + 1 and (r[0] < -2 or r[1] < -2 or r[2] > W + 2 or r[3] > H + 2):
                        if b.in_scroll is None:
                            add("high" if is_interactive(b) and lost > 0.25 else "med", "offscreen", b,
                                f"{lost * 100:.0f}% of the element is outside the screen ({W}x{H})")
        # --- clipped by a ClipsDescendants ancestor (not scroll content along the scroll axis)
        if (is_interactive(b) or (b.cls in TEXT and b.text_lines)) and b.clip is not None:
            r = b.rect()
            vr2 = rect_inter(r, b.clip)
            if vr2 is not None and area(r) > 4:
                lost = 1 - area(vr2) / area(r)
                sc = b.in_scroll
                along_scroll = False
                if sc is not None:
                    d = sc.props.get("ScrollingDirection", "XY")
                    cw, ch = getattr(sc, "canvas", (sc.w, sc.h))
                    # content cut on an axis that can actually scroll is fine
                    if (r[1] < b.clip[1] - 1 or r[3] > b.clip[3] + 1) and d in ("Y", "XY") and ch > sc.h + 1:
                        along_scroll = True
                    if (r[0] < b.clip[0] - 1 or r[2] > b.clip[2] + 1) and d in ("X", "XY") and cw > sc.w + 1:
                        along_scroll = True
                if lost > 0.15 and not along_scroll:
                    add("med", "clipped", b, f"{lost * 100:.0f}% cut off by a ClipsDescendants/ScrollingFrame ancestor")
        # --- touch target size
        if touch and is_interactive(b) and not backdrop(b):
            if min(b.w, b.h) < MIN_TOUCH:
                add("med" if min(b.w, b.h) >= 32 else "high", "small-touch", b,
                    f"touch target {b.w:.0f}x{b.h:.0f}px (< {MIN_TOUCH}px on a touch screen)")
    def is_window(a):
        return a.w * a.h >= 0.12 * screen_area and float(a.props.get("BackgroundTransparency", 0) or 0) < 0.5

    def in_big_window(o):
        a = o
        while a is not None and a.cls != "ScreenGui":
            if is_window(a):
                return True
            a = a.parent
        return False

    # --- HUD pieces hidden under another (small, opaque) HUD piece drawn later.
    # Big boxes (windows/backdrops, >= 20% of the screen) are treated as intended modals.
    for b in boxes:
        if not ((b.cls in TEXT and b.text_lines) or is_interactive(b)):
            continue
        vr = visible_rect(b)
        if vr is None or area(vr) < 20:
            continue
        ib = order.get(id(b), -1)
        best, who = 0.0, None
        for o in opaque:
            if in_big_window(o) or order.get(id(o), -1) <= ib or o is b or is_ancestor(o, b) or is_ancestor(b, o):
                continue
            orr = visible_rect(o)
            it = rect_inter(vr, orr) if orr else None
            if it:
                frac = area(it) / area(vr)
                if frac > best:
                    best, who = frac, o
        if who is not None and best >= 0.3:
            add("high" if best > 0.7 and is_interactive(b) else "med", "covered", b,
                f"{best * 100:.0f}% hidden under {who.path} (drawn on top)")
    # --- scroll canvas too short (content beyond canvas can never be reached)
    for b in boxes:
        if b.cls == "ScrollingFrame" and hasattr(b, "canvas"):
            cw, ch = b.canvas
            bottom = b.y + ch
            right = b.x + cw
            for c in b.children:
                if not getattr(c, "effective_visible", True):
                    continue
                if c.y + c.h > bottom + 4 and b.props.get("ScrollingDirection", "XY") in ("Y", "XY"):
                    add("med", "canvas-short", c, f"item ends {c.y + c.h - bottom:.0f}px below the ScrollingFrame canvas (CanvasSize too small, can't scroll to it)")
                    break
                if c.x + c.w > right + 4 and b.props.get("ScrollingDirection", "XY") in ("X", "XY"):
                    add("med", "canvas-short", c, f"item ends {c.x + c.w - right:.0f}px right of the canvas")
                    break
    # --- overlapping interactive elements
    inter_boxes = [b for b in shown if is_interactive(b) and not backdrop(b)]
    for i in range(len(inter_boxes)):
        a = inter_boxes[i]
        ra = visible_rect(a)
        for j in range(i + 1, len(inter_boxes)):
            b = inter_boxes[j]
            if a.gui != b.gui or is_ancestor(a, b) or is_ancestor(b, a):
                continue
            rb = visible_rect(b)
            it = rect_inter(ra, rb)
            if it is None:
                continue
            frac = area(it) / max(1, min(area(ra), area(rb)))
            if frac >= 0.15 and not covered(it, lower_of(a, b)):
                add("high" if frac > 0.5 else "med", "overlap", a, f"overlaps button {b.path} ({frac * 100:.0f}% of the smaller one)")
    # --- overlapping text (ink boxes of different labels)
    texts = [b for b in shown if b.cls in TEXT and b.text_lines and b.text_ink and float(b.props.get("TextTransparency", 0) or 0) < 0.9]
    for i in range(len(texts)):
        a = texts[i]
        ia = a.text_ink
        if a.clip:
            ia = rect_inter(ia, a.clip) or (0, 0, 0, 0)
        for j in range(i + 1, len(texts)):
            b = texts[j]
            if a.gui != b.gui or is_ancestor(a, b) or is_ancestor(b, a):
                continue
            ib = b.text_ink
            if b.clip:
                ib = rect_inter(ib, b.clip) or (0, 0, 0, 0)
            it = rect_inter(ia, ib)
            if it is None:
                continue
            frac = area(it) / max(1, min(area(ia), area(ib)))
            if frac >= 0.2 and (it[3] - it[1]) > 4 and (it[2] - it[0]) > 4 and not covered(it, lower_of(a, b)):
                add("med", "text-overlap", a, f'text overlaps the text of {b.path} "{str(b.props.get("Text"))[:30]}" ({frac * 100:.0f}%)')
    # --- core UI (topbar buttons) and touch controls covering interactive elements
    ins = lay.ins
    top = ins["top"]
    core = [((ins["left"] + 8, 0, ins["left"] + 12 + 56 + 48, top), "Roblox topbar (menu/chat buttons)"),
            ((W - ins["right"] - 60, 0, W, top), "Roblox topbar (more button)")]
    if touch and renderer is not None:
        for r, _ in renderer.touch_zones():
            core.append((r, "touch control (thumbstick/jump)"))
    for b in shown:
        if not (is_interactive(b) or (b.cls in TEXT and b.text_lines)):
            continue
        vr = visible_rect(b)
        for r, name in core:
            it = rect_inter(vr, r)
            if it and area(it) > 0.2 * area(vr):
                add("med" if is_interactive(b) else "low", "core-overlap", b, f"covered by the {name}")
    # sort
    rank = {"high": 0, "med": 1, "low": 2}
    out.sort(key=lambda f: (rank[f["sev"]], f["kind"], f["path"]))
    # de-duplicate identical kinds on repeated list items (same src + kind + msg shape)
    seen = {}
    dedup = []
    for f in out:
        key = (f["kind"], f["src"], f["msg"].split("(")[0])
        if key in seen:
            seen[key]["repeat"] = seen[key].get("repeat", 1) + 1
            continue
        seen[key] = f
        dedup.append(f)
    return dedup


def runtime_findings(dump):
    out = []
    for e in dump.get("log", []):
        k = e.get("kind")
        where = e.get("where") or []
        if isinstance(where, dict):
            where = []
        if k in ("error", "infinite_yield", "wait_timeout", "remote_serialization", "deprecated", "unknown_api", "kick"):
            out.append({"kind": k, "msg": e.get("msg"), "where": where, "count": e.get("count", 1), "ctx": e.get("ctx"), "t": e.get("t")})
    for b in dump.get("blocked", []) or []:
        where = b.get("where") or []
        if isinstance(where, dict):
            where = []
        out.append({"kind": "blocked-thread", "msg": "thread still suspended at the end: " + str(b.get("desc")), "where": where, "count": 1})
    return out
