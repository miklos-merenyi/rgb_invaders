#!/usr/bin/env python3
"""Draws the app icon and writes every size iOS and Android need.

Run from the repo root:  python3 tool/make_icons.py   (needs Pillow)

The icon is the game's invader sprite in rainbow rows of the six colours
(red, yellow, green, cyan, blue, magenta), glowing over a dark space
background with a faint expanding circle behind it.

Outputs:
  iOS      ios/Runner/Assets.xcassets/AppIcon.appiconset/
           1024x1024 light, dark and tinted variants (single-size catalog).
  Android  adaptive icon (API 26+): foreground/background PNG layers per
           density + vector monochrome layer for themed icons (Android 13+);
           legacy square and round PNGs for API 24-25;
  Stores   store_assets/: 512x512 Google Play icon, 1024x1024 App Store icon.
"""

import json
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..")
IOS_SET = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
RES = os.path.join(ROOT, "android/app/src/main/res")
STORE = os.path.join(ROOT, "store_assets")

# Same sprite as lib/game/game_painter.dart (frame A).
SPRITE = [
    "..X.....X..",
    "...X...X...",
    "..XXXXXXX..",
    ".XX.XXX.XX.",
    "XXXXXXXXXXX",
    "X.XXXXXXX.X",
    "X.X.....X.X",
    "...XX.XX...",
]
COLS, ROWS = len(SPRITE[0]), len(SPRITE)

# Hue order around the colour wheel, matching GameColors in lib/game/game.dart.
RAINBOW = [
    (0xFF, 0x3B, 0x30),  # red
    (0xFF, 0xEE, 0x33),  # yellow
    (0x34, 0xE0, 0x3A),  # green
    (0x33, 0xF0, 0xFF),  # cyan
    (0x3D, 0x6B, 0xFF),  # blue
    (0xFF, 0x3D, 0xF5),  # magenta
]

BG_CENTER = (0x24, 0x16, 0x52)
BG_EDGE = (0x05, 0x04, 0x12)

# Supersampling factor for smooth edges.
SS = 2


# Sprite row -> colour: antennae red, then one band per row, feet magenta.
ROW_COLOR = [0, 0, 1, 2, 3, 4, 5, 5]


def pixel_color(row, col):
    """Horizontal rainbow bands, top to bottom."""
    return RAINBOW[ROW_COLOR[row]]


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def background(size, stars=True):
    """Radial space gradient with a few stars."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    cx, cy = size / 2, size * 0.45
    maxd = (size**2 / 2) ** 0.5
    for y in range(size):
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / maxd
            px[x, y] = lerp(BG_CENTER, BG_EDGE, min(1, d * 1.35) ** 1.2)
    if stars:
        draw = ImageDraw.Draw(img)
        # Fixed positions (fractions of size) so every output matches.
        for fx, fy, r in [
            (0.14, 0.18, 0.006), (0.83, 0.13, 0.005), (0.72, 0.30, 0.004),
            (0.22, 0.74, 0.004), (0.88, 0.70, 0.006), (0.10, 0.48, 0.003),
            (0.62, 0.86, 0.004), (0.40, 0.10, 0.003), (0.92, 0.45, 0.003),
        ]:
            s = r * size
            draw.ellipse([fx * size - s, fy * size - s, fx * size + s,
                          fy * size + s], fill=(255, 255, 255))
    return img


def ring_layer(size, center, radius, width, alpha):
    """A faint white expanding circle, like a shot in the game."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - radius, cy - radius, cx + radius, cy + radius],
              outline=(255, 255, 255, alpha), width=round(width))
    glow = layer.filter(ImageFilter.GaussianBlur(width * 1.5))
    return Image.alpha_composite(glow, layer)


def sprite_layer(size, sprite_width, center, mono=None):
    """The rainbow invader with a soft glow. [mono] draws it in one colour."""
    px = sprite_width / COLS
    left = center[0] - sprite_width / 2
    top = center[1] - px * ROWS / 2
    body = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    for r, line in enumerate(SPRITE):
        for c, ch in enumerate(line):
            if ch != "X":
                continue
            x0, y0 = left + c * px, top + r * px
            # A thin gap between pixels keeps the retro LED look.
            gap = px * 0.07
            box = [x0 + gap, y0 + gap, x0 + px - gap, y0 + px - gap]
            if mono is not None:
                d.rounded_rectangle(box, radius=px * 0.12, fill=mono)
                continue
            color = pixel_color(r, c)
            d.rounded_rectangle(box, radius=px * 0.12, fill=color + (255,))
            # Highlight on the top third of each pixel.
            hi = [box[0], box[1], box[2], box[1] + (box[3] - box[1]) * 0.3]
            d.rounded_rectangle(hi, radius=px * 0.12,
                                fill=lerp(color, (255, 255, 255), 0.4) + (255,))
    if mono is not None:
        return body
    glow = body.filter(ImageFilter.GaussianBlur(px * 1.1))
    glow.putalpha(glow.getchannel("A").point(lambda a: min(255, a * 1.1)))
    return Image.alpha_composite(glow, body)


SPRITE_SCALE = 0.66  # sprite width as a fraction of the visible icon
RING_RADIUS = 0.41

# An adaptive icon layer is 108dp but only the middle 72dp is ever visible,
# and masks may cut anything outside a 66dp circle. Scaling the artwork by
# 72/108 keeps the same look as iOS and keeps the sprite and ring inside
# that safe circle.
ADAPTIVE_SCALE = 72 / 108


