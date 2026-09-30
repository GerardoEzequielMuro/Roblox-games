"""Approximate Roblox 2D GUI layout over the JSON tree dumped by the Luau runtime.

Handles: UDim2 Size/Position + AnchorPoint, SizeConstraint, UIPadding, UIListLayout
(FillDirection, Padding, alignments, SortOrder, Wraps, flex approx.), UIGridLayout
(CellSize, CellPadding, FillDirectionMaxCells, aspect-constrained cells), UIPageLayout
(first page only), UIAspectRatioConstraint, UISizeConstraint, UITextSizeConstraint,
UIScale (cumulative, scales offsets/text/strokes), AutomaticSize (approx.), ScrollingFrame
canvas (CanvasSize / AutomaticCanvasSize / CanvasPosition), Visible, Enabled, ScreenInsets /
IgnoreGuiInset, ClipsDescendants (rect), ZIndex with Sibling/Global behaviour, DisplayOrder.
"""
from __future__ import annotations

import math
import re
from dataclasses import dataclass, field

import fonts

LAYOUT_CLASSES = {"UIListLayout", "UIGridLayout", "UIPageLayout", "UITableLayout"}
GUI_OBJECT = {
    "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame",
    "ViewportFrame", "CanvasGroup", "VideoFrame",
}
BUTTONS = {"TextButton", "ImageButton"}
TEXT = {"TextLabel", "TextButton", "TextBox"}


@dataclass
class Box:
    node: dict
    cls: str
    name: str
    path: str
    x: float = 0
    y: float = 0
    w: float = 0
    h: float = 0
    scale: float = 1.0  # cumulative UIScale
    clip: tuple | None = None  # (x0, y0, x1, y1) clip rect from ancestors
    visible: bool = True
    z: tuple = ()
    gui: str = ""
    display_order: int = 0
    parent: "Box | None" = None
    children: list = field(default_factory=list)
    text_size: float = 0  # resolved px
    text_lines: list = field(default_factory=list)  # [(str, width)]
    text_ink: tuple | None = None  # (x0,y0,x1,y1) of rendered text
    text_overflow: tuple | None = None  # (need_w, need_h, avail_w, avail_h)
    font_key: str = "sans400"
    order: int = 0
    in_scroll: "Box | None" = None

    @property
    def props(self):
        return self.node["props"]

    def rect(self):
        return (self.x, self.y, self.x + self.w, self.y + self.h)


def udim2(v, default=(0, 0, 0, 0)):
    if not isinstance(v, list) or len(v) != 4:
        return default
    return v


def comp(node, cls):
    return [c for c in node["children"] if c["cls"] == cls]


def first(node, cls):
    for c in node["children"]:
        if c["cls"] == cls:
            return c
    return None


def strip_rich(s: str) -> str:
    s = re.sub(r"<br\s*/?>", "\n", s)
    s = re.sub(r"<[^>]*>", "", s)
    return s.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&").replace("&quot;", '"').replace("&apos;", "'")


def font_key_of(props) -> str:
    ff = props.get("FontFace") or {}
    return fonts.resolve(ff.get("family"), ff.get("weight"))


# ---------------------------------------------------------------------------------------
# text layout
# ---------------------------------------------------------------------------------------

def wrap_lines(text: str, key: str, size: float, wrap_w: float | None):
    lines = []
    for para in text.split("\n"):
        if wrap_w is None:
            lines.append((para, fonts.text_width(key, size, para)))
            continue
        words = para.split(" ")
        cur, cur_w = "", 0.0
        for word in words:
            if word == "":
                continue
            cand = word if cur == "" else cur + " " + word
            cw = fonts.text_width(key, size, cand)
            if cw <= wrap_w + 0.5 or cur == "":
                cur, cur_w = cand, cw
            else:
                lines.append((cur, cur_w))
                cur, cur_w = word, fonts.text_width(key, size, word)
        lines.append((cur, cur_w))
    return lines


def text_bounds(text, key, size, wrap_w, line_h=1.0):
    lines = wrap_lines(text, key, size, wrap_w)
    w = max((lw for _, lw in lines), default=0)
    return lines, w, len(lines) * size * line_h


