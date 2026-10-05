#!/usr/bin/env python3
"""Draws the Mac App Store screenshots (2880x1800).

Run from the repo root:  python3 tool/make_mac_screenshots.py   (needs Pillow,
NumPy, and the macOS system fonts Arial Black and Avenir Next)

Each screenshot is a window capture from store_assets/screenshots/macos/raw/
(see COMMANDS.md, "macOS screenshots") in the middle of a starry background,
with the title and a caption on the left, and on the right the J/K/L chords
that mix each colour, the one in the capture lit up.

Output: store_assets/screenshots/macos/screenshot_N_2880x1800.png
"""

import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_feature_graphic import (BLUE, CYAN, GREEN, MAGENTA, RED,
                                  TAGLINE_FONT, TITLE_FONT, WHITE, YELLOW)
from make_icons import BG_CENTER, BG_EDGE, STORE

W, H = 2880, 1800
DIR = os.path.join(STORE, "screenshots", "macos")
RAW = os.path.join(DIR, "raw")

KEYS = {"J": RED, "K": GREEN, "L": BLUE}
CHORDS = [("JK", YELLOW), ("KL", CYAN), ("JL", MAGENTA), ("JKL", WHITE)]

# (raw capture, caption, sub-caption, chord to light up or None).
SHOTS = [
    ("1_start.png", "Play with J, K and L", "Three keys, seven colours.", None),
    ("2_yellow.png", "J + K makes YELLOW", "Press keys together to mix.",
     "JK"),
    ("3_magenta.png", "J + L makes MAGENTA",
     "A ring only blasts its own colour.", "JL"),
    ("4_white.png", "All three make WHITE", "Mixed colours score more.",
     "JKL"),
    ("5_boss.png", "Beat the bosses", "Shoot them away band by band.", None),
    ("6_turbo.png", "Go TURBO", "5 in a row clears the screen.", None),
]

LIGHT = (0xD8, 0xD8, 0xE8)
DIM = (0x8A, 0x8A, 0xA0)
WORDS = {"RED": RED, "GREEN": GREEN, "BLUE": BLUE, "YELLOW": YELLOW,
         "CYAN": CYAN, "MAGENTA": MAGENTA, "WHITE": WHITE}


def font(size, tagline=False):
    if tagline:
        path, index = TAGLINE_FONT
        return ImageFont.truetype(path, size, index=index)
    return ImageFont.truetype(TITLE_FONT, size)


def background():
    """Space gradient brightest behind the window, with scattered stars."""
    y, x = np.mgrid[0:H, 0:W].astype(np.float32)
    d = np.hypot(x - W / 2, y - H * 0.45) / (np.hypot(W, H) * 0.55)
    t = (np.minimum(1, d * 1.2) ** 1.1)[..., None]
    rgb = np.array(BG_CENTER) * (1 - t) + np.array(BG_EDGE) * t
    img = Image.fromarray(rgb.astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(img)
    rnd = random.Random(7)
    for _ in range(320):
        x, y = rnd.random() * W, rnd.random() * H
        r = 1.2 + rnd.random() * 2.8
        a = rnd.randint(90, 200)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(a, a, a))
    return img.convert("RGBA")


def layer():
    return Image.new("RGBA", (W, H), (0, 0, 0, 0))


def glow_text(canvas, xy, s, f, color, glow=0):
    """[s] at [xy], in one colour or a colour per letter, with a soft glow."""
    x, y = xy
    colors = color if isinstance(color, list) else [color] * len(s)
    for ch, c in zip(s, colors):
        if glow:
            g = layer()
            ImageDraw.Draw(g).text((x, y), ch, font=f, fill=c + (glow,))
            canvas = Image.alpha_composite(canvas, g.filter(
                ImageFilter.GaussianBlur(f.size * 0.15)))
        t = layer()
        ImageDraw.Draw(t).text((x, y), ch, font=f, fill=c + (255,))
        canvas = Image.alpha_composite(canvas, t)
        x += f.getlength(ch)
    return canvas


def centred(canvas, cx, y, s, f, base=LIGHT, glow=0):
    """[s] centred on [cx], with its capitalised colour names in colour."""
    colors = []
    for word in s.split(" "):
        c = WORDS.get(word.strip(".,"), base)
        colors += [c] * len(word) + [base]
    return glow_text(canvas, (cx - f.getlength(s) / 2, y), s, f, colors[:-1],
                     glow)


