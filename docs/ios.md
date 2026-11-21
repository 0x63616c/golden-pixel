# iOS, target device and release

## Target: iPhone Duo, inner screen

| | |
| --- | --- |
| Inner display, rendered | 2853 x 2007 px landscape (2007 x 2853 native portrait) |
| Points | 951 x 669 pt at @3x |
| Physical panel | 1878 x 2670 px at about 430 ppi; iOS downsamples the rendered image to it (about 6.4%) |
| Fold band | about x = 455.5 to 495.5 pt when folded |

Sources: App Store Connect screenshot sizes as collected at iphoneduosupport.com/specs,
blakecrosley.com/blog/iphone-duo-for-developers, getchonky.app/blog/iphone-duo-screen-sizes and
duobreak.com. The simulator's own device profile is captured by CI as `duo-profile.json` in
the `duo-screenshots` artifact.

## The art grid

- One art pixel = **6 x 6 device pixels**. 2853 / 6 = 475, 2007 / 6 = 334, so the canvas is
  **475 x 334** art pixels (2850 x 2004 px, centred with 1.5 px to spare per side).
- A cell is **10 x 10** art pixels. The board view is the left 325 x 334; levels are 93 to 107
  cells across, so you pan around them. The panel takes the right 150 x 334.
- The inner screen's corners are heavily rounded: UI stays `Tuning.cornerRadius` (28 art px)
  clear of them.
- Text is Pixel Operator 8 (7-pixel caps); HUD icons are 7 x 7 to match.
- The board can zoom to 0.5x, 2x, 3x or 4x (3, 12, 18, 24 device pixels per board art pixel).
  The UI never zooms.
- Caveat: because the physical panel is smaller than the rendered image, the last step on real
  glass is iOS's own resample. Everything the app controls is exact (the grid check proves it
  on the rendered image and on simulator screenshots).

## Other phones: same pixels, smaller canvas

One art pixel is **2 points on every screen** (`Display.fit` in the core; 6 device pixels at
@3x), so the game is the same physical size on a phone as on the Duo. A smaller screen shows
a smaller canvas, never smaller pixels:

| | Rendered | Canvas (art px) | Safe area (pt) | Clear canvas |
| --- | --- | --- | --- | --- |
| iPhone Duo (inner) | 2853 x 2007 | 475 x 334 | bottom 34 | 475 x 317 |
| iPhone 18 Pro | 2622 x 1206 | 437 x 201 | left 62, right 62, bottom 20 | 375 x 191 |
| iPhone 18 Pro Max | 2868 x 1320 | 478 x 220 | left 62, right 62, bottom 20 | 416 x 210 |
| iPhone SE | 1334 x 750 (@2x, scale 4) | 333 x 187 | none | 333 x 187 |
| iPhone 13 mini | 2340 x 1080 (2.88 px per pt) | 390 x 180 | left 50, right 50, bottom 20 | 342 x 170 |

