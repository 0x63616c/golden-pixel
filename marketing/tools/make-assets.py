#!/usr/bin/env python3
"""Compose Golden Pixel's marketing images from real game renders.

Every image is built on one art-pixel grid and blown up with nearest-neighbour only, so the
pixels stay as crisp as in the game. The source pictures are renders of the game itself:

  - board backdrops: `gp-render <scene> --scale 1 --size WxH` (the board, without the panel)
  - the wordmark:    lifted from the `menu` scene (letters, golden pixel and 2-px keyline)
  - the app icon:    `gp-render icon`, rendered fresh on every run
  - type:            Pixel Operator 8, read from Core/Sources/GoldenPixelCore/PixelFont.swift

Nothing is cached between runs (renders go to build/marketing-cache), so once the logo, icon
or palette changes in the game, re-running this updates every asset.

Usage (from anywhere; needs Swift for the renders and Pillow):
  python3 marketing/tools/make-assets.py               # render, then compose into marketing/assets
  python3 marketing/tools/make-assets.py --no-render   # reuse the last renders (fast iteration)
"""
import argparse
import re
import subprocess
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / "build" / "marketing-cache"
OUT = ROOT / "marketing" / "assets"
CORE = ROOT / "Core" / "Sources" / "GoldenPixelCore"
PANEL_W = 150  # the right-hand panel in every landscape render; we crop it off board backdrops


def rgb(h):
    return ((h >> 16) & 255, (h >> 8) & 255, h & 255)


# Palette.swift, read at run time so a palette change in the game follows through.
def load_palette():
    src = (CORE / "Palette.swift").read_text()
    pal = {name: rgb(int(h, 16)) for name, h in re.findall(r"static let (\w+) = rgb\(0x([0-9a-fA-F]{6})\)", src)}
    m = re.search(r"static let ladder: \[Pixel\] = \[([^\]]+)\]", src)
    pal["ladder"] = [rgb(int(h, 16)) for h in re.findall(r"0x([0-9a-fA-F]{6})", m.group(1))] if m else []
    return pal


PAL = load_palette()


# ---------------------------------------------------------------------------------------------
# Renders


def run(cmd):
    print("  $", " ".join(str(c) for c in cmd))
    subprocess.run(cmd, cwd=ROOT, check=True, stdout=subprocess.DEVNULL)


RENDERED = set()  # scenes rendered this run


def render_scene(scene, w, h, fresh):
    out = CACHE / f"{scene}-{w}x{h}"
    png = out / f"{scene}.png"
    if (fresh and out not in RENDERED) or not png.exists():
        RENDERED.add(out)
        run(["swift", "run", "-c", "release", "gp-render", scene, out, "--scale", "1", "--size", f"{w}x{h}"])
    return Image.open(png).convert("RGB")


