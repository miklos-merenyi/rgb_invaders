#!/usr/bin/env python3
"""Draws the Google Play feature graphic (1024x500).

Run from the repo root:  python3 tool/make_feature_graphic.py   (needs Pillow,
and the macOS system fonts Arial Black and Avenir Next)

The title and tagline sit on the left. On the right, invaders in the game's
seven colours fall through space while a magenta circle, fired from below,
destroys the magenta one for +2, as in the game.

Output: store_assets/feature_graphic_1024x500.png
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_icons import BG_CENTER, BG_EDGE, SPRITE, COLS, ROWS, STORE, lerp

W, H = 1024, 500
SS = 2  # supersampling factor for smooth edges

# GameColors in lib/game/game.dart.
RED = (0xFF, 0x3B, 0x30)
GREEN = (0x34, 0xE0, 0x3A)
YELLOW = (0xFF, 0xEE, 0x33)
BLUE = (0x3D, 0x6B, 0xFF)
MAGENTA = (0xFF, 0x3D, 0xF5)
CYAN = (0x33, 0xF0, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF)

TITLE_FONT = "/System/Library/Fonts/Supplemental/Arial Black.ttf"
TAGLINE_FONT = ("/System/Library/Fonts/Avenir Next.ttc", 2)  # Demi Bold

# Invaders on the right: (x, y, sprite width, colour), in 1024x500 units.
INVADERS = [
    (610, 70, 62, RED),
    (760, 52, 54, CYAN),
    (910, 96, 66, YELLOW),
    (655, 205, 58, BLUE),
    (955, 250, 52, WHITE),
    (840, 330, 60, GREEN),
]
# The one being hit, and where the shot comes from (below the frame).
TARGET = (800, 190, 64, MAGENTA)
ORIGIN = (770, 560)


def background():
    """Space gradient brightest behind the invaders, with scattered stars."""
    w, h = W * SS, H * SS
    img = Image.new("RGB", (w, h))
    px = img.load()
    cx, cy = w * 0.72, h * 0.45
    maxd = math.hypot(w, h) * 0.55
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy) / maxd
            px[x, y] = lerp(BG_CENTER, BG_EDGE, min(1, d * 1.2) ** 1.1)
    draw = ImageDraw.Draw(img)
    rnd = random.Random(7)
    for _ in range(110):
        x, y = rnd.random() * w, rnd.random() * h
        r = (0.6 + rnd.random() * 1.4) * SS
        a = rnd.randint(90, 200)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(a, a, a))
    return img.convert("RGBA")


def layer():
    return Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))


def invader(canvas, x, y, width, color):
    """One-colour invader with the game's soft glow, centred on (x, y)."""
    x, y, width = x * SS, y * SS, width * SS
    p = width / COLS
    left, top = x - width / 2, y - p * ROWS / 2

    glow = layer()
    r = width * 0.5
    ImageDraw.Draw(glow).ellipse([x - r, y - r, x + r, y + r],
                                 fill=color + (80,))
    canvas = Image.alpha_composite(canvas, glow.filter(
        ImageFilter.GaussianBlur(width * 0.25)))

    body = layer()
    d = ImageDraw.Draw(body)
    for row, line in enumerate(SPRITE):
        for col, ch in enumerate(line):
            if ch == "X":
                x0, y0 = left + col * p, top + row * p
                d.rectangle([x0, y0, x0 + p + 0.5, y0 + p + 0.5],
                            fill=color + (255,))
    return Image.alpha_composite(canvas, body)


def shot(canvas, origin, radius, color):
    """The expanding circle: faint fill, blurred halo, crisp edge."""
    cx, cy, r = origin[0] * SS, origin[1] * SS, radius * SS
    box = [cx - r, cy - r, cx + r, cy + r]
    fill = layer()
    ImageDraw.Draw(fill).ellipse(box, fill=color + (18,))
    canvas = Image.alpha_composite(canvas, fill)
    halo = layer()
    ImageDraw.Draw(halo).ellipse(box, outline=color + (110,), width=12 * SS)
    canvas = Image.alpha_composite(canvas, halo.filter(
        ImageFilter.GaussianBlur(8 * SS)))
    edge = layer()
    ImageDraw.Draw(edge).ellipse(box, outline=color + (255,), width=4 * SS)
    return Image.alpha_composite(canvas, edge)


def burst(canvas, x, y, size, color):
    """Squares flying out of the hit, as in GamePainter._paintBurst."""
    out = layer()
    d = ImageDraw.Draw(out)
    for i in range(12):
        a = i * math.pi / 6 + 0.3
        dist = size * (0.95 + 0.2 * (i % 2))
        s = size * 0.075
        cx = (x + math.cos(a) * dist) * SS
        cy = (y + math.sin(a) * dist) * SS
        d.rectangle([cx - s * SS, cy - s * SS, cx + s * SS, cy + s * SS],
                    fill=color + (230 - 60 * (i % 2),))
    return Image.alpha_composite(canvas, out)


def text(canvas, xy, s, font, color, glow=None, spacing=0):
    """Draws [s] letter by letter so each can have its own colour."""
    x, y = xy[0] * SS, xy[1] * SS
    colors = color if isinstance(color, list) else [color] * len(s)
    for ch, c in zip(s, colors):
        if glow:
            g = layer()
            ImageDraw.Draw(g).text((x, y), ch, font=font, fill=c + (glow,))
            canvas = Image.alpha_composite(canvas, g.filter(
                ImageFilter.GaussianBlur(10 * SS)))
        t = layer()
        ImageDraw.Draw(t).text((x, y), ch, font=font, fill=c + (255,))
        canvas = Image.alpha_composite(canvas, t)
        x += font.getlength(ch) + spacing * SS
    return canvas


def main():
    img = background()

    tx, ty, tw, tc = TARGET
    hit_radius = math.hypot(tx - ORIGIN[0], ty - ORIGIN[1]) - tw * 0.2
    img = shot(img, ORIGIN, hit_radius, MAGENTA)
    for x, y, w, c in INVADERS:
        img = invader(img, x, y, w, c)
    img = invader(img, tx, ty, tw, tc)
    img = burst(img, tx, ty, tw, MAGENTA)
    points = ImageFont.truetype(TITLE_FONT, 34 * SS)
    img = text(img, (tx + 30, ty - 100), "+2", points, [MAGENTA, MAGENTA],
               glow=160)

    rgb = ImageFont.truetype(TITLE_FONT, 132 * SS)
    img = text(img, (62, 72), "RGB", rgb, [RED, GREEN, BLUE], glow=150,
               spacing=4)
    invaders = ImageFont.truetype(TITLE_FONT, 62 * SS)
    img = text(img, (66, 245), "INVADERS", invaders, WHITE, glow=70,
               spacing=3)
    path, index = TAGLINE_FONT
    tagline = ImageFont.truetype(path, 27 * SS, index=index)
    img = text(img, (70, 350), "Mix the colours.", tagline, (0xD8, 0xD8, 0xE8))
    img = text(img, (70, 386), "Blast the invaders.", tagline,
               (0xD8, 0xD8, 0xE8))

    out = img.resize((W, H), Image.LANCZOS).convert("RGB")
    os.makedirs(STORE, exist_ok=True)
    path = os.path.join(STORE, "feature_graphic_1024x500.png")
    out.save(path)
    print(path)


if __name__ == "__main__":
    main()
