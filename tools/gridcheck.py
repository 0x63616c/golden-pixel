#!/usr/bin/env python3
"""Grid check for real screenshots: every NxN block (N = device pixels per art pixel) must be
one solid colour. Finds the canvas offset (the Duo centres a 2850x2004 canvas in 2853x2007, so
it starts 1 px in), ignores the black letterbox margin, and fails if any block is mixed.

    tools/gridcheck.py [--scale N] [--min-solid 1.0] [--corner PX] [--safe-area FILE] shot.png [...]

--safe-area takes the insets the app was given (a <sim>.safe-area.json from `ios/ios.sh
compare`, in points) and skips the blocks under them: that is where the system draws the
Dynamic Island and the home indicator over the game, and those are not on the grid.

Needs Pillow. Bloom must be off (it is by default in the app and in gp-render).
"""
import argparse
import json
import math
import sys

from PIL import Image


def check(path, n, min_solid, corner=0, inset=(0, 0, 0, 0)):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    left, top, right, bottom = inset
    if h > w:  # a landscape app in a portrait framebuffer: its left edge is the image's bottom
        left, top, right, bottom = top, right, bottom, left
    colours = im.getcolors(1 << 16)
    if colours is not None and len(colours) < 8:
        # A blank frame (e.g. a folded Duo's black inner screen) is trivially "on grid".
        print(f"FAIL {path}: only {len(colours)} colours, the screenshot is blank")
        return False
    px = im.load()
    best = None
    for oy in range(n):
        for ox in range(n):
            mixed = total = 0
            for by in range(oy, h - n + 1, n):
                for bx in range(ox, w - n + 1, n):
                    if corner and (bx < corner or bx + n > w - corner) and (by < corner or by + n > h - corner):
                        continue  # the display's rounded-corner mask, not the game
                    if bx < left or by < top or bx + n > w - right or by + n > h - bottom:
                        continue  # under a system inset: the island or the home indicator
                    v = px[bx, by]
                    total += 1
                    for y in range(by, by + n):
                        row_ok = all(px[x, y] == v for x in range(bx, bx + n))
                        if not row_ok:
                            mixed += 1
                            break
            if best is None or mixed < best[0]:
                best = (mixed, total, ox, oy)
            if mixed == 0:
                break
        if best and best[0] == 0:
            break
    mixed, total, ox, oy = best
    solid = 1 - mixed / max(1, total)
    ok = solid >= min_solid
    print(f"{'ok  ' if ok else 'FAIL'} {path}: {w}x{h}, scale {n}, offset ({ox},{oy}), "
          f"{mixed} of {total} blocks mixed ({solid:.4%} solid)")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scale", type=int, help="device pixels per art pixel (default 6, or what the --safe-area file says)")
    ap.add_argument("--min-solid", type=float, default=1.0)
    ap.add_argument("--corner", type=int, default=0,
                    help="skip blocks within this many px of an image corner (screen corner masks)")
    ap.add_argument("--safe-area", help="JSON of the safe-area insets in points; blocks under them are skipped")
    ap.add_argument("--points", type=float, help="device pixels per point (default: the file's \"scale\", else 3)")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    inset = (0, 0, 0, 0)
    if a.safe_area:
        with open(a.safe_area) as f:
            i = json.load(f)
        points = a.points or i.get("scale", 3)
        if points != int(points):
            # e.g. the iPhone 13 mini: iOS resamples the frame onto this panel.
            print(f"skip {a.safe_area}: {points} device pixels per point, so there is no whole-pixel grid to check")
            sys.exit(0)
        inset = tuple(math.ceil(i[k] * points) for k in ("left", "top", "right", "bottom"))
        if a.scale is None:
            a.scale = int(i.get("art", 2 * points))
    results = [check(f, a.scale or 6, a.min_solid, a.corner, inset) for f in a.files]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
