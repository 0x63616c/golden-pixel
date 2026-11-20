# Golden Pixel: press kit

Placeholders in `[BRACKETS]` need filling in before this goes out.

## Fact sheet

| | |
| --- | --- |
| **Title** | Golden Pixel (App Store: "Golden Pixel: Idle Breaker") |
| **Developer** | [DEVELOPER NAME] |
| **Based in** | [CITY, COUNTRY] |
| **Release date** | TBD |
| **Platform** | iPhone (iOS 26 or later). Made for the iPhone Duo's inner screen; plays on every iPhone, landscape |
| **Price** | Free. No ads, no in-app purchases |
| **Data** | Collects no data. No accounts, analytics or tracking; progress is saved on the device |
| **Genre** | Idle / incremental brick breaker |
| **Age rating** | Expected 4+ (no objectionable content) |
| **Languages** | English |
| **Website** | [WEBSITE] |
| **App Store** | [APP STORE LINK] |
| **Press contact** | [PRESS EMAIL] |
| **Social** | [X HANDLE] · [BLUESKY HANDLE] · [TIKTOK HANDLE] |
| **Trailer** | [YOUTUBE LINK] |

## Description

**Short (one sentence).** Golden Pixel is a free idle brick breaker for iPhone where your
balls dig through a dark, pixel-perfect map toward one hidden golden pixel.

**Medium (about 50 words).** Every level starts as a small pocket of light in a buried map.
Flick balls into the dark like a slingshot and they bounce forever, breaking blue pixels and
pushing the light outward. Spend coins on more balls and mint shards on a skill tree, then
crack the golden pixel. Free, no ads, no in-app purchases.

**Long.** Somewhere in the dark, one golden pixel is pulsing. Golden Pixel is an idle brick
breaker drawn on a single pixel grid, and each level is a dig toward it.

You start with a pocket of open space, a few coins and nothing else. Hold an open spot, pull
back like a slingshot and let go: the ball flies the other way and never stops bouncing. Every
block it breaks pays coins for more balls, and every break pushes the light three cells further
into the fog. Blocks are one shade of blue, and the shade is how many hits they have left:
deep blue is tough, pale blue is one hit from breaking.

Glowing mint shards hide in the rock. They buy a skill tree of seven ball types (Basic, Fast,
Heavy, Volt, Bomb, Sniper and Ghost), each with its own upgrades and two specialisations, plus
the tools for finding the gold: Lantern widens your light, Radar boxes in the gold, Sonar
pings through the rock.

The golden pixel is the level's boss, hundreds of hits that grow a level at a time. Break it
and it becomes a star for good: more damage and more coins on every level after.

Golden Pixel is free, with no ads, no in-app purchases, no accounts and no tracking.

## Features

- **Slingshot launch.** Hold an open spot, pull back, let go. A plain tap reuses the last aim.
- **Idle at heart.** Balls bounce forever; the board keeps earning while you're away.
- **Fog of war you dig through.** You see three cells past open space; each break reveals more,
  dithering the cells in from black. The gold glows faintly through the dark.
- **Durability you can count.** One blue hue; each hit makes a block one shade paler.
- **Seven ball types:** Basic (reliable bouncer), Fast (quick light hits), Heavy (pierces what
  it breaks), Volt (chains lightning to nearby pixels), Bomb (explodes on impact), Sniper (aims
  after each bounce), Ghost (phases through pixels).
- **A skill tree paid in shards**, with general skills (damage, speed, crits, coins, idle
  earnings) and a branch for every ball.
- **Boss gold, permanent stars.** 400 hits on level 1, 1.5x tougher each level; every gold is a
  permanent +5% damage and +10% coins.
- **Big levels.** 93 to 107 cells across, about 15 to 25 minutes each; seven named levels,
  then the deep levels keep going.
- **Pinch zoom** from 0.5x to 4x, every step pixel-exact.
- **Made for iPhone Duo's inner screen** at its native scale. Other iPhones letterbox.
- **Free. No ads. No in-app purchases. No tracking.**

