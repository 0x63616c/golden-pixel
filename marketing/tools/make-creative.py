#!/usr/bin/env python3
"""The App Store creative asset (iOS 27 product page header + search results art).

One universal 16:9 PNG, 5244 x 2950, no alpha (Apple: "Creative assets specifications"). Art
is composed on an 874 x 492 art-pixel grid and blown up 6x with nearest-neighbour, so every
pixel is as crisp as in the game; one art row is trimmed off the bottom to land on 2950.

Composition: a lit pocket dug out of the dark, the wordmark and tagline inside Apple's art
safe area (1402 x 962 px at x 1921, y 660: the only part shown on every device and crop),
blue blocks shaded by durability around it, balls in flight, mint shards, and the golden
pixel glowing in the rock. The fog follows the game's rule: only cells within 3 cells of open
space are drawn; everything else is pure black.

Rules it keeps (App Store asset best practices): no price ("free"), no URLs, no copyright
symbol, no other platforms, no unverifiable claims; one clear idea; text legible.

Usage:  python3 marketing/tools/make-creative.py [--no-render]
Writes: marketing/assets/appstore-creative-5244x2950.png
"""
import argparse
import importlib.util
import random
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("assets", HERE / "make-assets.py")
A = importlib.util.module_from_spec(spec)
spec.loader.exec_module(A)
PAL = A.PAL

K = 6                       # device px per art px
W, H = 874, 492             # art canvas (5244 x 2952 before the trim)
OUT_W, OUT_H = 5244, 2950
CELL = 10                   # Tuning.cellPixels
SAFE = (1921 / K, 660 / K, (1921 + 1402) / K, (660 + 962) / K)  # art safe area (x0, y0, x1, y1)
REVEAL = 3                  # Tuning.revealRadius: cells lit around open space


