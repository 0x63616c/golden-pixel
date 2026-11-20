# Agent guide

Golden Pixel is a native Swift iOS game. Read this before changing anything.

## Layout

| Path | What |
| --- | --- |
| `Core/Sources/GoldenPixelCore` | The whole game: rules, levels, fog, economy, sim, UI layout, and the CPU rasteriser. Pure Swift, no Apple UI frameworks (a test enforces it), so it builds and tests on Linux. |
| `Core/Sources/gp-render` | CLI that renders staged scenes and the app icon to PNG, and the icon's layer SVGs for `ios/AppIcon.icon`. |
| `Core/Tests` | Unit tests: durability, economy, level generation, fog reveal, camera and gestures, game flow, renderer invariants, the grid check, architecture. |
| `tools/` | `gridcheck.py` (screenshot grid check), `compare.py` (side-by-side sheets of simulator screenshots), `bake-font.py` (font baking), font licence. |
| `App/` | The iOS shell: SwiftUI app, `MTKView` presenter + shaders, touch mapping, save file, haptics, sound. Thin on purpose. |
| `ios/` | XcodeGen `project.yml`, Info.plist, assets, the Icon Composer app icon (`AppIcon.icon`), `ios.sh` (sim, device, archive, screenshots, device comparison). The `.xcodeproj` is generated, never committed. |
| `fastlane/` | API-key lanes: `setup` (bundle ID, app record, TestFlight group), `beta`, `status`. |
| `.github/workflows` | `ci.yml` (PR gate), `testflight.yml` (main → TestFlight), `asc-setup.yml`, `pr-conventions.yml`. |
| `docs/` | Architecture, design, iOS and release notes. |

## Commands

Run `just` to list recipes. The core needs only Swift 6.2+; app recipes need macOS, Xcode 27
and `xcodegen`.

```sh
swift test                                    # all core tests (what CI and the pre-commit hook run)
swift test --filter FogTests                  # one test class
swift test --filter FogTests/testLevelStartsAsSpawnPocketPlusAThreeCellBorder   # one test
swift run -c release gp-render all build/render   # every staged scene at device scale 6, bloom off
swift run -c release gp-render mid build/render --frames 60   # one scene, as a frame sequence
python3 tools/gridcheck.py build/render/*.png     # grid check (needs Pillow; default --scale 6)
just ios-sim                                  # Duo simulator; SCENE=mid just ios-sim for a staged scene
just shots                                    # Duo simulator screenshots of staged scenes
just compare                                  # the same scenes on the Duo, iPhone 18 Pro and Pro Max, side by side
just hooks                                    # once per clone: enable .githooks/pre-commit
```

`just compare` writes `build/compare/<sim>/<scene>.png` and one sheet per scene in
`build/compare/sheets` (phones at their relative sizes, corners cut as on glass, safe area
outlined in pink). Look at the sheets after any layout change; see `docs/ios.md`.

Scenes are defined in `Core/Sources/GoldenPixelCore/Scenes.swift`. `just render` uses
`--scale 3`, so grid-check its output with `--scale 3`. CI uses the default scale.

## Rules

- **Pixel grid is law.** Everything on screen is drawn into the one art-resolution `Canvas`
  (475x334 on the Duo, 6 device px per art px) and shown at a whole scale with exact texel
  reads. No sub-pixel positions, no anti-aliasing, no gradients (use the Bayer dither), no
  lines between packed cells. Text is Pixel Operator 8 (7-px caps); icons are 7x7. The grid
  check (`GridTests`, `tools/gridcheck.py`) must pass.
- **Flat.** One colour per surface: no highlights, shadows or bevels anywhere (cells,
  sprites, cards, buttons). Blocks are one blue hue whose brightness is their durability.
- **Mind the corners.** The Duo's inner screen corners are heavily rounded: no button or
  text within `Tuning.cornerRadius` of a corner, and every button at least `Tuning.minTouch`
  square (`UISafetyTests`).
- **Only balls break pixels.** Touches never damage the board.
- **One frame buffer.** Never add per-pixel nodes or views. New visuals are `Canvas` drawing
  code in `Renderer.swift` and its `Render*.swift` extensions; the alpha byte is the glow (bloom) mask.
- **Core stays pure.** Logic and rendering live in `GoldenPixelCore` with no platform imports.
  `App/` only presents pixels, forwards touches, saves, and plays feedback.
- **Fog is fair.** Visible = within 3 cells (Chebyshev) of open space, nothing else (tests
  check it). Unrevealed cells render pure black; the only hints in the dark are the gold
  glow, sensed shards (within `Tuning.shardSenseRadius`), sonar rings and the radar box.
- **Tests with behaviour.** Changing rules, economy, levels or fog? Add or update a test in
  `Core/Tests`. Run `swift test` before every commit (the pre-commit hook does it).
- **Look at it.** For visual changes, run `just render` (or `just shots` on a Mac) and check
  the PNGs at 100%: every edge must land on the grid.
- **Target device:** iPhone Duo inner screen (see `docs/ios.md`). Other phones letterbox.

## Shipping

- Branch, PR with a Conventional Commit title, squash-merge when CI is green.
- Merging to `main` uploads a TestFlight build. Never submit for App Store review from CI.
- Never commit or print secrets. The ASC key lives only in the `testflight` environment.
