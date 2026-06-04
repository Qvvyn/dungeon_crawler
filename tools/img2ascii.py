#!/usr/bin/env python3
"""Convert an image into monospace ASCII art for use as a large set-piece.

This is an OFFLINE authoring step — run it on your machine, hand-tidy the
output, then drop the .txt into res://assets/ascii/. It is NOT a runtime
dependency and is never imported by the game.

Use this only for LARGE art (title screen, boss reveals, NPC portraits, death
screen). Small entity sprites should be hand-authored in scripts/AsciiSprites.gd
— auto-conversion at sprite scale looks like noise.

Usage:
    python tools/img2ascii.py input.png -w 60 -o assets/ascii/dragon.txt
    python tools/img2ascii.py input.png -w 80 --invert        # for light-on-dark sources

Requires Pillow:  pip install pillow

Prefer `chafa` if you have it — it has higher fidelity:
    chafa --format symbols --symbols ascii --size 60x36 --fg-only -c none in.png > out.txt
This script is the dependency-light fallback / fine-tuning option.
"""

import argparse
import sys

# Dark -> light ramp. Index 0 is the darkest cell, last is lightest (space).
# Reversed with --invert when the subject is light on a dark background.
RAMP = "@%#*+=-:. "


def main() -> int:
    ap = argparse.ArgumentParser(description="Image -> monospace ASCII art")
    ap.add_argument("input", help="source image (png/jpg/…) ")
    ap.add_argument("-w", "--width", type=int, default=60,
                    help="output width in characters (default 60)")
    ap.add_argument("-o", "--output", default=None,
                    help="output .txt path (default: stdout)")
    ap.add_argument("--invert", action="store_true",
                    help="invert brightness (use for light subjects on dark backgrounds)")
    ap.add_argument("--aspect", type=float, default=0.5,
                    help="char height/width ratio correction (default 0.5 — "
                         "monospace cells are ~2x taller than wide)")
    args = ap.parse_args()

    try:
        from PIL import Image
    except ImportError:
        print("Pillow not installed. Run: pip install pillow", file=sys.stderr)
        return 1

    img = Image.open(args.input).convert("L")
    w0, h0 = img.size
    new_w = max(1, args.width)
    new_h = max(1, int(h0 / w0 * new_w * args.aspect))
    img = img.resize((new_w, new_h))

    ramp = RAMP[::-1] if args.invert else RAMP
    n = len(ramp) - 1
    px = img.load()
    lines = []
    for y in range(new_h):
        row = []
        for x in range(new_w):
            lum = px[x, y]  # 0..255
            row.append(ramp[lum * n // 255])
        lines.append("".join(row).rstrip())
    art = "\n".join(lines)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            f.write(art + "\n")
        print(f"wrote {args.output} ({new_w}x{new_h})", file=sys.stderr)
    else:
        print(art)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
