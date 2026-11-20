# Short video scripts (TikTok, YouTube Shorts, Instagram Reels)

Three 15 to 30 s scripts. Each is a hook in the first second, one idea, and the App Store
link in the bio or comments.

## Format

- **Frame:** 1080 x 1920, 9:16. The game is landscape (475 x 334 art pixels), so put the game
  in the middle band at a whole scale and fill the rest with black: the game's own
  background, so it blends into the fog. At 1080 wide the game fits at 2x art scale (950 x
  668): 6x capture downscaled by exactly 3. Keep captions in the middle 66% (the apps cover
  the top and bottom). `assets/story-1080x1920.png` is the cover and end card.
- **Footage:** real gameplay only.
  - Simulator recording: `ios/ios.sh shots <dir>` records `menu`, `late` and `gold` for 7 s
    each (inner display, H.264). For other scenes or your own play: `SCENE=<scene> just ios-sim`,
    then `xcrun simctl io booted recordVideo --display=3 --codec=h264 out.mp4` (Ctrl-C stops).
  - Frame-exact renders: `swift run -c release gp-render <scene> build/clip --scale 2 --frames 300`
    writes 10 s of PNG frames at 30 fps (each frame is two 1/60 s game steps), already at 2x.
    Turn them into video with `ffmpeg -framerate 30 -i build/clip/<scene>/%04d.png -vf
    "pad=1080:1920:(ow-iw)/2:(oh-ih)/2:black" -c:v libx264 -pix_fmt yuv420p -crf 12 clip.mp4`.
  - Scale only by whole factors with nearest-neighbour (`-sws_flags neighbor`) so the pixels
    stay sharp, and export at a high bitrate: the apps' compression is hard on pixel art.
- **Sound:** the game's own sound effects (record on device or a Mac), or a track you hold
  the rights to. Avoid trending audio you can't license if you'll reuse the clip in ads.
- **Captions:** burned in, all caps, short, in white or gold. The game's font (Pixel Operator
  8) at a whole scale fits the look; otherwise a plain bold sans.

Staged scenes (`Core/Sources/GoldenPixelCore/Scenes.swift`): `menu`, `start` (one ball in a
pocket of light), `early` (six balls, light spreading), `mid` (a lit cave, 39 balls of three
types), `late` (six ball types, a packed board), `launch` (slingshot aim with the ghost ball),
`zoom` (2x close-up), `zoomout` (0.5x, the whole dig), `sheet` (ball info card), `tree` (skill
tree), `gold` (gold just broken: GOLD! +1 STAR).

---

## 1. "Satisfying" (15 s): for the brick-breaker / satisfying crowd

**Hook:** a full board erupting. **Idea:** one ball becomes hundreds.

| Time | Shot | Caption |
| --- | --- | --- |
| 0.0 to 1.5 | `late`, 1x: six colours of balls ricocheting along a blue wall | (none: let the motion hook) |
| 1.5 to 4.0 | Hard cut to `start`: the lone white ball in a pocket of light | ONE BALL... |
| 4.0 to 7.0 | Live play: hold an open spot, pull back, let go; the ball flies. Use the `launch` scene for a clean shot of the aim dots | HOLD. PULL. LET GO. |
| 7.0 to 10.0 | `early` then `mid`: the pocket widening, blocks paling and breaking | EVERY BREAK BUYS MORE |
| 10.0 to 13.5 | `late` again: 186 balls of six types | ...BECOMES 186 |
| 13.5 to 15.0 | `story-1080x1920.png` end card | GOLDEN PIXEL. FREE, NO ADS. |

**Text post:** `It started with one ball. #idlegame #pixelart`

---

## 2. "The fog" (20 s): for idle and strategy players

**Hook:** a black screen with one faint glow. **Idea:** you can only see what you've dug.

| Time | Shot | Caption |
| --- | --- | --- |
| 0.0 to 2.0 | `start` at 1x: mostly black, the pocket of light, two sensed shards breathing in dim mint | YOU CAN ONLY SEE 3 CELLS INTO THE DARK |
| 2.0 to 6.0 | `early` (recorded live): blocks pale, break, and the next cells dither in from black | EVERY BREAK PUSHES THE LIGHT FURTHER |
| 6.0 to 9.0 | `zoomout` (0.5x): the whole lit cave in the fog | MINT = SHARDS. THEY BUY SKILLS |
| 9.0 to 13.0 | `tree`: the skill tree, Ghost ball selected, BUY 4 shards | 7 BALLS. LANTERN. RADAR. SONAR. |
| 13.0 to 17.0 | `late`: packed board, dig heading off-screen | SOMEWHERE OUT THERE... |
| 17.0 to 20.0 | `gold`: GOLD! +1 STAR, then the end card | ...ONE PIXEL IS GOLD |

**Text post:** `An idle brick breaker with fog of war. No ads, no IAP. #incrementalgame #iosgames`

---

## 3. "One grid" (25 s): for pixel-art and dev audiences

**Hook:** an extreme close-up that's still razor sharp. **Idea:** the whole game is one canvas.

| Time | Shot | Caption |
| --- | --- | --- |
| 0.0 to 2.5 | `zoom` (2x board): balls as clean 5 x 5 circles with dotted trails | NO BLUR. AT ANY ZOOM. |
| 2.5 to 6.0 | `mid` at 1x, then a pinch out to 0.5x (record live, or cut to `zoomout`) | EVERYTHING IS ONE 475 x 334 CANVAS |
| 6.0 to 10.0 | Blocks breaking, one shade paler per hit | DURABILITY = LIGHTNESS |
| 10.0 to 14.0 | `sheet`: the Fast ball info card, all flat colour | NO SHADOWS. NO GRADIENTS. NO BEVELS. |
| 14.0 to 18.0 | `menu`: the wordmark with the golden pixel twinkling as the i's dot | 1 ART PIXEL = 6 x 6 SCREEN PIXELS |
| 18.0 to 22.0 | `late`: the full board in motion | A TEST FAILS THE BUILD IF ONE PIXEL IS OFF |
| 22.0 to 25.0 | End card | GOLDEN PIXEL. FREE ON IPHONE. |

**Text post:** `Every frame is drawn into one pixel grid. #pixelart #gamedev #indiedev`

---

## Afterwards

Repost the best-performing clip as an X/Bluesky video and a YouTube Short. Keep a list of what
worked (hook, length, sound) and make one new clip a week for the first month from player
requests: a giant late-game board, a Ghost-heavy build, a gold break at 4x zoom.
