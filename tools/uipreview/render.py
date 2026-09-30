"""Pillow renderer for the laid-out tree (layout.Layout)."""
from __future__ import annotations

import functools
import json
import math
import os
import re

from PIL import Image, ImageDraw, ImageFilter

import fonts
from layout import BUTTONS, TEXT, Box, Layout, first

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
ICON_DIR = os.path.join(REPO, "assets", "icons")


def c255(c, default=(255, 255, 255)):
    if not isinstance(c, list) or len(c) < 3:
        return default
    return tuple(max(0, min(255, int(round(v * 255)))) for v in c[:3])


def alpha_of(tr):
    try:
        tr = float(tr)
    except (TypeError, ValueError):
        tr = 0.0
    return max(0, min(255, int(round((1 - tr) * 255))))


@functools.lru_cache(maxsize=1)
def asset_icon_map():
    """rbxassetid -> icon name (assets/asset_ids.json, once icons are uploaded)."""
    p = os.path.join(REPO, "assets", "asset_ids.json")
    out = {}
    if os.path.exists(p):
        try:
            data = json.load(open(p, encoding="utf-8"))
            for name, v in data.items():
                vid = v if isinstance(v, (int, str)) else (v.get("id") if isinstance(v, dict) else None)
                if vid:
                    out[str(vid)] = name
        except Exception:
            pass
    return out


@functools.lru_cache(maxsize=128)
def icon_image(name):
    p = os.path.join(ICON_DIR, name + ".png")
    if os.path.exists(p):
        return Image.open(p).convert("RGBA")
    return None


