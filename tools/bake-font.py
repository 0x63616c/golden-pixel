#!/usr/bin/env python3
"""Bake Pixel Operator 8 (CC0, by Jayvee Enaguas) into Core/Sources/GoldenPixelCore/PixelFont.swift.

The TTF draws every pixel as a 100-unit square, so sampling each square's centre recovers the
exact bitmap. Usage: tools/bake-font.py path/to/PixelOperator8.ttf  (needs `pip install fonttools`).
Prints the glyph table; paste it over the `table` in PixelFont.swift.
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import RecordingPen

U = 100
font = TTFont(sys.argv[1])
gs, cmap = font.getGlyphSet(), font.getBestCmap()


def contours(name):
    rp = RecordingPen()
    gs[name].draw(rp)
    out, cur = [], []
    for op, args in rp.value:
        if op == "moveTo":
            cur = [args[0]]
        elif op in ("lineTo", "qCurveTo", "curveTo"):
            cur.append(args[-1])
        elif op in ("closePath", "endPath"):
            out.append(cur)
            cur = []
    return out


def inside(cs, x, y):
    w = 0
    for c in cs:
        for i in range(len(c)):
            (x1, y1), (x2, y2) = c[i], c[(i + 1) % len(c)]
            cross = (x - x1) * (y2 - y1) - (x2 - x1) * (y - y1)
            if y1 <= y < y2 and cross > 0:
                w += 1
            elif y2 <= y < y1 and cross < 0:
                w -= 1
    return w != 0


for code in range(32, 127):
    name = cmap.get(code)
    if not name:
        continue
    adv = round(gs[name].width / U)
    cs = contours(name)
    bits = []
    for r in range(7, -1, -1):  # cap top (row 0) down to the descender row
        y = (r - 0.5) * U
        bits.append(sum(1 << (x - 1) for x in range(1, adv) if inside(cs, (x + 0.5) * U, y)))
    ch = {"\\": "\\\\", '"': '\\"'}.get(chr(code), chr(code))
    print(f'        "{ch}": ({adv - 1}, [{", ".join(map(str, bits))}]),')