All measured on the iOS 27.2 simulators (`just compare` writes each one's safe area). The
last two stand for the narrowest and the shortest canvas iOS 26 runs on. They are `Device.all` in
`Display.swift`, and `UISafetyTests` lays every scene out on each of them.

- The system's safe area comes in with the canvas (`PixelView` passes it to the renderer) and
  ends up in `Layout.safeArea`. The board and the panel's background run to the screen's
  edges, under the Dynamic Island's side and the home indicator. Everything you read or
  press stays inside the safe area and out of the rounded corners (`Layout.safe`).
- A safe area under `Layout.shortHeight` (240) art pixels is "short": the panel's header
  tightens, cards step down through tighter spacing until they fit, and the skill card
  shrinks its tile.
- The panel gives the ball rows whatever height is left under its header: one column of full
  rows while each stays touch-sized (22 art px), otherwise two columns of tiles (the ball, its
  price over the count). All seven types fit on every device without scrolling.
- A menu card taller than the screen (how to play on any phone, settings on the smallest)
  scrolls under its header: drag anywhere on its body.
- Only a screen that cannot give 300 x 160 clear art pixels at 2 points per pixel gets a
  smaller scale.

## Run it

```sh
brew install xcodegen just
just ios-sim                 # iPhone Duo simulator ("GP Duo")
SCENE=mid just ios-sim       # a staged scene (see Scenes.names: menu, start, mid, tree, sheet, launch, zoomout, ...)
just ios-device              # a plugged-in phone (Xcode signed in to team X9E4HG27NK)
```

## Compare the layouts

```sh
just compare                         # Duo, iPhone 18 Pro and iPhone 18 Pro Max -> build/compare
just compare build/compare se mini   # any of duo, iphone, max, se, mini
just ios-sim max                     # play on one of them (SCENE=mid for a staged scene)
swift run -c release gp-render all build/phone --device iphone   # no simulator: duo, iphone, max, se, mini
```

`just compare` screenshots every staged scene on each simulator (`build/compare/<sim>/`) and
stacks them into one sheet per scene in `build/compare/sheets` (`all.png` has every scene).
The sheets are drawn at 1 px per point, so the phones keep their relative sizes on screen.
Each label gives the screenshot size, the art scale found in the image and the canvas that
gives. The screen's rounded corners are cut as on glass (from the simulator's mask,
`<sim>.mask.png`), and the pink outline is the safe area the app was given
(`<sim>.safe-area.json`, written by `PixelView` for staged scenes): outside it sit the Dynamic
Island and the home indicator. Needs Pillow; with `uv` installed it is fetched for the run.

It ends with a grid check of every screenshot at that phone's art scale. The corners and the
safe-area insets are skipped: the screen's mask, the Dynamic Island and the home indicator
are the system's pixels, not the game's. The mini is skipped whole: at 2.88 pixels per point
iOS resamples the frame, so there is no whole-pixel grid on its panel (as on the Duo's glass).

For a quick look without a simulator, `gp-render --device <name>` renders any of
`Device.all` (the canvas, safe area and scale that phone gets) straight from the core.

## App icon

`ios/AppIcon.icon` is an Icon Composer document (iOS 26+ Liquid Glass: default, dark, tinted
and clear), compiled by Xcode into `Assets.car`. Its art is generated: `Icon.swift` draws the
32 x 32 icon as four layers, back to front `board` (blocks, keyline cut out), `gold`, `rays` and
`ball`, and `just icon` writes each as an SVG of whole-art-pixel rects (32-unit viewBox at
1024 pt, so edges stay on the grid) into `AppIcon.icon/Assets`. `icon.json` holds the glass
and is edited in Icon Composer (`open ios/AppIcon.icon`):

- Fill: black in every appearance (the dark is the icon's open space).
- Board group: flat (no glass, specular or shadow) so the blocks stay crisp; 45% opacity
  when tinted/clear so the gold leads.
- Gold group: gold glass with specular and a full-strength layer-colour shadow (its glow);
  the rays flat. The gold is filled white when tinted/clear, the brightest thing on it.
- Ball group: glass with specular and a neutral shadow, the top of the stack.

`just icon-preview` renders all six appearances with Icon Composer's `ictool` into
`build/icon-preview`. `gp-render icon` still writes the flat 1024 px PNGs (marketing art).

## Release

- App: **Golden Pixel**, bundle ID `co.worldwidewebb.goldenpixel`, team `X9E4HG27NK`, SKU `golden-pixel-001`.
- Every merge to `main` runs `.github/workflows/testflight.yml`: it archives with cloud-managed
  signing (App Store Connect API key), uploads to TestFlight, and reports the processing
  state. Builds go to the internal group **Me**. Nothing is ever submitted for review.
- `App Store Connect setup` (manual workflow) registers the bundle ID, finds or creates the
  app record and the TestFlight group. Apple doesn't let API keys create app records, so if
  it reports "No app record yet", create it once in App Store Connect (Apps > + > New App,
  the values above) and run the workflow again.
- Secrets live only in the `testflight` environment (main branch only): `ASC_KEY_ID`,
  `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`. The key needs the Admin role for cloud signing.
- Each CI archive leaves an "Apple Development: Created via API" certificate on the account
  (its key is gone with the runner), and Apple allows ten. The `beta` lane revokes the
  leftovers before it archives (`revoke_leftover_ci_certificates`).
