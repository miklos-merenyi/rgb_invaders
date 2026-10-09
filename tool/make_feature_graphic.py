#!/usr/bin/env python3
"""Draws the Google Play feature graphic and the App Store creative assets.

Run from the repo root:  python3 tool/make_feature_graphic.py   (needs Pillow,
and the macOS system fonts Arial Black and Avenir Next)

The title and tagline sit on the left. On the right, invaders in the game's
seven colours fall through space while a magenta circle, fired from below,
destroys the magenta one for +2, as in the game.

The scene is laid out on a 1024x500 design. Wider or taller outputs keep that
design centred vertically, leave the title on the left and move the invaders
to the right edge, so the same artwork fits every aspect ratio.

Output, in store_assets/:
  feature_graphic_1024x500.png        Google Play feature graphic
  app_store_header_3840x1646.png      App Store product page header (21:9)
  app_store_search_3840x2560.png      App Store search results (3:2)
"""

import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_icons import BG_CENTER, BG_EDGE, SPRITE, COLS, ROWS, STORE, lerp

# (file name, output width, output height, supersampling factor)
OUTPUTS = [
    ("feature_graphic_1024x500.png", 1024, 500, 2),
    ("app_store_header_3840x1646.png", 3840, 1646, 1),
    ("app_store_search_3840x2560.png", 3840, 2560, 1),
]

# The design every output is laid out on.
DESIGN_W, DESIGN_H = 1024, 500

# GameColors in lib/game/game.dart.
RED = (0xFF, 0x3B, 0x30)
GREEN = (0x34, 0xE0, 0x3A)
YELLOW = (0xFF, 0xEE, 0x33)
BLUE = (0x3D, 0x6B, 0xFF)
MAGENTA = (0xFF, 0x3D, 0xF5)
CYAN = (0x33, 0xF0, 0xFF)
WHITE = (0xFF, 0xFF, 0xFF)

# Frame A of the mixed-colour and white sprites in lib/game/game_painter.dart.
BAT = [
    "X.........X",
    "XX..X.X..XX",
    "XXX.XXX.XXX",
    "XXXXXXXXXXX",
    ".XXX.X.XXX.",
    "..XXXXXXX..",
    "...X.X.X...",
    "..X.....X..",
]
URCHIN = [
    ".....X.....",
    ".X..XXX..X.",
    "..XXXXXXX..",
    ".XXX.X.XXX.",
    "XXXXXXXXXXX",
    ".XXX...XXX.",
    "..XXXXXXX..",
    ".X..XXX..X.",
]
SPRITES = {YELLOW: BAT, CYAN: BAT, MAGENTA: BAT, WHITE: URCHIN}

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
# The one being hit, and where the shot comes from (60 below the frame).
TARGET = (800, 190, 64, MAGENTA)
ORIGIN = (770, 560)


class Canvas:
    """A scene of [w]x[h] design units drawn at [k] pixels per unit."""

    def __init__(self, w, h, k):
        self.w, self.h, self.k = w, h, k
        self.size = (round(w * k), round(h * k))

    def layer(self):
        return Image.new("RGBA", self.size, (0, 0, 0, 0))


def background(c):
    """Space gradient brightest behind the invaders, with scattered stars."""
    # The gradient is smooth, so it is computed at 2 pixels per unit and
    # scaled to the canvas.
    w, h = round(c.w * 2), round(c.h * 2)
    img = Image.new("RGB", (w, h))
    px = img.load()
    cx, cy = w - (DESIGN_W * 2) * 0.28, h * 0.45
    maxd = math.hypot(DESIGN_W * 2, DESIGN_H * 2) * 0.55
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy) / maxd
            px[x, y] = lerp(BG_CENTER, BG_EDGE, min(1, d * 1.2) ** 1.1)
    if img.size != c.size:
        img = img.resize(c.size, Image.BICUBIC)
    draw = ImageDraw.Draw(img)
    rnd = random.Random(7)
    k = c.k
    for _ in range(round(110 * c.w * c.h / (DESIGN_W * DESIGN_H))):
        x, y = rnd.random() * c.w * k, rnd.random() * c.h * k
        r = (0.6 + rnd.random() * 1.4) * k
        a = rnd.randint(90, 200)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=(a, a, a))
    return img.convert("RGBA")


def invader(c, canvas, x, y, width, color):
    """One-colour invader with the game's soft glow, centred on (x, y)."""
    x, y, width = x * c.k, y * c.k, width * c.k
    p = width / COLS
    left, top = x - width / 2, y - p * ROWS / 2

    glow = c.layer()
    r = width * 0.5
    ImageDraw.Draw(glow).ellipse([x - r, y - r, x + r, y + r],
                                 fill=color + (80,))
    canvas = Image.alpha_composite(canvas, glow.filter(
        ImageFilter.GaussianBlur(width * 0.25)))

    body = c.layer()
    d = ImageDraw.Draw(body)
    for row, line in enumerate(SPRITES.get(color, SPRITE)):
        for col, ch in enumerate(line):
            if ch == "X":
                x0, y0 = left + col * p, top + row * p
                d.rectangle([x0, y0, x0 + p + 0.5, y0 + p + 0.5],
                            fill=color + (255,))
    return Image.alpha_composite(canvas, body)