def cave(seed):
    """Cells: 'open', 'block' (with a durability shade), 'gold', 'shard' or None (fog)."""
    rng = random.Random(seed)
    cols, rows = W // CELL + 2, H // CELL + 2
    ox, oy = -((cols * CELL - W) // 2), -((rows * CELL - H) // 2)  # grid origin in art px
    sx = ((SAFE[0] + SAFE[2]) / 2 - ox) / CELL
    sy = ((SAFE[1] + SAFE[3]) / 2 - oy) / CELL
    open_ = set()
    # The pocket round the safe area: an ellipse with a ragged edge.
    for r in range(rows):
        for c in range(cols):
            dx, dy = (c + 0.5 - sx) / 17.5, (r + 0.5 - sy) / 11.5
            if dx * dx + dy * dy < 1 + rng.uniform(-0.12, 0.06):
                open_.add((c, r))
    # Tunnels the balls have dug outwards, so light reaches the edges of the canvas.
    def tunnel(c, r, steps, dc, dr, width):
        for _ in range(steps):
            for i in range(-width, width + 1):
                open_.add((round(c) + (i if abs(dr) > abs(dc) else 0), round(r) + (i if abs(dc) >= abs(dr) else 0)))
            c += dc + rng.uniform(-0.35, 0.35)
            r += dr + rng.uniform(-0.35, 0.35)
    tunnel(sx - 16, sy + 2, 30, -1, 0.15, 1)
    tunnel(sx + 16, sy - 2, 30, 1, -0.1, 1)
    tunnel(sx - 8, sy + 10, 16, -0.6, 1, 1)
    tunnel(sx + 10, sy + 10, 16, 0.7, 1, 1)
    tunnel(sx + 4, sy - 11, 10, 0.3, -1, 0)
    tunnel(sx - 12, sy - 8, 20, -1, -0.6, 0)
    tunnel(sx + 14, sy + 6, 26, 1, 0.45, 0)
    # Side chambers the balls have opened up.
    for (cx, cy, rx, ry) in ((sx + 30, sy - 4, 6, 5), (sx - 31, sy + 6, 5, 4), (sx - 20, sy + 19, 4, 3), (sx + 24, sy + 18, 5, 3)):
        for r in range(rows):
            for c in range(cols):
                dx, dy = (c + 0.5 - cx) / rx, (r + 0.5 - cy) / ry
                if dx * dx + dy * dy < 1 + rng.uniform(-0.2, 0.1):
                    open_.add((c, r))
    open_ = {(c, r) for c, r in open_ if 0 <= c < cols and 0 <= r < rows}
    lit = {(c + i, r + j) for c, r in open_ for i in range(-REVEAL, REVEAL + 1) for j in range(-REVEAL, REVEAL + 1)}
    cells = {}
    for (c, r) in lit:
        if not (0 <= c < cols and 0 <= r < rows):
            continue
        if (c, r) in open_:
            cells[(c, r)] = ("open", None)
            continue
        # Durability: deeper rock (further from open space) is darker, with noise; edges are
        # chipped pale like a face the balls are working on.
        d = min(max(abs(c - a), abs(r - b)) for a, b in open_ if abs(c - a) <= REVEAL and abs(r - b) <= REVEAL)
        shade = min(5, max(0, d + rng.choice([-1, 0, 0, 1, 1, 2])))
        cells[(c, r)] = ("block", shade)
    blocks = [p for p, v in cells.items() if v[0] == "block"]
    for p in rng.sample(blocks, 9):
        cells[p] = ("shard", None)
    # The golden pixel: the 2 x 2 cell boss, half buried in the right-hand chamber's wall.
    gold = (round(sx + 30), round(sy - 4))
    for i in (0, 1):
        for j in (0, 1):
            cells[(gold[0] + i, gold[1] + j)] = ("gold", None)
            open_.discard((gold[0] + i, gold[1] + j))
    return cells, (ox, oy), gold, open_


def draw(seed=7):
    im = Image.new("RGB", (W, H), PAL["black"])
    px = im.load()
    cells, (ox, oy), gold, open_ = cave(seed)
    ladder = PAL["ladder"]
    for (c, r), (kind, shade) in cells.items():
        x0, y0 = ox + c * CELL, oy + r * CELL
        col = {"open": PAL["floor"], "shard": PAL["mint"], "gold": PAL["gold"]}.get(kind)
        if kind == "block":
            col = ladder[shade]
        im.paste(col, (x0, y0, x0 + CELL, y0 + CELL))
        if kind == "shard":  # a shard's facet: one diagonal of the mint cell, as in the game
            for i in range(2, CELL - 2):
                if 0 <= x0 + i < W and 0 <= y0 + i < H:
                    px[x0 + i, y0 + i] = PAL["mintDim"]
    # The gold's glow: stepped rings of gold light/dim/deep round its cell (flat bands, no blur).
    gx, gy = ox + (gold[0] + 1) * CELL, oy + (gold[1] + 1) * CELL  # centre of the 2 x 2 block
    # Halo: Bayer-dithered square bands, densest next to the gold (flat colours, no blur).
    bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
    for y in range(gy - 34, gy + 34):
        for x in range(gx - 34, gx + 34):
            d = max(abs(x - gx + 0.5), abs(y - gy + 0.5))
            if not (0 <= x < W and 0 <= y < H) or d < CELL + 1:
                continue
            level = (34 - d) / 24  # 1 near the gold, 0 at the edge
            if level * 16 > bayer[y % 4][x % 4]:
                px[x, y] = PAL["goldDim"] if d < 20 else PAL["goldDeep"]
    # Four rays, like the golden pixel in the wordmark.
    for d in range(CELL + 3, CELL + 22):
        for sx_, sy_ in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
            for w in (0, 1):
                x, y = gx + sx_ * d + (w if sx_ > 0 else -w) - (1 if sx_ < 0 else 0), gy + sy_ * d - (1 if sy_ < 0 else 0)
                if 0 <= x < W and 0 <= y < H:
                    px[x, y] = PAL["goldLight"] if d < CELL + 12 else PAL["gold"]
    im.paste(PAL["gold"], (gx - CELL, gy - CELL, gx + CELL, gy + CELL))
    im.paste(PAL["goldLight"], (gx - CELL + 3, gy - CELL + 3, gx - CELL + 7, gy - CELL + 7))

    # Text block: wordmark, tagline, promise. All inside the safe area.
    menu = A.render_scene("menu", 475, 334, FRESH)
    logo = A.extract_logo(menu)
    lines = [("FIND THE GOLD.", PAL["gold"], 2), ("NO ADS.  NO IN-APP PURCHASES.", PAL["text"], 1)]
    block_h = logo.height + 10 + 14 + 12 + 7
    cx = round((SAFE[0] + SAFE[2]) / 2)
    y = round((SAFE[1] + SAFE[3]) / 2 - block_h / 2)
    text_boxes = [(cx - logo.width // 2, y, cx + logo.width // 2, y + logo.height)]
    A.paste(im, logo, cx - logo.width // 2, y)
    y += logo.height + 10
    for s, col, k in lines:
        w = A.measure(s, k)
        box = (cx - w // 2 - 3, y - 3, cx + w // 2 + 4, y + 7 * k + 3)
        im.paste(PAL["floor"], box)
        A.centred(im, s, cx, y, col, k)
        text_boxes.append(box)
        y += 7 * k + 12

    # Balls in flight across the open space, each a 3x3 in its own colour with a short trail,
    # kept off the type.
    rng = random.Random(seed + 1)
    colours = list(A.ball_colours().values())
    open_px = [(ox + c * CELL + rng.randrange(CELL), oy + r * CELL + rng.randrange(CELL)) for c, r in open_]
    placed = 0
    for x, y in rng.sample(open_px, len(open_px)):
        if placed >= 70:
            break
        if not (2 <= x < W - 2 and 2 <= y < H - 2):
            continue
        if any(b[0] - 6 <= x <= b[2] + 6 and b[1] - 6 <= y <= b[3] + 6 for b in text_boxes):
            continue
        col = rng.choice(colours)
        dx, dy = rng.choice([(1, 1), (1, -1), (-1, 1), (-1, -1)])
        for t in (3, 5):  # dotted trail behind it
            tx, ty = x - dx * t, y - dy * t
            if 0 <= tx < W and 0 <= ty < H and px[tx, ty] == PAL["floor"]:
                px[tx, ty] = tuple(v // 2 for v in col)
        im.paste(col, (x - 1, y - 1, x + 2, y + 2))
        placed += 1
    return im


def main():
    global FRESH
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-render", action="store_true")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    FRESH = not a.no_render
    im = A.blow(draw(a.seed), K).crop((0, 0, OUT_W, OUT_H))
    out = A.OUT / "appstore-creative-5244x2950.png"
    im.save(out)
    print(f"{out.relative_to(A.ROOT)}  {im.width}x{im.height}  {im.mode}")


FRESH = True
if __name__ == "__main__":
    sys.exit(main())