def keycap(canvas, x, y, size, key, lit):
    """A rounded key in its colour, bright when [lit]."""
    color = KEYS[key]
    face = color if lit else tuple(int(c * 0.35) for c in color)
    box = [x, y, x + size, y + size]
    if lit:
        g = layer()
        ImageDraw.Draw(g).rounded_rectangle(box, size * 0.22,
                                            fill=color + (150,))
        canvas = Image.alpha_composite(canvas, g.filter(
            ImageFilter.GaussianBlur(size * 0.2)))
    k = layer()
    d = ImageDraw.Draw(k)
    d.rounded_rectangle(box, size * 0.22, fill=face + (255,),
                        outline=tuple(min(255, c + 70) for c in face) + (255,),
                        width=3)
    f = font(int(size * 0.5))
    label = (255, 255, 255, 255 if lit else 170)
    d.text((x + size / 2, y + size * 0.5), key, font=f, fill=label,
           anchor="mm")
    return Image.alpha_composite(canvas, k)


def dot(canvas, cx, cy, r, color, lit):
    g = layer()
    ImageDraw.Draw(g).ellipse([cx - r * 1.6, cy - r * 1.6, cx + r * 1.6,
                               cy + r * 1.6], fill=color + (120 if lit else 50,))
    canvas = Image.alpha_composite(canvas, g.filter(
        ImageFilter.GaussianBlur(r * 0.6)))
    d = layer()
    ImageDraw.Draw(d).ellipse([cx - r, cy - r, cx + r, cy + r],
                              fill=color + (255 if lit else 130,))
    return Image.alpha_composite(canvas, d)


def arrow(canvas, x0, x1, y, on):
    a = layer()
    d = ImageDraw.Draw(a)
    fill = (255, 255, 255, 200 if on else 80)
    d.line([x0, y, x1 - 14, y], fill=fill, width=6)
    d.polygon([(x1, y), (x1 - 20, y - 14), (x1 - 20, y + 14)], fill=fill)
    return Image.alpha_composite(canvas, a)


def legend(canvas, cx, top, lit):
    """The four chords and their colours; all bright unless one is [lit]."""
    canvas = centred(canvas, cx, top, "PRESS TOGETHER", font(40, True), DIM)
    size, gap, row = 104, 18, 170
    for i, (keys, color) in enumerate(CHORDS):
        on = lit is None or lit == keys
        y = top + 110 + i * row
        width = 3 * size + 2 * gap + 90 + 2 * 46
        x = cx - width / 2 + (3 - len(keys)) * (size + gap)
        for k in keys:
            canvas = keycap(canvas, x, y, size, k, on)
            x += size + gap
        canvas = arrow(canvas, x + 18, x + 72, y + size / 2, on)
        canvas = dot(canvas, x + 90 + 46, y + size / 2, 40, color, on)
    return canvas


def window(canvas, path):
    """The capture, centred, with a macOS-style drop shadow."""
    win = Image.open(path).convert("RGBA")
    scale = (H - 200) / win.height
    win = win.resize((round(win.width * scale), round(win.height * scale)),
                     Image.LANCZOS)
    x, y = (W - win.width) // 2, (H - win.height) // 2
    shadow = layer()
    alpha = Image.new("L", (W, H), 0)
    alpha.paste(win.getchannel("A"), (x, y + 30))
    shadow.putalpha(alpha.point(lambda a: a * 0.75))
    canvas = Image.alpha_composite(canvas, shadow.filter(
        ImageFilter.GaussianBlur(45)))
    canvas.alpha_composite(win, (x, y))
    return canvas, x, x + win.width


def main():
    bg = background()
    for n, (raw, caption, sub, lit) in enumerate(SHOTS, 1):
        img, left, right = window(bg.copy(), os.path.join(RAW, raw))

        cx = left / 2
        img = glow_text(img, (cx - font(230).getlength("RGB") / 2, 330),
                        "RGB", font(230), [RED, GREEN, BLUE], glow=150)
        img = centred(img, cx, 600, "INVADERS", font(108), WHITE, glow=70)
        img = centred(img, cx, 960, caption, font(64, True), WHITE)
        img = centred(img, cx, 1060, sub, font(46, True))

        img = legend(img, (right + W) / 2, 470, lit)

        path = os.path.join(DIR, f"screenshot_{n}_{W}x{H}.png")
        img.convert("RGB").save(path)
        print(path)


if __name__ == "__main__":
    main()
