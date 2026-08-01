#!/usr/bin/env python3
"""Generate Android launcher mipmaps for Orvo's selectable icons.

FIX (app icon zoom): Android adaptive icons render a 108dp canvas but only
show the inner ~66% (the rest is reserved for launcher masks / parallax).
The old ic_launcher_N_fg.png files were full-bleed art, so launchers cropped
straight into the design ("zoomed" icons). Since icons 2+ are gradient tiles
(no single edge color for a flat background), this script bakes a correct
composition into the foreground bitmap itself:

  - backdrop: the SAME art, scaled full-bleed and gaussian-blurred, so the
    area outside the safe zone continues the icon's own gradient naturally
  - center:   the sharp art at 66% (the adaptive safe zone)

It also writes the legacy square icons (pre-Android-8 launchers).

Usage (from the project root):
    python tools/generate_launcher_icons.py 5        # just icon 5
    python tools/generate_launcher_icons.py 2 3 4 5  # several

Requires Pillow:  pip install pillow
Reads  assets/icons/icon<N>.png
Writes android/app/src/main/res/mipmap-*/ic_launcher_<N>.png and _fg.png
"""
import sys
from pathlib import Path

try:
    from PIL import Image, ImageFilter
except ImportError:
    sys.exit("Pillow is required:  pip install pillow")

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# density -> (legacy launcher px, adaptive layer px = 108dp * scale)
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

SAFE = 0.66  # adaptive safe-zone fraction of the 108dp canvas


def build_fg(src: Image.Image, size: int) -> Image.Image:
    """Blurred full-bleed backdrop + sharp art centered in the safe zone."""
    backdrop = src.resize((size, size), Image.LANCZOS).filter(
        ImageFilter.GaussianBlur(radius=max(2, size * 0.055))
    )
    inner = max(1, round(size * SAFE))
    sharp = src.resize((inner, inner), Image.LANCZOS)
    off = (size - inner) // 2
    backdrop.paste(sharp, (off, off))
    return backdrop


def main(indices):
    for n in indices:
        src_path = ROOT / "assets" / "icons" / f"icon{n}.png"
        if not src_path.exists():
            sys.exit(f"missing {src_path}")
        src = Image.open(src_path).convert("RGB")
        for density, (legacy_px, fg_px) in DENSITIES.items():
            d = RES / f"mipmap-{density}"
            d.mkdir(parents=True, exist_ok=True)
            src.resize((legacy_px, legacy_px), Image.LANCZOS).save(
                d / f"ic_launcher_{n}.png", optimize=True
            )
            build_fg(src, fg_px).save(d / f"ic_launcher_{n}_fg.png", optimize=True)
        print(f"icon{n}: wrote legacy + adaptive foregrounds for "
              f"{', '.join(DENSITIES)}")


if __name__ == "__main__":
    idx = [int(a) for a in sys.argv[1:]] or [2, 3, 4, 5]
    main(idx)