def foreground(size, scale=1.0, ring_alpha=55, mono=None):
    """Transparent layer with the ring and the sprite, centred.

    [scale] shrinks the artwork (used for Android adaptive layers)."""
    c = (size / 2, size / 2)
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if ring_alpha:
        layer = Image.alpha_composite(
            layer, ring_layer(size, c, size * RING_RADIUS * scale,
                              size * 0.008 * scale, ring_alpha))
    return Image.alpha_composite(
        layer, sprite_layer(size, size * SPRITE_SCALE * scale, c, mono=mono))


def render(fn, size, *args, **kw):
    """Render at SS x size and downsample for smooth edges."""
    return fn(size * SS, *args, **kw).resize((size, size), Image.LANCZOS)


def full_icon(size):
    bg = render(background, size).convert("RGBA")
    return Image.alpha_composite(bg, render(foreground, size)).convert("RGB")


def rounded_mask(size, radius_frac):
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size * SS - 1, size * SS - 1], radius=size * SS * radius_frac,
        fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def circle_mask(size):
    mask = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(mask).ellipse([0, 0, size * SS - 1, size * SS - 1],
                                 fill=255)
    return mask.resize((size, size), Image.LANCZOS)


# ── iOS ──────────────────────────────────────────────────────────────────────

def write_ios():
    # Replace the Flutter template's per-size icons with a single-size set.
    for f in os.listdir(IOS_SET):
        if f.endswith(".png"):
            os.remove(os.path.join(IOS_SET, f))

    # Light: opaque, no alpha channel (App Store requirement).
    full_icon(1024).save(os.path.join(IOS_SET, "AppIcon.png"))
    # Dark: transparent background; iOS supplies its own dark backdrop.
    render(foreground, 1024, ring_alpha=40).save(
        os.path.join(IOS_SET, "AppIcon-Dark.png"))
    # Tinted: grayscale on transparent; iOS colours it with the user's tint.
    render(foreground, 1024, ring_alpha=70, mono=(255, 255, 255, 255)).save(
        os.path.join(IOS_SET, "AppIcon-Tinted.png"))

    def entry(filename, appearance=None):
        e = {"filename": filename, "idiom": "universal", "platform": "ios",
             "size": "1024x1024"}
        if appearance:
            e["appearances"] = [{"appearance": "luminosity",
                                 "value": appearance}]
        return e

    contents = {
        "images": [entry("AppIcon.png"),
                   entry("AppIcon-Dark.png", "dark"),
                   entry("AppIcon-Tinted.png", "tinted")],
        "info": {"author": "xcode", "version": 1},
    }
    with open(os.path.join(IOS_SET, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")


# ── Android ──────────────────────────────────────────────────────────────────

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

ADAPTIVE_XML = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />
</adaptive-icon>
"""


def monochrome_vector():
    """Themed-icon layer: the sprite as a vector on the 108dp canvas."""
    width = 108 * SPRITE_SCALE * ADAPTIVE_SCALE
    px = width / COLS
    left = (108 - width) / 2
    top = (108 - px * ROWS) / 2
    gap = px * 0.07
    size = px - 2 * gap
    parts = []
    for r, line in enumerate(SPRITE):
        for c, ch in enumerate(line):
            if ch == "X":
                x, y = left + c * px + gap, top + r * px + gap
                parts.append(f"M{x:.2f},{y:.2f}h{size:.2f}v{size:.2f}"
                             f"h{-size:.2f}z")
    return f"""<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/make_icons.py. Themed icon layer (Android 13+). -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path
        android:fillColor="#FFFFFFFF"
        android:pathData="{''.join(parts)}" />
</vector>
"""


def write_android():
    for name, k in DENSITIES.items():
        d = os.path.join(RES, f"mipmap-{name}")
        os.makedirs(d, exist_ok=True)

        # Adaptive layers (API 26+): 108dp each.
        layer = round(108 * k)
        render(background, layer).save(
            os.path.join(d, "ic_launcher_background.png"))
        render(foreground, layer, scale=ADAPTIVE_SCALE).save(
            os.path.join(d, "ic_launcher_foreground.png"))

        # Legacy icons (API 24-25): 48dp, square with rounded corners, and round.
        legacy = round(48 * k)
        icon = full_icon(legacy).convert("RGBA")
        square = icon.copy()
        square.putalpha(rounded_mask(legacy, 0.18))
        square.save(os.path.join(d, "ic_launcher.png"))
        round_icon = icon.copy()
        round_icon.putalpha(circle_mask(legacy))
        round_icon.save(os.path.join(d, "ic_launcher_round.png"))

    anydpi = os.path.join(RES, "mipmap-anydpi-v26")
    os.makedirs(anydpi, exist_ok=True)
    for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
        with open(os.path.join(anydpi, name), "w") as f:
            f.write(ADAPTIVE_XML)
    with open(os.path.join(RES, "drawable", "ic_launcher_monochrome.xml"),
              "w") as f:
        f.write(monochrome_vector())


# ── Store listings ───────────────────────────────────────────────────────────

def write_store():
    os.makedirs(STORE, exist_ok=True)
    # Google Play: 512x512, full square; Play applies its own corner mask.
    full_icon(512).save(os.path.join(STORE, "play_store_icon_512.png"))
    # App Store Connect takes the icon from the build; this copy is for
    # listings and websites.
    full_icon(1024).save(os.path.join(STORE, "app_store_icon_1024.png"))


if __name__ == "__main__":
    write_ios()
    write_android()
    write_store()