## Story: how it's made (the angle for dev and pixel-art press)

Golden Pixel began as a web game. The native version kept one rule from it, that you only see
three pixels in from open space, and turned it into the whole game: a fog you dig through.

It's written in Swift, and the entire game (rules, levels, fog, economy, simulation, UI
layout, camera and a CPU rasteriser) is one pure Swift package with no Apple UI frameworks. A
test enforces that, so the whole game builds and tests on Linux. The iOS app is a thin shell
that presents pixels, forwards touches, saves and plays sounds.

**One grid, no exceptions.** Every frame is drawn by the CPU into one 475 x 334 art-pixel
canvas: the board, the panel, text, icons, lightning, sparks. On the iPhone Duo's inner screen
each art pixel is exactly 6 x 6 device pixels (2853 / 6 = 475). The canvas goes to the GPU as
one texture and is shown at a whole-number scale with exact texel reads. There's no
anti-aliasing, no sub-pixel position, no gradient (an ordered Bayer dither does that job), and
no view or node per pixel.

**Flat by rule.** One colour per surface: no highlights, shadows or bevels. Blocks are one
blue hue whose lightness is their durability. Gold is used only for the gold and coins, mint
only for shards.

**The grid is tested.** A unit test renders every staged scene, scales it up and checks that
every N x N block is a single colour. CI renders every scene with the game's own command-line
renderer and runs the same grid check on those and on iPhone Duo simulator screenshots. A
layout test keeps every button out of the Duo's heavily rounded corners and at least 44 pt
square.

**Even the icon and the type are on the grid.** The app icon is drawn by the game's own
renderer on a 64 x 64 canvas, scaled 16x. The type is Pixel Operator 8 (CC0, by Jayvee
Enaguas), baked into a bitmap table by sampling the font's own 100-unit pixel grid.

**Balanced by simulation.** A headless simulator plays every level to check each one takes 15
to 25 minutes and that there's no long stretch with nothing to buy.

Quotable: "If a pixel doesn't land on the grid, the build fails."

## Images and video

All in `marketing/assets/` (regenerate with `marketing/tools/make-assets.py`). Every image is a
real render of the game, enlarged by whole factors with nearest-neighbour only. Please don't
resample by non-whole factors or smooth them; if you need another size, ask, or crop.

- `screens/*-1900x1336.png`: in-game screenshots (menu, first ball, mid-game, late game,
  zoomed in, ball info, skill tree, gold broken).
- `header-1920x1080.png`, `og-1200x630.png`, `square-1080x1080.png`, `story-1080x1920.png`,
  `tree-1080x1080.png`: key art.
- Trailer: [YOUTUBE LINK] (storyboard in `marketing/trailer.md`).

## Logo and icon

- `assets/logo-x4.png` and `logo-x8.png`: the GOLDEN PiXEL wordmark on transparent, with its
  2-px black keyline. GOLDEN is gold `#ffd23f`, PiXEL is white, and the dot of the lowercase i
  is the golden pixel itself.
- `assets/icon-1024.png`: the app icon, 1024 x 1024 with stepped corners on transparent.

Usage:

- Keep the keyline; it's what makes the wordmark read on any background. Best on black or the
  game's dark greys.
- Scale by whole numbers only (x1, x2, x4...) with nearest-neighbour. Never blur, rotate,
  stretch or recolour it, and don't add glows, shadows or outlines.
- Leave clear space around the wordmark of at least the height of the gold dot.
- The lowercase "i" in PiXEL is intentional; write the name as "Golden Pixel" in text.
- The icon and wordmark are being finalised; take the current files from `assets/` (they're
  regenerated from the game).

## Credits

- Design, code and art: [DEVELOPER NAME]
- Font: Pixel Operator 8 by Jayvee Enaguas (HarvettFox96), CC0 1.0
- Sound: [CREDIT, if any]

## Contact

[PRESS EMAIL] · [WEBSITE]. Promo codes and TestFlight access on request.