def render_icon(fresh):
    """The app icon at one pixel per art pixel (gp-render writes it at Icon.scale)."""
    png = CACHE / "icon" / "icon.png"
    if fresh or not png.exists():
        run(["swift", "run", "-c", "release", "gp-render", "icon", CACHE / "icon"])
    im = Image.open(png).convert("RGB")
    src = (CORE / "Icon.swift").read_text()
    m = re.search(r"static let size = (\d+)", src)
    size = int(m.group(1)) if m else 64
    k = im.width // size
    # Sample each k x k block's centre: exact, since the icon is drawn on the art grid.
    small = Image.new("RGB", (size, size))
    src_px, dst_px = im.load(), small.load()
    for y in range(size):
        for x in range(size):
            dst_px[x, y] = src_px[x * k + k // 2, y * k + k // 2]
    return small


def board(im):
    """The board part of a landscape render (everything left of the panel)."""
    return im.crop((0, 0, im.width - PANEL_W, im.height))


def content_box(im):
    """Bounding box of the lit area in a board render: everything that isn't pure black (the
    fog), ignoring small specks such as shards sensed through the dark."""
    mask = im.point(lambda v: 255 if v > 0 else 0).convert("L").point(lambda v: 255 if v else 0)
    return mask.filter(ImageFilter.MinFilter(9)).filter(ImageFilter.MaxFilter(9)).getbbox()


# ---------------------------------------------------------------------------------------------
# The wordmark, lifted from the main menu


def extract_logo(menu):
    """Returns the GOLDEN PiXEL wordmark as RGBA at art scale: letters, the golden pixel and its
    rays as drawn in the menu, plus the 2-px black keyline that hugs the letters; transparent
    elsewhere. Found by colour: the letters are exactly white or gold, the rays gold light/dim;
    the hero button (the biggest gold shape) and everything below it is left out."""
    W, H = menu.size
    px = menu.load()
    letter = {PAL["white"], PAL["gold"]}
    ray = {PAL["goldLight"], PAL["goldDim"]}
    ink = letter | ray
    seen = [[False] * W for _ in range(H)]
    comps = []
    for y in range(H):
        for x in range(W):
            if seen[y][x] or px[x, y] not in ink:
                continue
            q, pts = deque([(x, y)]), []
            seen[y][x] = True
            while q:
                cx, cy = q.popleft()
                pts.append((cx, cy))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < W and 0 <= ny < H and not seen[ny][nx] and px[nx, ny] in ink:
                            seen[ny][nx] = True
                            q.append((nx, ny))
            comps.append(pts)
    button = max(comps, key=len)
    top = min(p[1] for p in button)
    keep = [c for c in comps if len(c) >= 40 and max(p[1] for p in c) < top]
    pts = [p for c in keep for p in c]
    x0, y0 = min(p[0] for p in pts) - 2, min(p[1] for p in pts) - 2
    x1, y1 = max(p[0] for p in pts) + 3, max(p[1] for p in pts) + 3
    w, h = x1 - x0, y1 - y0
    letters = Image.new("L", (w, h), 0)
    lp = letters.load()
    for x, y in pts:
        if px[x, y] in letter:
            lp[x - x0, y - y0] = 255
    keyline = letters.filter(ImageFilter.MaxFilter(5))  # Chebyshev radius 2, like the game
    logo = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    lo = logo.load()
    kp = keyline.load()
    for y in range(h):
        for x in range(w):
            if kp[x, y]:
                lo[x, y] = (0, 0, 0, 255)
    for x, y in pts:
        lo[x - x0, y - y0] = px[x, y] + (255,)
    return logo


# ---------------------------------------------------------------------------------------------
# Type: Pixel Operator 8 from the game's own baked table


def load_font():
    src = (CORE / "PixelFont.swift").read_text()
    table = {}
    for ch, adv, rows in re.findall(r'^\s*"((?:\\.|[^"\\])+)": \((\d+), \[([\d, ]+)\]\),', src, re.M):
        ch = {'\\"': '"', "\\\\": "\\"}.get(ch, ch)
        table[ch] = (int(adv), [int(r) for r in rows.split(",")])
    return table


FONT = load_font()


def measure(s, k=1):
    return max(0, (sum(FONT.get(c, FONT["?"])[0] for c in s) - 1) * k)


def text(im, s, x, y, colour, k=1):
    """Draws s with its cap top at (x, y), each font pixel k x k art pixels."""
    for c in s:
        adv, rows = FONT.get(c, FONT["?"])
        for r, bits in enumerate(rows):
            for b in range(16):
                if bits >> b & 1:
                    im.paste(colour, (x + b * k, y + r * k, x + (b + 1) * k, y + (r + 1) * k))
        x += adv * k
    return x


def centred(im, s, cx, y, colour, k=1):
    text(im, s, cx - measure(s, k) // 2, y, colour, k)


# ---------------------------------------------------------------------------------------------
# Pieces


def blow(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def paste(dst, src, x, y):
    dst.paste(src, (x, y), src if src.mode == "RGBA" else None)


def badge(icon, k, pad=0):
    """The app icon, k x per icon pixel, cut to an iOS-ish squircle in whole pixels (corner
    radius about 22% of the side, stepped), on transparent."""
    im = blow(icon, k).convert("RGBA")
    n = im.width
    r = round(n * 0.225)
    mask = Image.new("L", (n, n), 255)
    mp = mask.load()
    for y in range(n):
        for x in range(n):
            dx = max(r - x - 0.5, x + 0.5 - (n - r), 0)
            dy = max(r - y - 0.5, y + 0.5 - (n - r), 0)
            if dx * dx + dy * dy > r * r:
                mp[x, y] = 0
    im.putalpha(mask)
    return im




def frame(src, border=PAL["border"], t=2):
    """A screenshot in a flat border, no shadow."""
    out = Image.new("RGB", (src.width + 2 * t, src.height + 2 * t), border)
    out.paste(src, (t, t))
    return out


# ---------------------------------------------------------------------------------------------
# Cards. Each is composed at art scale and blown up by a whole factor, so every element lands
# on the card's own pixel grid. Type is 1x (7-px caps) or 2x (14-px caps) of that grid.


def place_cave(im, cave, x, y, clear_above=False):
    """Pastes the cave render so the lit area's top-left lands at (x, y) on the card. With
    clear_above, the fog above the lit area is cleared of its hints (sensed shards, the gold's
    faint pulse) so they don't sit among the type."""
    bx = content_box(cave)
    im.paste(cave.crop((bx[0] - x, bx[1] - y, bx[0] - x + im.width, bx[1] - y + im.height)), (0, 0))
    if clear_above:
        im.paste(PAL["black"], (0, 0, im.width, y))
    return bx[2] - bx[0], bx[3] - bx[1]


def wordmark_block(im, logo, cx, y, lines, gap=12):
    """The logo centred on cx with its top at y, then lines of (text, colour, scale) under it.
    Returns the y below the block."""
    paste(im, logo, cx - logo.width // 2, y)
    y += logo.height + gap
    for s, colour, k in lines:
        centred(im, s, cx, y, colour, k)
        y += 13 * k
    return y


TAGS = [("BREAK THE BLUE.", PAL["text"], 2), ("FIND THE GOLD.", PAL["gold"], 2)]


def og_card(logo, icon, cave):
    """1200 x 630 (Open Graph, X/Bluesky link card, Product Hunt gallery): 600 x 315 art at
    2x. The lit cave on the right, the wordmark in the fog on the left."""
    W, H, k = 600, 315, 2
    im = Image.new("RGB", (W, H), PAL["black"])
    bx = content_box(cave)
    place_cave(im, cave, 272, (H - (bx[3] - bx[1])) // 2)
    wordmark_block(im, logo, 136, 56, TAGS)
    centred(im, "FREE ON IPHONE  -  NO ADS  -  NO IAP", 136, H - 26, PAL["muted"], 1)
    return blow(im, k)


def header(logo, icon, cave):
    """1920 x 1080 (YouTube/X/itch header, press hero, wallpaper): 640 x 360 art at 3x. The
    left block (wordmark, tagline, two small lines) is centred vertically."""
    W, H, k = 640, 360, 3
    im = Image.new("RGB", (W, H), PAL["black"])
    bx = content_box(cave)
    place_cave(im, cave, 290, (H - (bx[3] - bx[1])) // 2)
    block = logo.height + 12 + 2 * 26 + 18 + 12 + 7
    y = wordmark_block(im, logo, 150, (H - block) // 2, TAGS)
    centred(im, "AN IDLE PIXEL BREAKER FOR IPHONE", 150, y + 18, PAL["text2"], 1)
    centred(im, "FREE  -  NO ADS  -  NO IN-APP PURCHASES", 150, y + 30, PAL["muted"], 1)
    return blow(im, k)


def square(logo, icon, cave):
    """1080 x 1080 (Instagram, X/Bluesky/Reddit image post): 360 x 360 art at 3x. Wordmark in
    the dark above the lit cave, which runs off the bottom edge."""
    W, H, k = 360, 360, 3
    im = Image.new("RGB", (W, H), PAL["black"])
    bx = content_box(cave)
    place_cave(im, cave, (W - (bx[2] - bx[0])) // 2, 180, clear_above=True)
    wordmark_block(im, logo, W // 2, 26, [("FIND THE GOLD.", PAL["gold"], 2)])
    return blow(im, k)


def story(logo, icon, cave):
    """1080 x 1920 (Instagram/TikTok/Shorts cover, Stories): 360 x 640 art at 3x. All type
    sits between about 14% and 80% of the height: the apps cover the top and bottom with
    their own chrome. The cave runs off the bottom."""
    W, H, k = 360, 640, 3
    im = Image.new("RGB", (W, H), PAL["black"])
    bx = content_box(cave)
    place_cave(im, cave, (W - (bx[2] - bx[0])) // 2, 330, clear_above=True)
    y = wordmark_block(im, logo, W // 2, 96, TAGS)
    centred(im, "FREE ON IPHONE", W // 2, y + 14, PAL["text2"], 1)
    centred(im, "NO ADS  -  NO IN-APP PURCHASES", W // 2, y + 26, PAL["muted"], 1)
    return blow(im, k)


def ball_colours():
    """Each ball's flat colour, from BallKind.color in Config.swift."""
    src = (CORE / "Config.swift").read_text()
    block = src[src.index("public var color: Pixel"):]
    block = block[: block.index("public var shade")]
    return {k: rgb(int(h, 16)) for k, h in re.findall(r"case \.(\w+): return rgb\(0x([0-9a-fA-F]{6})\)", block)}


def roster_card(logo, icon, tree):
    """1080 x 1080 feature card: the skill tree that unlocks the seven balls, and the balls'
    names in their own colours. 540 x 540 art at 2x, so the tree fits at one to one."""
    W, H, k = 540, 540, 2
    im = Image.new("RGB", (W, H), PAL["black"])
    # The tree's nodes and info bar, without its header row (shard count, close button).
    top = 36
    tb = content_box(tree.crop((0, top, tree.width, tree.height)))
    t = frame(tree.crop((max(0, tb[0] - 8), top + tb[1] - 8, min(tree.width, tb[2] + 8), top + tb[3] + 4)))
    block = 21 + 19 + 7 + 17 + t.height + 22 + 14  # headline, subline, tree, ball names
    y0 = (H - block) // 2
    centred(im, "7 BALLS. 1 SKILL TREE.", W // 2, y0, PAL["text"], 3)
    centred(im, "SHARDS BUY UPGRADES. EVERY GOLD IS A STAR.", W // 2, y0 + 40, PAL["mint"], 1)
    ty = y0 + 64
    paste(im, t, (W - t.width) // 2, ty)
    col = ball_colours()
    names = [("BASIC", "basic"), ("FAST", "fast"), ("HEAVY", "heavy"), ("VOLT", "lightning"),
             ("BOMB", "bomb"), ("SNIPER", "sniper"), ("GHOST", "ghost")]
    gap = measure("  ", 2)
    total = sum(measure(n, 2) for n, _ in names) + gap * (len(names) - 1)
    x, y = (W - total) // 2, ty + t.height + 22
    for n, kind in names:
        text(im, n, x, y, col.get(kind, PAL["text"]), 2)
        x += measure(n, 2) + gap
    return blow(im, k)


def icon_tile(icon):
    """1024 x 1024 icon with stepped rounded corners on transparent, for press pages."""
    return badge(icon, 1024 // icon.width)


PRESS_SCENES = ["menu", "start", "mid", "late", "zoom", "sheet", "tree", "gold"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--no-render", action="store_true", help="reuse renders in build/marketing-cache")
    ap.add_argument("--out", type=Path, default=OUT)
    a = ap.parse_args()
    fresh = not a.no_render
    a.out.mkdir(parents=True, exist_ok=True)

    print("Rendering the game")
    menu = render_scene("menu", 475, 334, fresh)
    icon = render_icon(fresh)
    # One big landscape render (wider than tall keeps the panel on the right): the whole lit
    # cave of the mid-game scene with plenty of fog around it.
    cave = board(render_scene("mid", 1150, 800, fresh))
    tree = render_scene("tree", 475, 334, fresh)

    logo = extract_logo(menu)
    out = {
        "og-1200x630.png": og_card(logo, icon, cave),
        "header-1920x1080.png": header(logo, icon, cave),
        "square-1080x1080.png": square(logo, icon, cave),
        "story-1080x1920.png": story(logo, icon, cave),
        "tree-1080x1080.png": roster_card(logo, icon, tree),
        "icon-1024.png": icon_tile(icon),
        "logo-x4.png": blow(logo, 4),
        "logo-x8.png": blow(logo, 8),
    }
    # Press screenshots: real staged scenes at 4x (1900 x 1336), the Duo canvas as it is.
    for scene in PRESS_SCENES:
        out[f"screens/{scene}-1900x1336.png"] = blow(render_scene(scene, 475, 334, fresh), 4)

    print("Writing", a.out.relative_to(ROOT) if a.out.is_relative_to(ROOT) else a.out)
    (a.out / "screens").mkdir(exist_ok=True)
    for name, im in out.items():
        im.save(a.out / name)
        print(f"  {name}  {im.width}x{im.height}")


if __name__ == "__main__":
    sys.exit(main())
