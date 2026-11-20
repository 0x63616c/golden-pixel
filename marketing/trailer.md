# Trailer and App Store app preview

One 25 s cut that works as the App Store app preview (muted, captions carry it) and, with an
end card and music, as the YouTube / social trailer.

## App Store app preview rules (checked November 2026)

From Apple's [app preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)
and [app preview guidelines](https://developer.apple.com/app-store/app-previews/):

| | |
| --- | --- |
| Length | **15 to 30 s** |
| Count | Up to 3 per device size and language |
| Resolution | Large iPhones, **including iPhone Duo**: **1920 x 886** landscape (886 x 1920 portrait). Smaller sizes fall back to scaled versions of the larger one |
| Format | .mov, .m4v or .mp4, H.264 (10 to 12 Mbps, progressive, up to High Profile 4.0), or ProRes 422 HQ (.mov) |
| Frame rate | 30 fps max |
| Audio | Stereo AAC 256 kbps, 44.1 or 48 kHz; all tracks enabled |
| File size | 500 MB max |
| Poster frame | 5 s in by default; you can pick the frame. Changing it later needs a new app version |
| Content | Only footage from inside the app, captured on device or simulator. **No hands, fingers or devices on screen.** Graphic touch hotspots are allowed to show interaction |
| Text | Overlays allowed and useful (previews autoplay muted); leave them up long enough to read |
| Avoid | Prices (pricing varies by region, so don't say "free" in the preview), dates or seasonal references, transitions that imply features, more cutscene than gameplay, music you don't have rights to in every territory |
| Disclosure | Only needed for IAP, subscriptions or login; Golden Pixel has none |

Previews appear before screenshots unless their aspect ratio differs from the screenshots, in
which case they move to "A Closer Look".

## Fitting the pixel grid into 1920 x 886

The game canvas is 475 x 334 art pixels (1.42:1); the preview frame is 2.17:1. The largest
whole scale that fits 886 px high is **2x: 950 x 668**, centred with black around it. Black is
the game's own fog colour, so the frame blends into the dark rather than looking letterboxed.
Never scale by a non-whole factor; the pixels would blur.

The simulator records the Duo's inner display at 6 device px per art px, so the capture
downscales by exactly 3. (For the YouTube trailer at 1920 x 1080, use 3x: 1425 x 1002, a ÷2
downscale.)

## Capturing the footage

**Simulator recordings (preferred for the App Store: real captures of the app):**

```sh
ios/ios.sh shots build/trailer          # screenshots of every staged scene + 7 s recordings
                                        # of menu, late and gold (inner display, H.264)
SCENE=early just ios-sim                # any other staged scene, then record it:
xcrun simctl io booted recordVideo --display=3 --codec=h264 --force build/trailer/early.mp4
# Ctrl-C to stop. Display 3 is the Duo's inner screen (see ios/ios.sh).
```

For live play (the slingshot, a pinch zoom), launch `just ios-sim` and play with the mouse
while recording; the cursor isn't recorded.

**Frame-exact renders (good for social and YouTube; the same frame buffer the app shows,
from the staged scenes' real simulation):**

```sh
swift run -c release gp-render late build/trailer/frames --scale 2 --frames 240   # 8 s at 30 fps, 950 x 668
```

**Assembling (ffmpeg):** crop the recording to the 2850 x 2004 canvas (run
`tools/gridcheck.py` on a screenshot to read the canvas offset; rotate first with
`transpose` if the recording comes out portrait), scale ÷3 with `flags=area` (each 3 x 3
area sits inside one 6 x 6 art pixel, so the colour is exact and compression noise averages
out), pad to the preview size, and add a stereo track:

```sh
ffmpeg -i shot.mp4 -f lavfi -i anullsrc=r=48000:cl=stereo -shortest \
  -vf "crop=2850:2004:1:1,scale=950:668:flags=area,pad=1920:886:485:109:black,fps=30" \
  -c:v libx264 -profile:v high -level 4.0 -b:v 11M -maxrate 12M -bufsize 24M -pix_fmt yuv420p \
  -c:a aac -b:a 256k -ac 2 preview-part.mp4
```

Replace the silent track with the game's sound effects (recorded on a device or Mac) or a
licensed score. For `gp-render` frames: `-framerate 30 -i frames/late/%04d.png` and drop the
crop and scale.

## Storyboard (25 s)

Cuts and fades only. Captions in the game's font (Pixel Operator 8 at a whole scale, white
or gold), in the black area above or below the game so they never cover the board. Each
caption stays up at least 2 s.

| # | Time | Shot (scene / source) | What happens | Caption |
| --- | --- | --- | --- | --- |
| 1 | 0:00 to 0:02 | `start` (sim recording) | Black screen, one pocket of light, a white ball; two shards breathe in dim mint in the dark | SOMEWHERE IN THE DARK... |
| 2 | 0:02 to 0:05 | `launch` / live play | Hold an open spot: the ghost ball and aim dots appear, pull back, release. Show a flat pixel ring as a touch hotspot on the hold point (no fingers) | HOLD. PULL BACK. LET GO. |
| 3 | 0:05 to 0:09 | `early` (sim recording, live) | Balls ricochet; blocks step paler with each hit, break, and the next cells dither in from black | EVERY BREAK PUSHES BACK THE DARK |
| 4 | 0:09 to 0:12 | `mid` (sim recording) | The lit cave full of white, pink and orange balls; a shard breaks: +1 SHARD | MINT SHARDS BUY SKILLS |
| 5 | 0:12 to 0:15 | `tree` (sim recording) | The skill tree, the Ghost ball selected with BUY 4 | 7 BALL TYPES |
| 6 | 0:15 to 0:18 | `zoomout` then `zoom` (sim) | The whole dig at 0.5x, then a 2x close-up of the balls, both pixel-sharp | PIXEL-PERFECT AT EVERY ZOOM |
| 7 | 0:18 to 0:22 | `late` (`ios.sh shots` late.mp4) | Six ball types flooding a blue wall; coins climbing in the panel | FIND THE GOLDEN PIXEL |
| 8 | 0:22 to 0:25 | `gold` (`ios.sh shots` gold.mp4), fade to `menu` | GOLD! +1 STAR, then the menu's wordmark with the golden pixel twinkling | NO ADS. NO IN-APP PURCHASES. |

**Poster frame:** 0:05 is the default; set it to shot 7 (`late`), the busiest, most colourful
frame, or shot 4 if late looks too noisy as a still.

**YouTube / social version:** same cut at 1920 x 1080 (3x game), plus a 2 s end card
(`assets/header-1920x1080.png`) with "FREE ON IPHONE" and the App Store badge, and music.
Apple's App Store badge has its own usage rules (marketing resources on developer.apple.com);
use it unmodified.

## Second and third previews (optional)

Apple allows three per size; each should show something new:

1. **The dig** (above).
2. **The skill tree and balls:** 20 s on unlocking and using Volt, Bomb, Sniper and Ghost.
3. **The gold:** Radar boxing the gold, Sonar pings, and a boss gold draining as it breaks.

These need live recordings beyond the staged scenes: play a late level in the simulator with a
save that has those skills.
