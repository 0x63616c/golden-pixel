# Agent guide

Golden Pixel is a native Swift iOS game. Read this before changing anything.

## Layout

| Path | What |
| --- | --- |
| `Core/Sources/GoldenPixelCore` | The whole game: rules, levels, fog, economy, sim, UI layout, and the CPU rasteriser. Pure Swift, no Apple UI frameworks (a test enforces it), so it builds and tests on Linux. |
| `Core/Sources/gp-render` | CLI that renders staged scenes and the app icon to PNG. |
| `Core/Tests` | Unit tests: durability, economy, level generation, fog reveal, camera and gestures, game flow, renderer invariants, the grid check, architecture. |
| `tools/` | `gridcheck.py` (screenshot grid check), `bake-font.py` (font baking), font licence. |
| `App/` | The iOS shell: SwiftUI app, `MTKView` presenter + shaders, touch mapping, save file, haptics, sound. Thin on purpose. |
| `ios/` | XcodeGen `project.yml`, Info.plist, assets, `ios.sh` (sim, device, archive, screenshots). The `.xcodeproj` is generated, never committed. |
| `fastlane/` | API-key lanes: `setup` (bundle ID, app record, TestFlight group), `beta`, `status`. |
| `.github/workflows` | `ci.yml` (PR gate), `testflight.yml` (main → TestFlight), `asc-setup.yml`, `pr-conventions.yml`. |
| `docs/` | Architecture, design, iOS and release notes. |

## Rules

- **Pixel grid is law.** Everything on screen is drawn into the one art-resolution `Canvas`
  (475x334 on the Duo, 6 device px per art px) and shown at a whole scale with exact texel
  reads. No sub-pixel positions, no anti-aliasing, no gradients (use the Bayer dither), no
  lines between packed cells. Text is Pixel Operator 8 (7-px caps); icons are 7x7. The grid
  check (`GridTests`, `tools/gridcheck.py`) must pass.
- **One light, top-left.** Shade only faces exposed to open space: highlight top/left,
  shadow bottom/right, 1 px. Same for walls, sprites, cards and buttons.
- **One frame buffer.** Never add per-pixel nodes or views. New visuals are `Canvas` drawing
  code in `Renderer.swift`; the alpha byte is the glow (bloom) mask.
- **Core stays pure.** Logic and rendering live in `GoldenPixelCore` with no platform imports.
  `App/` only presents pixels, forwards touches, saves, and plays feedback.
- **Fog is fair.** Visible = within 3 cells (Chebyshev) of open space, nothing else (tests
  check it). Unrevealed cells render pure black; the only hints in the dark are the gold
  glow, sonar rings and the radar box.
- **Tests with behaviour.** Changing rules, economy, levels or fog? Add or update a test in
  `Core/Tests`. Run `swift test` before every commit (the pre-commit hook does it).
- **Look at it.** For visual changes, run `just render` (or `just shots` on a Mac) and check
  the PNGs at 100%: every edge must land on the grid.
- **Target device:** iPhone Duo inner screen (see `docs/ios.md`). Other phones letterbox.

## Shipping

- Branch, PR with a Conventional Commit title, squash-merge when CI is green.
- Merging to `main` uploads a TestFlight build. Never submit for App Store review from CI.
- Never commit or print secrets. The ASC key lives only in the `testflight` environment.
