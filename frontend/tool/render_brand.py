#!/usr/bin/env python3
"""Geometric twin-lobe mark. Vector-ish raster — no photo, no model."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

CANVAS = (14, 14, 13, 255)  # #0E0E0D
INK = (243, 241, 238, 255)  # #F3F1EE
ECHO = (90, 88, 84, 255)  # dim twin
ROOT = Path(__file__).resolve().parents[1]


def _box(m: float, span: float, x0: float, y0: float, x1: float, y1: float) -> list[float]:
    return [
        m + x0 * span,
        m + y0 * span,
        m + x1 * span,
        m + y1 * span,
    ]


def _lobes(d: ImageDraw.ImageDraw, m: float, span: float, dx: float, dy: float, fill, outline=None, width: int = 0) -> None:
    def e(x0: float, y0: float, x1: float, y1: float) -> None:
        b = _box(m, span, x0, y0, x1, y1)
        b[0] += dx
        b[2] += dx
        b[1] += dy
        b[3] += dy
        kw: dict = {"fill": fill}
        if outline is not None:
            kw["outline"] = outline
            kw["width"] = width
        d.ellipse(b, **kw)

    e(0.06, 0.16, 0.58, 0.78)  # left hemisphere
    e(0.38, 0.10, 0.94, 0.72)  # right hemisphere
    e(0.18, 0.58, 0.52, 0.94)  # cerebellum


def _draw_mark(size: int, *, bg: tuple[int, int, int, int] | None, safe: float = 0.0) -> Image.Image:
    img = Image.new("RGBA", (size, size), bg if bg is not None else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = size * (0.14 + safe)
    span = size - 2 * m
    echo_w = max(2, int(size * 0.028))
    shift = span * 0.055

    _lobes(d, m, span, shift, shift * 0.7, None, outline=ECHO, width=echo_w)
    _lobes(d, m, span, 0, 0, INK)

    # midline cleft — two thoughts, one mark
    cx = m + span * 0.48
    cleft_w = max(2, int(size * 0.034))
    d.line(
        [(cx, m + span * 0.20), (cx + span * 0.04, m + span * 0.68)],
        fill=bg if bg is not None else CANVAS,
        width=cleft_w,
    )
    # stem
    stem = _box(m, span, 0.46, 0.78, 0.58, 0.97)
    r = max(2, int(span * 0.04))
    d.rounded_rectangle(stem, radius=r, fill=INK)
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

    _save(master.resize((32, 32), Image.Resampling.LANCZOS), web / "favicon.png")
    _save(master.resize((192, 192), Image.Resampling.LANCZOS), web / "icons" / "Icon-192.png")
    _save(master.resize((512, 512), Image.Resampling.LANCZOS), web / "icons" / "Icon-512.png")
    _save(mask.resize((192, 192), Image.Resampling.LANCZOS), web / "icons" / "Icon-maskable-192.png")
    _save(mask.resize((512, 512), Image.Resampling.LANCZOS), web / "icons" / "Icon-maskable-512.png")
    _save(master.resize((180, 180), Image.Resampling.LANCZOS), web / "apple-touch-icon.png")

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
