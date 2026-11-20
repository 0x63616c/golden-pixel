#!/usr/bin/env python3
"""Side-by-side sheets of the same scene on several simulators.

    tools/compare.py <dir> [sim ...]

Reads <dir>/<sim>/<scene>.png (what `ios/ios.sh compare` writes) and writes one sheet per
scene to <dir>/sheets/<scene>.png, plus <dir>/sheets/all.png with every scene. Each screenshot
is turned landscape and shown at 1 px per point (a third of its pixels, exact texel picks, no
filtering), so the phones keep their relative sizes.

Each label gives the screenshot size, the art scale found in the image (device pixels per art
pixel) and the art canvas that gives. With <dir>/<sim>.mask.png (the screen's outline as
alpha) the rounded corners are cut as on glass, and with <dir>/<sim>.safe-area.json (insets in
points) the safe area is outlined in pink: outside it sit the island and the home indicator.
Needs Pillow.
"""
import argparse
import json
import os
import sys
from functools import reduce
from math import gcd

from PIL import Image, ImageDraw, ImageFont

NAMES = {"duo": "iPhone Duo (inner)", "iphone": "iPhone 18 Pro", "max": "iPhone 18 Pro Max",
         "se": "iPhone SE", "mini": "iPhone 13 mini"}
# Screenshots come out in the panel's native portrait; the app runs landscape.
TURN = Image.Transpose.ROTATE_90
POINT = 3  # device pixels per point, unless the safe-area file says otherwise ("scale")
PAD, LABEL = 12, 22
BG, INK, DIM, SAFE = (24, 24, 28), (235, 235, 240), (150, 150, 160), (255, 60, 170)


def art_scale(im):
    """Device pixels per art pixel: the spacing every colour change in the image shares."""
    w, h = im.size
    px = im.load()
    steps = []
    for y in range(h // 3, 2 * h // 3, max(1, h // 60)):
        edges = [x for x in range(w // 6 + 1, 5 * w // 6) if px[x, y] != px[x - 1, y]]
        steps += [b - a for a, b in zip(edges, edges[1:])]
    return reduce(gcd, steps, 0) or 1


def load(path):
    im = Image.open(path).convert("RGB")
    if im.height > im.width:
        im = im.transpose(TURN)
    return im


def glass(root, sim):
    """The screen's outline (an L image, 0 = off the glass) and its safe-area insets in points."""
    mask = insets = None
    path = os.path.join(root, sim + ".mask.png")
    if os.path.exists(path):
        im = Image.open(path)
        if im.mode == "RGBA":
            mask = im.getchannel("A")
            if mask.height > mask.width:
                mask = mask.transpose(TURN)
    path = os.path.join(root, sim + ".safe-area.json")
    if os.path.exists(path):
        with open(path) as f:
            insets = json.load(f)
    return mask, insets


def tile(sim, path, font, mask, insets):
    im = load(path)
    n = art_scale(im)
    w, h = im.size
    if mask is not None and mask.size == im.size:
        im = Image.composite(im, Image.new("RGB", im.size, BG), mask)
    point = round(insets.get("scale", POINT)) if insets else POINT
    small = im.resize((w // point, h // point), Image.Resampling.NEAREST)
    text = (f"{NAMES.get(sim, sim)}   {w} x {h} px   {w // point} x {h // point} pt   "
            f"art scale {n}   canvas {w // n} x {h // n}")
    if insets:
        l, t, r, b = (round(insets[k]) for k in ("left", "top", "right", "bottom"))
        text += f"   safe area L{l} T{t} R{r} B{b} pt"
        if l or t or r or b:
            ImageDraw.Draw(small).rectangle((l, t, small.width - 1 - r, small.height - 1 - b), outline=SAFE)
    out = Image.new("RGB", (max(small.width, int(font.getlength(text)) + 1), small.height + LABEL), BG)
    ImageDraw.Draw(out).text((0, 4), text, fill=INK, font=font)
    out.paste(small, (0, LABEL))
    return out


def stack(tiles, title, font):
    width = max(t.width for t in tiles) + 2 * PAD
    height = LABEL + sum(t.height + PAD for t in tiles) + PAD
    sheet = Image.new("RGB", (width, height), BG)
    ImageDraw.Draw(sheet).text((PAD, PAD - 4), title, fill=DIM, font=font)
    y = LABEL + PAD
    for t in tiles:
        sheet.paste(t, (PAD, y))
        y += t.height + PAD
    return sheet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("sims", nargs="*")
    args = ap.parse_args()
    sims = args.sims or sorted(d for d in os.listdir(args.dir)
                               if d != "sheets" and os.path.isdir(os.path.join(args.dir, d)))
    extras = {sim: glass(args.dir, sim) for sim in sims}
    scenes = []
    for sim in sims:
        for f in sorted(os.listdir(os.path.join(args.dir, sim))):
            if f.endswith(".png") and f[:-4] not in scenes:
                scenes.append(f[:-4])
    if not scenes:
        sys.exit(f"no screenshots under {args.dir}")
    try:
        font = ImageFont.load_default(size=13)
    except TypeError:
        font = ImageFont.load_default()
    out = os.path.join(args.dir, "sheets")
    os.makedirs(out, exist_ok=True)
    sheets = []
    for scene in scenes:
        tiles = [tile(sim, os.path.join(args.dir, sim, scene + ".png"), font, *extras[sim])
                 for sim in sims if os.path.exists(os.path.join(args.dir, sim, scene + ".png"))]
        sheet = stack(tiles, scene, font)
        sheet.save(os.path.join(out, scene + ".png"))
        sheets.append(sheet)
    # Every scene in one image: a row of the per-scene sheets.
    everything = Image.new("RGB", (sum(s.width for s in sheets), max(s.height for s in sheets)), BG)
    x = 0
    for s in sheets:
        everything.paste(s, (x, 0))
        x += s.width
    everything.save(os.path.join(out, "all.png"))
    print(f"{len(scenes)} scenes x {len(sims)} simulators -> {os.path.abspath(out)}")


if __name__ == "__main__":
    main()
