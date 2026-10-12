"""M(a)C Dungeons II app icon, designed for Liquid Glass.

Bold, flat silhouettes on a gradient fill; depth, highlights and translucency
come from the system's glass material instead of painted detail:
  - background: night gradient fill (icon.json)
  - Gate (glass): a stepped, blocky dungeon arch with a base slab
  - Portal (glass, front): the doorway glow, warm orange to magenta, and two
    torch flames on the pillar faces
Each layer is a white mask; colours are fills in icon.json, so light/dark/tinted
appearances are handled by the system.

Run: uv run --no-project --with pillow python app/icon/make_icon.py
Writes app/icon/AppIcon.icon (open in Icon Composer to tweak) and compiles
app/icon/compiled/{Assets.car,AppIcon.icns}.
"""
import json
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
SIZE = 1024
U = 32  # one block = 32 pt on the 1024 canvas (32 x 32 blocks)


WHITE, CLEAR = (255, 255, 255, 255), (0, 0, 0, 0)


def fill_blocks(img, blocks, fill):
    d = ImageDraw.Draw(img)
    for x0, y0, x1, y1 in blocks:  # inclusive block ranges
        d.rectangle([x0 * U, y0 * U, (x1 + 1) * U - 1, (y1 + 1) * U - 1], fill=fill)
    return img


def mask(blocks):
    return fill_blocks(Image.new("RGBA", (SIZE, SIZE), CLEAR), blocks, WHITE)


def cut(img, blocks):
    return fill_blocks(img, blocks, CLEAR)


def stepped(x0, x1, top, bottom, steps):
    """Rectangle x0..x1, top..bottom whose top corners step inward like a
    pixel-art arch: steps = [(inset, rows), ...] from the crown downwards."""
    rows, y = [], top
    for inset, n in steps:
        rows.append((x0 + inset, y, x1 - inset, y + n - 1))
        y += n
    rows.append((x0, y, x1, bottom))
    return rows


# Gate spans columns 7..24; doorway columns 11..20 (16 x 32 grid units).
OPENING = stepped(11, 20, 10, 24, [(3, 1), (2, 1), (1, 1)])


def gate():
    img = mask(stepped(7, 24, 5, 24, [(5, 1), (3, 1), (2, 1), (1, 2)]) + [(5, 24, 26, 26)])
    return cut(img, OPENING)


def portal():
    return mask(OPENING)


def torches():
    flames = []
    for x in (8, 22):            # mounted on the pillar faces
        flames += [(x, 12, x + 1, 12), (x, 13, x + 1, 14)]
    return mask(flames)


def color(r, g, b):
    return f"display-p3:{r:.5f},{g:.5f},{b:.5f},1.00000"


def layer(name, fill):
    return {
        "blend-mode": "normal",
        "fill": fill,
        "glass": True,
        "hidden": False,
        "image-name": f"{name}.png",
        "name": name,
        "position": {"scale": 1, "translation-in-points": [0, 0]},
    }


def write_icon_document():
    doc = HERE / "AppIcon.icon"
    shutil.rmtree(doc, ignore_errors=True)
    (doc / "Assets").mkdir(parents=True)
    gate().save(doc / "Assets" / "Gate.png")
    portal().save(doc / "Assets" / "Portal.png")
    torches().save(doc / "Assets" / "Torches.png")
    vertical = {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}
    manifest = {
        "fill": {
            "linear-gradient": [color(0.20, 0.16, 0.42), color(0.09, 0.06, 0.20)],
            "orientation": vertical,
        },
        "groups": [  # first group is frontmost
            {
                "name": "Portal",
                "layers": [
                    layer("Portal", {
                        "linear-gradient": [color(1.00, 0.74, 0.30), color(0.86, 0.22, 0.62)],
                        "orientation": vertical,
                    }),
                    layer("Torches", {"solid": color(1.00, 0.62, 0.20)}),
                ],
                "shadow": {"kind": "layer-color", "opacity": 0.6},
                "specular": True,
                "translucency": {"enabled": True, "value": 0.2},
            },
            {
                "name": "Gate",
                "layers": [layer("Gate", {"solid": color(0.88, 0.87, 0.95)})],
                "shadow": {"kind": "neutral", "opacity": 0.5},
                "specular": True,
                "translucency": {"enabled": True, "value": 0.35},
            },
        ],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }
    (doc / "icon.json").write_text(json.dumps(manifest, indent=2))
    return doc


def compile_icon(doc):
    out = HERE / "compiled"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir()
    subprocess.run([
        "xcrun", "actool", str(doc), "--compile", str(out),
        "--app-icon", "AppIcon", "--platform", "macosx", "--target-device", "mac",
        "--minimum-deployment-target", "14.0",
        "--output-partial-info-plist", str(out / "partial.plist"),
        "--errors", "--warnings",
    ], check=True, stdout=subprocess.DEVNULL)
    # flat preview of the rendered icon for quick review
    tmp = out / "preview.iconset"
    subprocess.run(["iconutil", "-c", "iconset", str(out / "AppIcon.icns"), "-o", str(tmp)], check=True)
    best = max(tmp.glob("*.png"), key=lambda p: Image.open(p).size[0])
    shutil.copy(best, HERE / "AppIcon-preview.png")
    shutil.rmtree(tmp)
    return out


def main():
    for stale in ("AppIcon.png", "AppIcon-glass-preview.png"):
        (HERE / stale).unlink(missing_ok=True)
    out = compile_icon(write_icon_document())
    print(sorted(p.name for p in out.iterdir()))


if __name__ == "__main__":
    main()
