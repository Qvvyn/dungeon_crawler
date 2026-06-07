#!/usr/bin/env python3
# Render an ASCII art .txt (or several, side by side) to a PNG using the game's
# Departure Mono font, so the art can be visually checked the way it renders
# in-game. Usage: py tools/render_ascii.py out.png file1.txt [file2.txt ...]
import sys
from PIL import Image, ImageDraw, ImageFont

FONT = "assets/fonts/DepartureMono-Regular.otf"
SIZE = 22
BG = (18, 18, 28)
FG = (235, 235, 248)
LABEL = (130, 200, 255)

def load(path):
    with open(path, encoding="utf-8") as f:
        return f.read().rstrip("\n").split("\n")

def main():
    out = sys.argv[1]
    paths = sys.argv[2:]
    font = ImageFont.truetype(FONT, SIZE)
    asc, desc = font.getmetrics()
    lh = asc + desc - 4              # tighten like the game's negative line_sep
    cw = font.getlength("M")
    panels = []
    for p in paths:
        lines = load(p)
        cols = max((len(l) for l in lines), default=1)
        w = int(cw * cols)
        h = lh * (len(lines) + 1)    # +1 row for the filename label
        panels.append((p.split("/")[-1], lines, w, h))
    gap = int(cw * 4)
    W = sum(w for _, _, w, _ in panels) + gap * (len(panels) + 1)
    H = max(h for _, _, _, h in panels) + 24
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    x = gap
    for name, lines, w, h in panels:
        d.text((x, 6), name, font=font, fill=LABEL)
        y = 6 + lh
        for line in lines:
            d.text((x, y), line, font=font, fill=FG)
            y += lh
        x += w + gap
    img.save(out)
    print(f"saved {out}  ({W}x{H}, {len(panels)} panel(s))")

if __name__ == "__main__":
    main()
