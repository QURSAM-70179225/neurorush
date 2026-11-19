#!/usr/bin/env python3
"""Generates the NeuroRush app icon, adaptive-icon layers and Play feature graphic.

Run from the repo root: python3 tool/make_branding.py
Outputs: assets/branding/*.png and docs/store/{icon-512,feature-graphic}.png
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "branding"
STORE = ROOT / "docs" / "store"
VIOLET, PINK, CYAN, AMBER = (108, 77, 255), (255, 77, 157), (34, 199, 238), (255, 176, 32)


def gradient(size, c1, c2):
    w, h = size
    img = Image.new("RGB", size, c1)
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w + y / h) / 2
            px[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
    return img


def bolt(draw, cx, cy, s, fill):
    """Lightning bolt centred at (cx, cy) with height ~ 2*s."""
    pts = [(-0.10, -1.00), (0.55, -1.00), (0.15, -0.15), (0.60, -0.15), (-0.30, 1.00), (0.00, 0.12), (-0.48, 0.12)]
    draw.polygon([(cx + x * s, cy + y * s) for x, y in pts], fill=fill)


def brain_arcs(draw, cx, cy, r, width, fill):
    """Two stylised brain hemispheres around the bolt."""
    for side in (-1, 1):
        box = [cx + side * r * 0.05 - r, cy - r, cx + side * r * 0.05 + r, cy + r]
        start, end = (100, 260) if side < 0 else (-80, 80)
        draw.arc(box, start, end, fill=fill, width=width)
        inner = [cx + side * r * 0.3 - r * 0.55, cy - r * 0.55, cx + side * r * 0.3 + r * 0.55, cy + r * 0.55]
        s2, e2 = (120, 240) if side < 0 else (-60, 60)
        draw.arc(inner, s2, e2, fill=fill, width=int(width * 0.75))


def glyph_layer(size, scale=1.0):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size / 2
    brain_arcs(d, c, c, size * 0.36 * scale, max(4, int(size * 0.045 * scale)), (255, 255, 255, 235))
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bolt(ImageDraw.Draw(shadow), c + size * 0.012, c + size * 0.02, size * 0.27 * scale, (40, 0, 80, 110))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(size * 0.012)))
    bolt(ImageDraw.Draw(img), c, c, size * 0.27 * scale, (255, 214, 64, 255))
    return img


def icon(size):
    bg = gradient((size, size), VIOLET, PINK).convert("RGBA")
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(Image.alpha_composite(bg, glyph_layer(size)), (0, 0), mask)
    return out


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    STORE.mkdir(parents=True, exist_ok=True)
    icon(1024).save(OUT / "icon.png")
    # Adaptive icon: full-bleed background + foreground inside the 66% safe zone.
    gradient((1024, 1024), VIOLET, PINK).save(OUT / "icon_background.png")
    glyph_layer(1024, scale=0.62).save(OUT / "icon_foreground.png")
    # Play Store: 512x512 icon (no transparency) and 1024x500 feature graphic.
    store_icon = Image.new("RGB", (512, 512), VIOLET)
    full = gradient((512, 512), VIOLET, PINK).convert("RGBA")
    store_icon.paste(Image.alpha_composite(full, glyph_layer(512)).convert("RGB"))
    store_icon.save(STORE / "icon-512.png")

    fg = gradient((1024, 500), VIOLET, PINK).convert("RGBA")
    d = ImageDraw.Draw(fg)
    for i, (x, y, r, col) in enumerate([(880, 90, 60, CYAN), (960, 400, 40, AMBER), (70, 430, 50, CYAN), (620, 40, 26, AMBER)]):
        d.ellipse([x - r, y - r, x + r, y + r], fill=col + (90,))
    fg.alpha_composite(icon(300), (60, 100))
    bold = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 92)
    reg = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 38)
    d.text((410, 135), "NeuroRush", font=bold, fill="white")
    max_w = 1024 - 414 - 40
    for y, line, alpha in [(255, "Brain training in 60 seconds", 235), (310, "8 games · AI coach · 1v1 battles", 200)]:
        size = 38
        font = reg
        while d.textlength(line, font=font) > max_w:
            size -= 1
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size)
        d.text((414, y), line, font=font, fill=(255, 255, 255, alpha))
    fg.convert("RGB").save(STORE / "feature-graphic.png")
    print("Wrote branding assets")


if __name__ == "__main__":
    main()
