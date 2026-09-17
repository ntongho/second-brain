#!/usr/bin/env python3
"""Vector-ish brand rasterizer. Geometric only — no photo, no model."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

CANVAS = (14, 14, 13, 255)  # #0E0E0D
INK = (243, 241, 238, 255)  # #F3F1EE
HAIR = (42, 41, 38, 255)  # #2A2926
ROOT = Path(__file__).resolve().parents[1]


def _draw_mark(size: int, *, bg: tuple[int, int, int, int] | None, safe: float = 0.0) -> Image.Image:
    img = Image.new("RGBA", (size, size), bg if bg is not None else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    inset = int(size * (0.18 + safe))
    outer = [inset, inset, size - inset - 1, size - inset - 1]
    radius = max(4, int((outer[2] - outer[0]) * 0.18))
    d.rounded_rectangle(outer, radius=radius, fill=INK)

    # inner page
    pad = max(2, int(size * 0.045))
    inner = [outer[0] + pad, outer[1] + pad, outer[2] - pad, outer[3] - pad]
    ir = max(3, radius - pad)
    d.rounded_rectangle(inner, radius=ir, fill=CANVAS)

    # fold (top-right of inner page)
    w = inner[2] - inner[0]
    fold = max(6, int(w * 0.28))
    x1, y1, x2, y2 = inner
    d.polygon([(x2, y1), (x2 - fold, y1), (x2, y1 + fold)], fill=INK)

    # three quiet lines — a note, not a logo-mark explosion
    lx0 = inner[0] + int(w * 0.18)
    lx1 = inner[2] - int(w * 0.22)
    ly = inner[1] + int(w * 0.48)
    stroke = max(1, int(size * 0.028))
    gap = max(3, int(w * 0.12))
    for i, frac in enumerate((1.0, 0.78, 0.52)):
        y = ly + i * gap
        x_end = lx0 + int((lx1 - lx0) * frac)
        d.rounded_rectangle([lx0, y, x_end, y + stroke], radius=stroke // 2, fill=HAIR)
    return img


def _save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG")
    print(path.relative_to(ROOT))


def main() -> None:
    brand = ROOT / "assets" / "brand"
    web = ROOT / "web"

    master = _draw_mark(1024, bg=CANVAS)
    _save(master, brand / "icon-1024.png")
    _save(master.resize((512, 512), Image.Resampling.LANCZOS), brand / "icon-512.png")
    _save(master.resize((192, 192), Image.Resampling.LANCZOS), brand / "icon-192.png")
    _save(master.resize((180, 180), Image.Resampling.LANCZOS), brand / "apple-touch-icon.png")
    _save(master.resize((64, 64), Image.Resampling.LANCZOS), brand / "mark-64.png")
    _save(master.resize((32, 32), Image.Resampling.LANCZOS), brand / "favicon-32.png")
    _save(master.resize((16, 16), Image.Resampling.LANCZOS), brand / "favicon-16.png")

    fg = _draw_mark(1024, bg=None, safe=0.12)
    _save(fg, brand / "adaptive-foreground-1024.png")

    mask = _draw_mark(1024, bg=CANVAS, safe=0.12)
    _save(mask.resize((512, 512), Image.Resampling.LANCZOS), brand / "maskable-512.png")
    _save(mask.resize((192, 192), Image.Resampling.LANCZOS), brand / "maskable-192.png")

    # Flutter web defaults (overwrite after `flutter create`)
    _save(master.resize((32, 32), Image.Resampling.LANCZOS), web / "favicon.png")
    _save(master.resize((192, 192), Image.Resampling.LANCZOS), web / "icons" / "Icon-192.png")
    _save(master.resize((512, 512), Image.Resampling.LANCZOS), web / "icons" / "Icon-512.png")
    _save(mask.resize((192, 192), Image.Resampling.LANCZOS), web / "icons" / "Icon-maskable-192.png")
    _save(mask.resize((512, 512), Image.Resampling.LANCZOS), web / "icons" / "Icon-maskable-512.png")
    _save(master.resize((180, 180), Image.Resampling.LANCZOS), web / "apple-touch-icon.png")

    # Android mipmap densities from 48dp base + drop-in overlay for flutter create
    android = brand / "android"
    overlay = ROOT / "android_overlay" / "app" / "src" / "main" / "res"
    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    fg_px = {
        "drawable-mdpi": 108,
        "drawable-hdpi": 162,
        "drawable-xhdpi": 216,
        "drawable-xxhdpi": 324,
        "drawable-xxxhdpi": 432,
    }
    for name, px in densities.items():
        icon = master.resize((px, px), Image.Resampling.LANCZOS)
        _save(icon, android / name / "ic_launcher.png")
        _save(icon, overlay / name / "ic_launcher.png")
        _save(icon, overlay / name / "ic_launcher_round.png")
    for name, px in fg_px.items():
        _save(fg.resize((px, px), Image.Resampling.LANCZOS), overlay / name / "ic_launcher_foreground.png")

    ios = brand / "ios"
    for px in (20, 29, 40, 58, 60, 76, 80, 87, 120, 152, 167, 180, 1024):
        _save(master.resize((px, px), Image.Resampling.LANCZOS), ios / f"AppIcon-{px}.png")


if __name__ == "__main__":
    main()
