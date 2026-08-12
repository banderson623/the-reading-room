#!/usr/bin/env python3
"""Normalize the supplied artwork into a clean, full-bleed 1024x1024 icon master.

The source is a dark rounded "card" (the real design) sitting off-center on a
white/transparent backdrop. This isolates the dark card, centers and slightly
overscans it to fill the canvas, and bleeds the card's own dark colour into every
corner so the whole tile is opaque and dark. macOS then applies its squircle mask
and the icon reaches the perimeter instead of floating in a smaller tile.

    python3 Tools/prepare-icon.py <source.png> <out-1024.png>
"""
import sys
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
S = 1024
OVERSCAN = 1.05      # sample just inside the card edges
CORNER = 150         # px of each corner forced to background

im = Image.open(src).convert("RGBA")
px = im.load()
w, h = im.size

# 1. Bounding box + average colour of the dark card (lum < 0.30, opaque).
minx, miny, maxx, maxy = w, h, 0, 0
rs = gs = bs = n = 0
for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a > 128 and (0.299*r + 0.587*g + 0.114*b) / 255 < 0.30:
            minx, maxx = min(minx, x), max(maxx, x)
            miny, maxy = min(miny, y), max(maxy, y)
            rs += r; gs += g; bs += b; n += 1
bg = (rs // n, gs // n, bs // n) if n else (17, 18, 18)
card = im.crop((minx, miny, maxx + 1, maxy + 1))
cw, ch = card.size
print(f"card bbox {minx}..{maxx} x {miny}..{maxy}  bg={bg}")

# 2. Scale the card to cover the canvas (with a little overscan) and centre it.
scale = S / min(cw, ch) * OVERSCAN
scaled = card.resize((round(cw * scale), round(ch * scale)), Image.LANCZOS)

canvas = Image.new("RGBA", (S, S), bg + (255,))
ox = (S - scaled.width) // 2
oy = (S - scaled.height) // 2
canvas.alpha_composite(scaled, (ox, oy))   # card over its own dark bg

# 3. Replace the corner regions with solid background, erasing the source's
#    stray white/rounded corners. Both come out dark, so the tile is a clean,
#    fully-opaque square; macOS supplies the rounding.
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=CORNER, fill=255)
plate = Image.new("RGBA", (S, S), bg + (255,))
final = Image.composite(canvas, plate, mask).convert("RGB")
final.save(out)
print(f"wrote {out}")