@functools.lru_cache(maxsize=512)
def emoji_image(cluster, px):
    ef = fonts.emoji_font()
    px = max(4, int(px))
    if ef is None:
        return None
    try:
        im = Image.new("RGBA", (136, 128), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.text((0, 0), cluster, font=ef, embedded_color=True)
        bbox = im.getbbox()
        if not bbox:
            return None
        im = im.crop(bbox)
        scale = px / 109 * 0.95
        return im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
    except Exception:
        return None


class Renderer:
    def __init__(self, lay: Layout, show_core=True):
        self.lay = lay
        self.W, self.H = lay.W, lay.H
        self.touch = lay.dump["screen"].get("touch", False)
        self.show_core = show_core
        self.img = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 255))
        self.images_seen = []

    # ---------------------------------------------------------------------------------
    def background(self):
        # a neutral "3D scene" so transparent UI stays readable: sky gradient + ground
        W, H = self.W, self.H
        bg = Image.new("RGB", (1, 256))
        for i in range(256):
            t = i / 255
            if t < 0.62:
                u = t / 0.62
                col = (int(110 + 60 * u), int(160 + 50 * u), int(215 + 25 * u))
            else:
                u = (t - 0.62) / 0.38
                col = (int(96 - 30 * u), int(150 - 40 * u), int(80 - 25 * u))
            bg.putpixel((0, i), col)
        self.img.paste(bg.resize((W, H)).convert("RGBA"))
        d = ImageDraw.Draw(self.img)
        # a rough "character" in the middle
        cx, cy = W // 2, int(H * 0.6)
        u = max(8, H // 30)
        d.rectangle((cx - u, cy - 3 * u, cx + u, cy), fill=(60, 90, 160))
        d.rectangle((cx - u, cy, cx + u, cy + 2 * u), fill=(70, 70, 80))
        d.ellipse((cx - u, cy - 5 * u, cx + u, cy - 3 * u), fill=(250, 215, 160))

    def core_overlay(self):
        """Roblox CoreGui approximations drawn ON TOP (like the real client): topbar
        buttons and, on touch devices, thumbstick + jump button."""
        if not self.show_core:
            return
        ov = Image.new("RGBA", (self.W, self.H), (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        ins = self.lay.ins
        top = ins["top"]
        left = ins["left"]
        # topbar: Roblox menu + chat on the left, "more" on the right (44 px pills)
        by = (top - 44) // 2
        for i, label in enumerate(["R", "chat"]):
            x0 = left + 12 + i * 56
            d.rounded_rectangle((x0, by, x0 + 44, by + 44), radius=22, fill=(18, 18, 21, 170))
            f = fonts.get_font("sans700", 14)
            tw = f.getlength(label)
            d.text((x0 + 22 - tw / 2, by + 13), label, fill=(255, 255, 255, 230), font=f)
        x1 = self.W - ins["right"] - 12
        d.rounded_rectangle((x1 - 44, by, x1, by + 44), radius=22, fill=(18, 18, 21, 170))
        d.text((x1 - 30, by + 10), "...", fill=(255, 255, 255, 230), font=fonts.get_font("sans700", 18))
        if self.touch:
            for r, col in self.touch_zones():
                d.ellipse(r, outline=(255, 255, 255, 150), width=3, fill=col)
        self.img.alpha_composite(ov)

    def touch_zones(self):
        """(rect, fill) of the default touch controls (PlayerModule TouchJump/thumbstick)."""
        W, H = self.W, self.H
        small = min(W, H) <= 500
        if small:
            js = 70
            jx, jy = W - (js * 1.5 - 10), H - js - 20
            ts = 70 * 1.6
            tx, ty = 40 + self.lay.ins["left"], H - ts - 30
        else:
            js = 120
            jx, jy = W - (js * 1.5 - 10), H - js * 1.75
            ts = 120 * 1.3
            tx, ty = 80 + self.lay.ins["left"], H - ts - 60
        return [
            ((jx, jy, jx + js, jy + js), (255, 255, 255, 40)),
            ((tx, ty, tx + ts, ty + ts), (0, 0, 0, 50)),
        ]

    # ---------------------------------------------------------------------------------
    def render(self):
        self.background()
        for box in self.lay.draw_list():
            try:
                self.draw_box(box)
            except Exception as e:  # never let one element kill the render
                self.lay.notes.append(f"render error on {box.path}: {e}")
        self.core_overlay()
        return self.img

    def group_alpha(self, box: Box):
        a = 1.0
        b = box.parent
        while b is not None:
            if b.cls == "CanvasGroup":
                a *= 1 - float(b.props.get("GroupTransparency", 0) or 0)
            b = b.parent
        return a

    def draw_box(self, box: Box):
        p = box.props
        if box.w < 0.5 or box.h < 0.5:
            return
        # clipped away entirely?
        if box.clip is not None:
            cx0, cy0, cx1, cy1 = box.clip
            if cx1 <= cx0 or cy1 <= cy0:
                return
            if box.x >= cx1 or box.y >= cy1 or box.x + box.w <= cx0 or box.y + box.h <= cy0:
                return
        s = box.scale
        strokes = [c for c in box.node["children"] if c["cls"] == "UIStroke" and c["props"].get("Enabled", True) is not False]
        border_strokes = [st for st in strokes if st["props"].get("ApplyStrokeMode") == "Border" or box.cls not in TEXT]
        text_strokes = [st for st in strokes if st not in border_strokes]
        margin = int(max([float(st["props"].get("Thickness", 1)) * s for st in border_strokes] + [0]) + 3)
        W = int(math.ceil(box.w)) + 2 * margin
        H = int(math.ceil(box.h)) + 2 * margin
        if W * H > 12_000_000:
            return
        ss = 2 if W * H < 250_000 else 1
        layer = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
        d = ImageDraw.Draw(layer)
        m = margin * ss
        bw, bh = box.w * ss, box.h * ss
        rect = (m, m, m + bw - 1, m + bh - 1)
        corner = first(box.node, "UICorner")
        radius = 0
        if corner:
            cr = corner["props"].get("CornerRadius") or [0, 8]
            radius = cr[0] * min(box.w, box.h) + cr[1] * s
            radius = max(0, min(radius, min(box.w, box.h) / 2)) * ss
        bt = float(p.get("BackgroundTransparency", 0) or 0)
        galpha = self.group_alpha(box)
        if box.cls == "CanvasGroup":
            galpha *= 1 - float(p.get("GroupTransparency", 0) or 0)
        if bt < 1:
            col = c255(p.get("BackgroundColor3"), (163, 162, 165)) + (alpha_of(bt),)
            if radius > 0:
                d.rounded_rectangle(rect, radius=radius, fill=col)
            else:
                d.rectangle(rect, fill=col)
            bsp = int(p.get("BorderSizePixel", 0) or 0)
            if bsp > 0 and not corner and not border_strokes:
                bc = c255(p.get("BorderColor3"), (27, 42, 53)) + (alpha_of(bt),)
                o = bsp * ss
                d.rectangle((m - o, m - o, m + bw - 1 + o, m + bh - 1 + o), outline=bc, width=o)
        # images
        if box.cls in ("ImageLabel", "ImageButton"):
            self.draw_image(layer, box, (m, m, bw, bh), ss, radius)
        elif box.cls == "ViewportFrame":
            self.placeholder(layer, (m, m, bw, bh), "3D", ss, (90, 90, 110), alpha=90)
        # text
        if box.cls in TEXT and box.text_lines:
            self.draw_text(layer, box, m, ss, text_strokes)
        # gradient multiplies everything drawn so far (background + image + text)
        grad = first(box.node, "UIGradient")
        if grad and grad["props"].get("Enabled", True) is not False:
            layer = self.apply_gradient(layer, grad["props"], (m, m, bw, bh))
        # border strokes (drawn outside the edge, not affected by the gradient here)
        if border_strokes:
            d = ImageDraw.Draw(layer)
            for st in border_strokes:
                sp = st["props"]
                th = max(1, float(sp.get("Thickness", 1)) * s) * ss
                sc = c255(sp.get("Color"), (0, 0, 0)) + (alpha_of(sp.get("Transparency", 0)),)
                o = th / 2
                r2 = (m - o, m - o, m + bw - 1 + o, m + bh - 1 + o)
                sgrad = first(st, "UIGradient")
                if sgrad:
                    kp = sgrad["props"].get("Color")
                    if isinstance(kp, list) and kp:
                        sc = tuple(int(v * 255) for v in kp[0][1:4]) + (sc[3],)
                if radius > 0:
                    d.rounded_rectangle(r2, radius=radius + o, outline=sc, width=int(round(th)))
                else:
                    d.rectangle(r2, outline=sc, width=int(round(th)))
        # scrollbar of a ScrollingFrame whose canvas is taller/wider than the window
        if box.cls == "ScrollingFrame" and hasattr(box, "canvas"):
            d = ImageDraw.Draw(layer)
            cw, chh = box.canvas
            th = float(p.get("ScrollBarThickness", 12) or 0) * s * ss
            bar_t = alpha_of(p.get("ScrollBarImageTransparency", 0))
            if th > 0 and chh > box.h + 1:
                frac = box.h / chh
                cp = (p.get("CanvasPosition") or [0, 0])[1] / chh
                d.rectangle((m + bw - th, m + cp * bh, m + bw - 1, m + (cp + frac) * bh), fill=(40, 40, 40, min(bar_t, 200)))
            if th > 0 and cw > box.w + 1:
                frac = box.w / cw
                d.rectangle((m, m + bh - th, m + frac * bw, m + bh - 1), fill=(40, 40, 40, min(bar_t, 200)))
        if ss != 1:
            layer = layer.resize((W, H), Image.LANCZOS)
        rot = float(p.get("Rotation", 0) or 0)
        if abs(rot) > 0.01:
            layer = layer.rotate(-rot, resample=Image.BICUBIC, expand=False)
        if galpha < 0.999:
            a = layer.getchannel("A").point(lambda v: int(v * galpha))
            layer.putalpha(a)
        self.paste(layer, box.x - margin, box.y - margin, box.clip)

    def paste(self, layer, x, y, clip):
        x0, y0 = int(round(x)), int(round(y))
        x1, y1 = x0 + layer.width, y0 + layer.height
        cx0, cy0, cx1, cy1 = 0, 0, self.W, self.H
        if clip is not None:
            cx0, cy0 = max(cx0, int(math.floor(clip[0]))), max(cy0, int(math.floor(clip[1])))
            cx1, cy1 = min(cx1, int(math.ceil(clip[2]))), min(cy1, int(math.ceil(clip[3])))
        ix0, iy0, ix1, iy1 = max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)
        if ix1 <= ix0 or iy1 <= iy0:
            return
        crop = layer.crop((ix0 - x0, iy0 - y0, ix1 - x0, iy1 - y0))
        self.img.alpha_composite(crop, (ix0, iy0))

    def placeholder(self, layer, r, label, ss, col=(120, 120, 140), alpha=150):
        x, y, w, h = r
        d = ImageDraw.Draw(layer)
        d.rectangle((x, y, x + w - 1, y + h - 1), fill=col + (alpha,), outline=(255, 255, 255, 160), width=max(1, ss))
        step = max(8, int(14 * ss))
        for k in range(-int(h), int(w), step):
            d.line((x + max(k, 0), y + max(-k, 0), x + min(k + h, w), y + min(h, w - k)), fill=(255, 255, 255, 40), width=ss)
        size = max(8, min(int(h / 4), 14 * ss))
        f = fonts.get_font("sans700", size)
        tw = f.getlength(label)
        if tw > w - 4:
            label = label[: max(1, int(len(label) * (w - 4) / max(tw, 1)))]
            tw = f.getlength(label)
        d.text((x + (w - tw) / 2, y + (h - size) / 2), label, fill=(255, 255, 255, 220), font=f)

    def draw_image(self, layer, box, r, ss, radius):
        p = box.props
        image = str(p.get("Image") or "")
        if not image:
            return
        it = float(p.get("ImageTransparency", 0) or 0)
        if it >= 1:
            return
        x, y, w, h = r
        tint = c255(p.get("ImageColor3"), (255, 255, 255))
        icon = None
        m = re.search(r"(\d{5,})", image)
        fake = self.lay.dump.get("iconMap") or {}
        if m and isinstance(fake, dict) and m.group(1) in fake:
            icon = icon_image(fake[m.group(1)])
        elif m and m.group(1) in asset_icon_map():
            icon = icon_image(asset_icon_map()[m.group(1)])
        mi = re.search(r"assets/icons/([a-z_]+)\.png", image)
        if mi:
            icon = icon_image(mi.group(1))
        self.images_seen.append(image)
        if icon is not None:
            side = int(min(w, h))
            im = icon.resize((max(1, side), max(1, side)), Image.LANCZOS)
            if tint != (255, 255, 255):
                tl = Image.new("RGBA", im.size, tint + (255,))
                im = Image.composite(Image.blend(im, tl, 0.0), im, im)
            layer.alpha_composite(im, (int(x + (w - side) / 2), int(y + (h - side) / 2)))
            return
        if image.startswith("rbxthumb://") or "AvatarHeadShot" in image:
            d = ImageDraw.Draw(layer)
            d.ellipse((x, y, x + w - 1, y + h - 1), fill=(200, 200, 210, alpha_of(it)))
            d.ellipse((x + w * 0.3, y + h * 0.15, x + w * 0.7, y + h * 0.55), fill=(240, 205, 160, 255))
            return
        label = image
        label = re.sub(r"^rbxasset(id)?://", "", label)
        label = re.sub(r"^https?://www\.roblox\.com/asset/\?id=", "", label)
        self.placeholder(layer, r, "img " + label[-18:], ss, tuple(int(v * 0.6) for v in tint), alpha=int(150 * (1 - it)))

    def draw_text(self, layer, box: Box, m, ss, text_strokes):
        p = box.props
        tt = float(p.get("TextTransparency", 0) or 0)
        if tt >= 1:
            return
        color = c255(p.get("TextColor3"), (27, 42, 53)) + (alpha_of(tt),)
        if box.cls == "TextBox" and not p.get("Text"):
            color = color[:3] + (int(color[3] * 0.6),)
        size = box.text_size * ss
        if size < 1:
            return
        key = box.font_key
        font = fonts.get_font(key, int(round(size)))
        lh = float(p.get("LineHeight", 1) or 1) * size
        ix0, iy0, ix1, iy1 = box.text_ink
        ox, oy = (ix0 - box.x) * ss + m, (iy0 - box.y) * ss + m
        tw_total = (ix1 - ix0) * ss
        xa = p.get("TextXAlignment", "Center")
        stroke_w, stroke_col = 0, None
        sto = float(p.get("TextStrokeTransparency", 1) or 1)
        if sto < 1:
            stroke_w = max(1, int(round(1 * box.scale * ss)))
            stroke_col = c255(p.get("TextStrokeColor3"), (0, 0, 0)) + (alpha_of(sto),)
        for st in text_strokes:
            sp = st["props"]
            stroke_w = max(1, int(round(float(sp.get("Thickness", 1)) * box.scale * ss)))
            stroke_col = c255(sp.get("Color"), (0, 0, 0)) + (alpha_of(sp.get("Transparency", 0)),)
        d = ImageDraw.Draw(layer)
        asc = font.getmetrics()[0]
        for i, (line, lw) in enumerate(box.text_lines):
            lw *= ss
            if xa == "Left":
                lx = ox
            elif xa == "Right":
                lx = ox + tw_total - lw
            else:
                lx = ox + (tw_total - lw) / 2
            ly = oy + i * lh
            # vertically centre the glyphs in the line box (anchor "lm" = middle of asc/desc)
            base_y = ly + lh / 2
            x = lx
            for kind, run in fonts.split_runs(line, key):
                if kind == "emoji":
                    for cl in fonts.emoji_clusters(run):
                        em = emoji_image(cl, size)
                        adv = fonts.EMOJI_EM * size
                        if em is not None:
                            if tt > 0:
                                a = em.getchannel("A").point(lambda v: int(v * (1 - tt)))
                                em = em.copy()
                                em.putalpha(a)
                            layer.alpha_composite(em, (int(x + (adv - em.width) / 2), int(ly + (lh - em.height) / 2)))
                        else:
                            d.rectangle((x + 2, ly + 2, x + adv - 2, ly + lh - 2), outline=color, width=max(1, ss))
                        x += adv
                else:
                    f = font
                    if kind == "fallback":
                        f = fonts.fallback_font(int(round(size))) or font
                    if stroke_w and stroke_col:
                        d.text((x, base_y), run, font=f, fill=color, stroke_width=stroke_w, stroke_fill=stroke_col, anchor="lm")
                    else:
                        d.text((x, base_y), run, font=f, fill=color, anchor="lm")
                    x += f.getlength(run)

    def apply_gradient(self, layer, gp, r):
        x, y, w, h = r
        cols = gp.get("Color") or [[0, 1, 1, 1], [1, 1, 1, 1]]
        trs = gp.get("Transparency") or [[0, 0], [1, 0]]
        rot = float(gp.get("Rotation", 0) or 0)
        off = gp.get("Offset") or [0, 0]
        th = math.radians(rot)
        c, s_ = math.cos(th), math.sin(th)
        shift = off[0] * c + off[1] * s_
        N = 256
        strip = Image.new("RGBA", (N, 1))
        for i in range(N):
            t = min(1, max(0, i / (N - 1) - shift))
            strip.putpixel((i, 0), tuple(int(v * 255) for v in _seq_color(cols, t)) + (int((1 - _seq_num(trs, t)) * 255),))
        # gradient spans the element's extent along the rotated axis (like Roblox)
        L = max(2, int(abs(w * c) + abs(h * s_)))
        P = max(2, int(abs(w * s_) + abs(h * c)))
        g = strip.resize((L, P), Image.BILINEAR)
        if abs(rot) > 0.01:
            g = g.rotate(-rot, resample=Image.BILINEAR, expand=True)
        full = Image.new("RGBA", layer.size, (255, 255, 255, 255))
        gx = int(x + w / 2 - g.width / 2)
        gy = int(y + h / 2 - g.height / 2)
        full.paste(g, (gx, gy))
        # outside the element (stroke margin) keep the edge colors: good enough
        from PIL import ImageChops

        lr, lg, lb, la = layer.split()
        gr, gg, gb, ga = full.split()
        return Image.merge(
            "RGBA",
            (ImageChops.multiply(lr, gr), ImageChops.multiply(lg, gg), ImageChops.multiply(lb, gb), ImageChops.multiply(la, ga)),
        )


def _seq_color(kps, t):
    kps = sorted(kps, key=lambda k: k[0])
    if t <= kps[0][0]:
        return kps[0][1:4]
    for a, b in zip(kps, kps[1:]):
        if a[0] <= t <= b[0]:
            u = (t - a[0]) / max(b[0] - a[0], 1e-6)
            return [a[i] + (b[i] - a[i]) * u for i in (1, 2, 3)]
    return kps[-1][1:4]


def _seq_num(kps, t):
    kps = sorted(kps, key=lambda k: k[0])
    if t <= kps[0][0]:
        return kps[0][1]
    for a, b in zip(kps, kps[1:]):
        if a[0] <= t <= b[0]:
            u = (t - a[0]) / max(b[0] - a[0], 1e-6)
            return a[1] + (b[1] - a[1]) * u
    return kps[-1][1]