def scaled_size(text, key, bw, bh, lo=1, hi=100):
    hi = int(min(hi, 100))
    lo = int(max(lo, 1))
    if bw <= 0 or bh <= 0:
        return lo
    # binary search the largest size that fits (wrapping, as TextScaled does)
    best = lo
    a, b = lo, hi
    while a <= b:
        m = (a + b) // 2
        _, w, h = text_bounds(text, key, m, bw)
        if w <= bw + 0.5 and h <= bh + 0.5:
            best = m
            a = m + 1
        else:
            b = m - 1
    return best


# ---------------------------------------------------------------------------------------
# layout engine
# ---------------------------------------------------------------------------------------

class Layout:
    def __init__(self, dump: dict):
        self.dump = dump
        sc = dump["screen"]
        self.W, self.H = sc["w"], sc["h"]
        self.ins = sc["insets"]
        self.boxes: list[Box] = []
        self.counter = 0
        self.notes: list[str] = []

    def screen_rect(self, props):
        if props.get("IgnoreGuiInset") is True or props.get("ScreenInsets") == "None":
            return (0, 0, self.W, self.H)
        ins = self.ins
        if props.get("ScreenInsets") == "DeviceSafeInsets":
            return (ins["left"], 0, self.W - ins["left"] - ins["right"], self.H - ins["bottom"])
        return (ins["left"], ins["top"], self.W - ins["left"] - ins["right"], self.H - ins["top"] - ins["bottom"])

    def run(self):
        roots = [r for r in self.dump["roots"] if r["cls"] == "ScreenGui"]
        for r in roots:
            p = r["props"]
            if p.get("Enabled") is False:
                continue
            x, y, w, h = self.screen_rect(p)
            gui = Box(r, r["cls"], r["name"], r["name"], x, y, w, h)
            gui.gui = r["name"]
            gui.display_order = int(p.get("DisplayOrder", 0) or 0)
            gui.global_z = p.get("ZIndexBehavior") == "Global"
            self.layout_children(gui, r, (x, y, w, h), 1.0, None, None)
            self.boxes.append(gui)
        return self

    # children of a container (flattening Folders)
    def gui_children(self, node):
        out = []
        for c in node["children"]:
            if c["cls"] == "Folder":
                out.extend(self.gui_children(c))
            elif c["cls"] in GUI_OBJECT:
                out.append(c)
        return out

    def padding(self, node, w, h, s):
        p = first(node, "UIPadding")
        if not p:
            return 0, 0, 0, 0
        pp = p["props"]

        def u(k, base):
            v = pp.get(k) or [0, 0]
            return v[0] * base + v[1] * s

        return u("PaddingLeft", w), u("PaddingTop", h), u("PaddingRight", w), u("PaddingBottom", h)

    def own_scale(self, node):
        s = 1.0
        for c in comp(node, "UIScale"):
            s *= float(c["props"].get("Scale", 1) or 1)
        return s

    def base_size(self, node, pw, ph, s):
        p = node["props"]
        xs, xo, ys, yo = udim2(p.get("Size"))
        sc = p.get("SizeConstraint", "RelativeXY")
        w = xs * pw + xo * s
        h = ys * ph + yo * s
        if sc == "RelativeXX":
            h = ys * pw + yo * s
        elif sc == "RelativeYY":
            w = xs * ph + xo * s
        return w, h

    def constrain(self, node, w, h, s):
        for c in node["children"]:
            cp = c["props"]
            if c["cls"] == "UISizeConstraint":
                mn = cp.get("MinSize") or [0, 0]
                mx = cp.get("MaxSize") or [1e9, 1e9]
                w = min(max(w, mn[0] * s), max(mn[0], mx[0]) * s)
                h = min(max(h, mn[1] * s), max(mn[1], mx[1]) * s)
        for c in node["children"]:
            cp = c["props"]
            if c["cls"] == "UIAspectRatioConstraint":
                ar = float(cp.get("AspectRatio", 1) or 1)
                if ar <= 0:
                    continue
                at = cp.get("AspectType", "FitWithinMaxSize")
                dom = cp.get("DominantAxis", "Width")
                if at == "ScaleWithParentSize":
                    if dom == "Width":
                        h = w / ar
                    else:
                        w = h * ar
                else:
                    if h <= 0:
                        h = w / ar
                    elif w / h > ar:
                        w = h * ar
                    else:
                        h = w / ar
        return w, h

    def text_needed(self, node, w_avail, s):
        """natural text size (for AutomaticSize)"""
        p = node["props"]
        text = p.get("Text") or ""
        if node["cls"] == "TextBox" and not text:
            text = p.get("PlaceholderText") or ""
        if p.get("RichText"):
            text = strip_rich(text)
        if not text:
            return 0, 0
        size = float(p.get("TextSize", 14)) * s
        key = font_key_of(p)
        wrap = w_avail if (p.get("TextWrapped") and w_avail and w_avail > 0) else None
        _, tw, th = text_bounds(text, key, size, wrap, float(p.get("LineHeight", 1) or 1))
        return tw, th

    def place(self, node, parent_box: Box, content, s_parent, clip, scroll_box, forced=None):
        """Lay out one GuiObject. content = (x,y,w,h) of the parent's content area.
        forced = (x, y, w, h) when a layout object positions/sizes it."""
        p = node["props"]
        cx, cy, cw, ch = content
        own = self.own_scale(node)
        s = s_parent * own
        if forced is not None:
            x, y, w, h = forced
        else:
            w, h = self.base_size(node, cw, ch, s_parent)
            w, h = self.constrain(node, w, h, s_parent)
            w *= own
            h *= own
        auto = p.get("AutomaticSize", "None")
        box = Box(node, node["cls"], node["name"], parent_box.path + "." + node["name"])
        box.parent = parent_box
        box.gui = parent_box.gui
        box.display_order = parent_box.display_order
        box.scale = s
        box.in_scroll = scroll_box
        self.counter += 1
        box.order = self.counter
        box.visible = p.get("Visible", True) is not False
        if auto and auto != "None":
            # grow to content: text + children extents (offset-sized children only)
            need_w, need_h = self.auto_content(node, w, h, s)
            if auto in ("X", "XY"):
                w = max(w, need_w)
            if auto in ("Y", "XY"):
                h = max(h, need_h)
        if forced is None:
            xs, xo, ys, yo = udim2(p.get("Position"))
            ap = p.get("AnchorPoint") or [0, 0]
            x = cx + xs * cw + xo * s_parent - ap[0] * w
            y = cy + ys * ch + yo * s_parent - ap[1] * h
        else:
            x, y = forced[0], forced[1]
        box.x, box.y, box.w, box.h = x, y, max(w, 0), max(h, 0)
        box.clip = clip
        parent_box.children.append(box)
        # text
        if node["cls"] in TEXT:
            self.layout_text(box)
        # children
        child_clip = clip
        if p.get("ClipsDescendants") or node["cls"] == "ScrollingFrame":
            r = (box.x, box.y, box.x + box.w, box.y + box.h)
            child_clip = r if clip is None else (max(r[0], clip[0]), max(r[1], clip[1]), min(r[2], clip[2]), min(r[3], clip[3]))
        if node["cls"] == "ScrollingFrame":
            self.layout_scrolling(box, node, s, child_clip)
        else:
            self.layout_children(box, node, (box.x, box.y, box.w, box.h), s, child_clip, scroll_box)
        return box

    def auto_content(self, node, w, h, s):
        pl, pt, pr, pb = self.padding(node, w, h, s)
        tw, th = (0, 0)
        if node["cls"] in TEXT:
            p = node["props"]
            auto = p.get("AutomaticSize")
            avail = (w - pl - pr) if auto == "Y" else None
            tw, th = self.text_needed(node, avail, s)
        kids = self.gui_children(node)
        lay = next((c for c in node["children"] if c["cls"] in LAYOUT_CLASSES), None)
        cw = ch = 0.0
        vis = [k for k in kids if k["props"].get("Visible", True) is not False]
        if lay and lay["cls"] == "UIListLayout" and vis:
            lp = lay["props"]
            vertical = lp.get("FillDirection", "Vertical") == "Vertical"
            pad = (lp.get("Padding") or [0, 0])[1] * s
            sizes = []
            for k in vis:
                kw, kh = self.base_size(k, max(w - pl - pr, 0), max(h - pt - pb, 0), s)
                kw, kh = self.constrain(k, kw, kh, s)
                ka = k["props"].get("AutomaticSize", "None")
                if ka != "None":
                    nw, nh = self.auto_content(k, kw, kh, s)
                    if ka in ("X", "XY"):
                        kw = max(kw, nw)
                    if ka in ("Y", "XY"):
                        kh = max(kh, nh)
                sizes.append((kw, kh))
            if vertical:
                ch = sum(sz[1] for sz in sizes) + pad * (len(sizes) - 1)
                cw = max(sz[0] for sz in sizes)
            else:
                cw = sum(sz[0] for sz in sizes) + pad * (len(sizes) - 1)
                ch = max(sz[1] for sz in sizes)
        elif lay and lay["cls"] == "UIGridLayout" and vis:
            lp = lay["props"]
            cs = udim2(lp.get("CellSize"), [0, 100, 0, 100])
            cp = udim2(lp.get("CellPadding"), [0, 5, 0, 5])
            cellw = cs[0] * w + cs[1] * s
            cellh = cs[2] * h + cs[3] * s
            padx, pady = cp[1] * s, cp[3] * s
            avail = max(w - pl - pr, 1)
            cols = max(1, int((avail + padx) // max(cellw + padx, 1)))
            mc = int(lp.get("FillDirectionMaxCells", 0) or 0)
            if mc > 0:
                cols = min(cols, mc)
            rows = math.ceil(len(vis) / cols)
            cw = cols * cellw + (cols - 1) * padx
            ch = rows * cellh + max(rows - 1, 0) * pady
        else:
            for k in vis:
                kp = k["props"]
                xs, xo, ys, yo = udim2(kp.get("Size"))
                ps = udim2(kp.get("Position"))
                if xs == 0:
                    cw = max(cw, ps[1] * s + xo * s)
                if ys == 0:
                    ch = max(ch, ps[3] * s + yo * s)
        return max(tw, cw) + pl + pr, max(th, ch) + pt + pb

    def layout_text(self, box: Box):
        p = box.props
        text = p.get("Text") or ""
        if box.cls == "TextBox" and not text:
            text = p.get("PlaceholderText") or ""
        if p.get("RichText"):
            text = strip_rich(text)
        mvg = p.get("MaxVisibleGraphemes", -1)
        if isinstance(mvg, (int, float)) and mvg >= 0:
            text = text[: int(mvg)]
        key = font_key_of(p)
        box.font_key = key
        pl, pt, pr, pb = self.padding(box.node, box.w, box.h, box.scale)
        aw, ah = box.w - pl - pr, box.h - pt - pb
        lh = float(p.get("LineHeight", 1) or 1)
        tsc = first(box.node, "UITextSizeConstraint")
        lo, hi = 1, 100
        if tsc:
            lo = float(tsc["props"].get("MinTextSize", 1) or 1)
            hi = float(tsc["props"].get("MaxTextSize", 100) or 100)
        if not text:
            box.text_lines = []
            box.text_size = float(p.get("TextSize", 14)) * box.scale
            return
        if p.get("TextScaled"):
            size = scaled_size(text, key, aw, ah, lo * box.scale, hi * box.scale)
            lines, tw, th = text_bounds(text, key, size, aw, lh)
        else:
            size = min(max(float(p.get("TextSize", 14)), 1), 100) * box.scale
            if tsc:
                size = min(max(size, lo * box.scale), hi * box.scale)
            wrap = aw if p.get("TextWrapped") else None
            lines, tw, th = text_bounds(text, key, size, wrap, lh)
            if tw > aw + 2 or th > ah + 2:
                box.text_overflow = (tw, th, aw, ah)
            if p.get("TextTruncate") in ("AtEnd", "SplitWord") and tw > aw + 2 and lines:
                # truncate the last line with "..."
                s0, _ = lines[-1]
                while s0 and fonts.text_width(key, size, s0 + "...") > aw:
                    s0 = s0[:-1]
                lines[-1] = (s0 + "...", fonts.text_width(key, size, s0 + "..."))
                box.text_overflow = None
                box.truncated = True
        box.text_size = size
        box.text_lines = lines
        # ink rect
        xa = p.get("TextXAlignment", "Center")
        ya = p.get("TextYAlignment", "Center")
        tw = max((lw for _, lw in lines), default=0)
        th = len(lines) * size * lh
        x0 = box.x + pl
        y0 = box.y + pt
        if xa == "Left":
            ix = x0
        elif xa == "Right":
            ix = x0 + aw - tw
        else:
            ix = x0 + (aw - tw) / 2
        if ya == "Top":
            iy = y0
        elif ya == "Bottom":
            iy = y0 + ah - th
        else:
            iy = y0 + (ah - th) / 2
        box.text_ink = (ix, iy, ix + tw, iy + th)

    def layout_scrolling(self, box: Box, node, s, clip):
        p = node["props"]
        pl, pt, pr, pb = 0, 0, 0, 0
        cs = udim2(p.get("CanvasSize"), [0, 0, 2, 0])
        cw = cs[0] * box.w + cs[1] * s
        chh = cs[2] * box.h + cs[3] * s
        auto = p.get("AutomaticCanvasSize", "None")
        # ScrollingFrame: children laid in the canvas. Scrollbar takes space on the axis.
        bar = float(p.get("ScrollBarThickness", 12) or 0) * s
        dirn = p.get("ScrollingDirection", "XY")
        if cw <= 0:
            cw = box.w
        if chh <= 0:
            chh = box.h
        if auto != "None":
            nw, nh = self.auto_content(node, box.w - (bar if dirn in ("Y", "XY") and chh > box.h else 0), box.h, s)
            if auto in ("X", "XY"):
                cw = max(box.w, nw)
            if auto in ("Y", "XY"):
                chh = max(box.h, nh)
        view_w = box.w - (bar if chh > box.h + 0.5 else 0)
        # canvas X scale is relative to window width minus the vertical bar
        if cs[0] > 0 and auto not in ("X", "XY"):
            cw = cs[0] * view_w + cs[1] * s
        cp = p.get("CanvasPosition") or [0, 0]
        box.canvas = (cw, chh)
        self.layout_children(box, node, (box.x - cp[0], box.y - cp[1], cw, chh), s, clip, box)

    def layout_children(self, box: Box, node, rect, s, clip, scroll_box):
        x, y, w, h = rect
        pl, pt, pr, pb = self.padding(node, w, h, s)
        content = (x + pl, y + pt, max(w - pl - pr, 0), max(h - pt - pb, 0))
        kids = self.gui_children(node)
        lay = next((c for c in node["children"] if c["cls"] in LAYOUT_CLASSES), None)
        if lay is None or not kids:
            for k in kids:
                self.place(k, box, content, s, clip, scroll_box)
            return
        if lay["cls"] == "UIGridLayout":
            self.grid(box, lay, kids, content, s, clip, scroll_box)
        elif lay["cls"] == "UIPageLayout":
            # only the first page (by order) is shown, filling the content area
            vis = self.sorted_kids(lay, kids)
            for i, k in enumerate(vis):
                if i == 0:
                    self.place(k, box, content, s, clip, scroll_box)
                else:
                    bx = self.place(k, box, content, s, clip, scroll_box)
                    bx.visible = False
        else:
            self.listlayout(box, lay, kids, content, s, clip, scroll_box)

    def sorted_kids(self, lay, kids):
        so = lay["props"].get("SortOrder", "LayoutOrder")
        idx = {id(k): i for i, k in enumerate(kids)}
        if so == "Name":
            return sorted(kids, key=lambda k: (k["name"], idx[id(k)]))
        if so == "LayoutOrder":
            return sorted(kids, key=lambda k: (int(k["props"].get("LayoutOrder", 0) or 0), idx[id(k)]))
        return kids

    def listlayout(self, box, lay, kids, content, s, clip, scroll_box):
        lp = lay["props"]
        cx, cy, cw, ch = content
        vertical = lp.get("FillDirection", "Vertical") == "Vertical"
        padu = lp.get("Padding") or [0, 0]
        pad = padu[0] * (ch if vertical else cw) + padu[1] * s
        ha = lp.get("HorizontalAlignment", "Left")
        va = lp.get("VerticalAlignment", "Top")
        wraps = lp.get("Wraps") is True
        ordered = self.sorted_kids(lay, kids)
        visible = [k for k in ordered if k["props"].get("Visible", True) is not False]
        hidden = [k for k in ordered if k["props"].get("Visible", True) is False]
        # measure
        sizes = []
        for k in visible:
            own = self.own_scale(k)
            kw, kh = self.base_size(k, cw, ch, s)
            kw, kh = self.constrain(k, kw, kh, s)
            kw *= own
            kh *= own
            ka = k["props"].get("AutomaticSize", "None")
            if ka != "None":
                nw, nh = self.auto_content(k, kw, kh, s * own)
                if ka in ("X", "XY"):
                    kw = max(kw, nw)
                if ka in ("Y", "XY"):
                    kh = max(kh, nh)
            sizes.append([kw, kh])
        # flex (approx.): UIFlexItem Fill / HorizontalFlex Fill grow items to fill the main axis
        main_avail = ch if vertical else cw
        flex_mode = lp.get("VerticalFlex" if vertical else "HorizontalFlex", "None")
        growers = []
        for i, k in enumerate(visible):
            fi = first(k, "UIFlexItem")
            if fi and fi["props"].get("FlexMode", "None") in ("Fill", "Grow", "Custom"):
                growers.append(i)
        if (flex_mode == "Fill" or growers) and not wraps and sizes:
            total = sum(sz[1 if vertical else 0] for sz in sizes) + pad * (len(sizes) - 1)
            extra = main_avail - total
            targets = growers if growers else list(range(len(sizes)))
            if extra > 0 and targets:
                for i in targets:
                    sizes[i][1 if vertical else 0] += extra / len(targets)
        # lines (wrapping)
        lines = [[]]
        acc = 0.0
        for i, sz in enumerate(sizes):
            m = sz[1] if vertical else sz[0]
            if wraps and lines[-1] and acc + pad + m > main_avail + 0.5:
                lines.append([])
                acc = 0.0
            acc = m if not lines[-1] else acc + pad + m
            lines[-1].append(i)
        cross_off = 0.0
        for line in lines:
            if not line:
                continue
            main_total = sum((sizes[i][1] if vertical else sizes[i][0]) for i in line) + pad * (len(line) - 1)
            cross_max = max((sizes[i][0] if vertical else sizes[i][1]) for i in line)
            gap = pad
            if vertical:
                start = cy + (0 if va == "Top" else (ch - main_total) / 2 if va == "Center" else ch - main_total)
            else:
                start = cx + (0 if ha == "Left" else (cw - main_total) / 2 if ha == "Center" else cw - main_total)
            if flex_mode in ("SpaceBetween", "SpaceAround", "SpaceEvenly") and len(line) > 0:
                free = main_avail - (main_total - pad * (len(line) - 1))
                n = len(line)
                if flex_mode == "SpaceBetween" and n > 1:
                    gap = free / (n - 1)
                    start = cy if vertical else cx
                elif flex_mode == "SpaceAround":
                    gap = free / n
                    start = (cy if vertical else cx) + gap / 2
                elif flex_mode == "SpaceEvenly":
                    gap = free / (n + 1)
                    start = (cy if vertical else cx) + gap
            pos = start
            for i in line:
                k = visible[i]
                kw, kh = sizes[i]
                if vertical:
                    if ha == "Left" or wraps and len(lines) > 1:
                        kx = cx + cross_off
                    elif ha == "Center":
                        kx = cx + (cw - kw) / 2
                    else:
                        kx = cx + cw - kw
                    self.place(k, box, content, s, clip, scroll_box, forced=(kx, pos, kw, kh))
                    pos += kh + gap
                else:
                    if va == "Top" or wraps and len(lines) > 1:
                        ky = cy + cross_off
                    elif va == "Center":
                        ky = cy + (ch - kh) / 2
                    else:
                        ky = cy + ch - kh
                    self.place(k, box, content, s, clip, scroll_box, forced=(pos, ky, kw, kh))
                    pos += kw + gap
            cross_off += cross_max + pad
        for k in hidden:
            bx = self.place(k, box, content, s, clip, scroll_box)
            bx.visible = False

    def grid(self, box, lay, kids, content, s, clip, scroll_box):
        lp = lay["props"]
        cx, cy, cw, ch = content
        cs = udim2(lp.get("CellSize"), [0, 100, 0, 100])
        cp = udim2(lp.get("CellPadding"), [0, 5, 0, 5])
        cellw = cs[0] * cw + cs[1] * s
        cellh = cs[2] * ch + cs[3] * s
        ar = first(lay, "UIAspectRatioConstraint")
        if ar:
            ratio = float(ar["props"].get("AspectRatio", 1) or 1)
            if cellw / max(cellh, 1e-6) > ratio:
                cellw = cellh * ratio
            else:
                cellh = cellw / ratio
        padx = cp[0] * cw + cp[1] * s
        pady = cp[2] * ch + cp[3] * s
        horizontal = lp.get("FillDirection", "Horizontal") == "Horizontal"
        ordered = self.sorted_kids(lay, kids)
        visible = [k for k in ordered if k["props"].get("Visible", True) is not False]
        hidden = [k for k in ordered if k["props"].get("Visible", True) is False]
        if horizontal:
            per = max(1, int((cw + padx + 0.01) // max(cellw + padx, 1)))
        else:
            per = max(1, int((ch + pady + 0.01) // max(cellh + pady, 1)))
        mc = int(lp.get("FillDirectionMaxCells", 0) or 0)
        if mc > 0:
            per = min(per, mc)
        n = len(visible)
        if horizontal:
            cols = min(per, n) if n else 1
            rows = math.ceil(n / per) if n else 0
        else:
            rows = min(per, n) if n else 1
            cols = math.ceil(n / per) if n else 0
        tot_w = cols * cellw + max(cols - 1, 0) * padx
        tot_h = rows * cellh + max(rows - 1, 0) * pady
        ha = lp.get("HorizontalAlignment", "Left")
        va = lp.get("VerticalAlignment", "Top")
        ox = cx + (0 if ha == "Left" else (cw - tot_w) / 2 if ha == "Center" else cw - tot_w)
        oy = cy + (0 if va == "Top" else (ch - tot_h) / 2 if va == "Center" else ch - tot_h)
        for i, k in enumerate(visible):
            if horizontal:
                r, c = divmod(i, per)
            else:
                c, r = divmod(i, per)
            self.place(k, box, content, s, clip, scroll_box, forced=(ox + c * (cellw + padx), oy + r * (cellh + pady), cellw, cellh))
        for k in hidden:
            bx = self.place(k, box, content, s, clip, scroll_box)
            bx.visible = False
        box.grid_content = (tot_w, tot_h)

    # -----------------------------------------------------------------------------------
    def draw_list(self):
        """Visible boxes in draw order: [(box, effective_clip)]"""
        out = []
        guis = sorted(self.boxes, key=lambda g: (g.display_order, self.dump_index(g)))
        for g in guis:
            items = []
            self.collect(g, items, (), g.__dict__.get("global_z", False))
            if g.__dict__.get("global_z", False):
                items.sort(key=lambda t: (t[1], t[2]))
            out.extend(b for b, _, _ in items)
        return out

    def dump_index(self, g):
        for i, r in enumerate(self.dump["roots"]):
            if r is g.node:
                return i
        return 0

    def collect(self, box, items, zpath, global_z):
        kids = [c for c in box.children if c.visible]
        if not global_z:
            kids = sorted(kids, key=lambda c: (int(c.props.get("ZIndex", 1) or 1), c.order))
        for c in kids:
            z = int(c.props.get("ZIndex", 1) or 1)
            items.append((c, z, c.order))
            self.collect(c, items, zpath + (z,), global_z)

    def all_boxes(self):
        out = []

        def rec(b, vis):
            for c in b.children:
                v = vis and c.visible
                c.effective_visible = v
                out.append(c)
                rec(c, v)

        for g in self.boxes:
            rec(g, True)
        return out
