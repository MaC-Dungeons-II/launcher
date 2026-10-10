"""DMG window background: light lavender gradient with an arrow from
the app to the Applications link. 640x400 pt, written at 1x and 2x.

Run: uv run --no-project --with pillow python app/dmg/make_background.py
"""
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
W, H = 640, 400
TOP, BOTTOM = (246, 243, 255), (226, 219, 248)  # light lavender, readable Finder labels


def render(scale):
    w, h = W * scale, H * scale
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / (h - 1)
        d.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    # arrow between the two icons (icons sit at x=160 and x=480, y=190)
    c = (219, 87, 150)  # portal magenta
    y = 190 * scale
    d.rounded_rectangle([250 * scale, y - 5 * scale, 372 * scale, y + 5 * scale], radius=5 * scale, fill=c)
    d.polygon([(368 * scale, y - 22 * scale), (398 * scale, y), (368 * scale, y + 22 * scale)], fill=c)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 15 * scale)
    except OSError:
        font = ImageFont.load_default()
    text = "Drag to Applications to install"
    tw = d.textlength(text, font=font)
    d.text(((w - tw) / 2, 318 * scale), text, font=font, fill=(88, 76, 140))
    return img


# Finder takes a multi-resolution TIFF for Retina backgrounds
lo, hi = HERE / "background.png", HERE / "background@2x.png"
render(1).save(lo)
render(2).save(hi)
subprocess.run(["tiffutil", "-cathidpicheck", str(lo), str(hi), "-out", str(HERE / "background.tiff")], check=True)
lo.unlink()
hi.unlink()