def shot(c, canvas, origin, radius, color):
    """The expanding circle: faint fill, blurred halo, crisp edge."""
    k = c.k
    cx, cy, r = origin[0] * k, origin[1] * k, radius * k
    box = [cx - r, cy - r, cx + r, cy + r]
    fill = c.layer()
    ImageDraw.Draw(fill).ellipse(box, fill=color + (18,))
    canvas = Image.alpha_composite(canvas, fill)
    halo = c.layer()
    ImageDraw.Draw(halo).ellipse(box, outline=color + (110,),
                                 width=round(12 * k))
    canvas = Image.alpha_composite(canvas, halo.filter(
        ImageFilter.GaussianBlur(8 * k)))
    edge = c.layer()
    ImageDraw.Draw(edge).ellipse(box, outline=color + (255,),
                                 width=round(4 * k))
    return Image.alpha_composite(canvas, edge)


def burst(c, canvas, x, y, size, color):
    """Squares flying out of the hit, as in GamePainter._paintBurst."""
    k = c.k
    out = c.layer()
    d = ImageDraw.Draw(out)
    for i in range(12):
        a = i * math.pi / 6 + 0.3
        dist = size * (0.95 + 0.2 * (i % 2))
        s = size * 0.075
        cx = (x + math.cos(a) * dist) * k
        cy = (y + math.sin(a) * dist) * k
        d.rectangle([cx - s * k, cy - s * k, cx + s * k, cy + s * k],
                    fill=color + (230 - 60 * (i % 2),))
    return Image.alpha_composite(canvas, out)


def text(c, canvas, xy, s, size, color, glow=None, spacing=0, font=None):
    """Draws [s] letter by letter so each can have its own colour."""
    path, index = font or (TITLE_FONT, 0)
    font = ImageFont.truetype(path, round(size * c.k), index=index)
    x, y = xy[0] * c.k, xy[1] * c.k
    colors = color if isinstance(color, list) else [color] * len(s)
    for ch, col in zip(s, colors):
        if glow:
            g = c.layer()
            ImageDraw.Draw(g).text((x, y), ch, font=font, fill=col + (glow,))
            canvas = Image.alpha_composite(canvas, g.filter(
                ImageFilter.GaussianBlur(10 * c.k)))
        t = c.layer()
        ImageDraw.Draw(t).text((x, y), ch, font=font, fill=col + (255,))
        canvas = Image.alpha_composite(canvas, t)
        x += font.getlength(ch) + spacing * c.k
    return canvas


def render(name, out_w, out_h, ss):
    # Widen or heighten the design to the output's aspect ratio.
    w = max(DESIGN_W, DESIGN_H * out_w / out_h)
    h = max(DESIGN_H, DESIGN_W * out_h / out_w)
    c = Canvas(w, h, out_w / w * ss)
    dx, dy = w - DESIGN_W, (h - DESIGN_H) / 2  # invaders: right, centred

    img = background(c)

    tx, ty, tw, tc = TARGET
    tx, ty = tx + dx, ty + dy
    origin = (ORIGIN[0] + dx, h + ORIGIN[1] - DESIGN_H)
    hit_radius = math.hypot(tx - origin[0], ty - origin[1]) - tw * 0.2
    img = shot(c, img, origin, hit_radius, MAGENTA)
    for x, y, iw, col in INVADERS:
        img = invader(c, img, x + dx, y + dy, iw, col)
    img = invader(c, img, tx, ty, tw, tc)
    img = burst(c, img, tx, ty, tw, MAGENTA)
    img = text(c, img, (tx + 30, ty - 100), "+2", 34, [MAGENTA, MAGENTA],
               glow=160)

    img = text(c, img, (62, 72 + dy), "RGB", 132, [RED, GREEN, BLUE],
               glow=150, spacing=4)
    img = text(c, img, (66, 245 + dy), "INVADERS", 62, WHITE, glow=70,
               spacing=3)
    grey = (0xD8, 0xD8, 0xE8)
    img = text(c, img, (70, 350 + dy), "Mix the colours.", 27, grey,
               font=TAGLINE_FONT)
    img = text(c, img, (70, 386 + dy), "Blast the invaders.", 27, grey,
               font=TAGLINE_FONT)

    # RGB without alpha: App Store Connect rejects transparency.
    out = img.resize((out_w, out_h), Image.LANCZOS).convert("RGB")
    os.makedirs(STORE, exist_ok=True)
    path = os.path.join(STORE, name)
    out.save(path)
    print(path)


def main():
    for output in OUTPUTS:
        render(*output)


if __name__ == "__main__":
    main()
