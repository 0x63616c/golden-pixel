# Architecture

```
touches ──► PointerTracker ──► Gesture ──► Game.handle ──► Game (rules, sim, camera)
                                                            │
CADisplayLink (MTKView) ──► Game.update(dt) ──► Renderer.render ──► Canvas (475x334 RGBA on the Duo)
                                                                     │ one texture upload
                                            Metal: glow pass (optional) + present pass
                                            (exact texel reads, whole scale, centred)
```

- **GoldenPixelCore** (Swift package, no platform imports; a test enforces it) holds all of
  it: levels, fog, economy, simulation, UI layout and hit-testing, the camera, the font and
  sprites, and the CPU rasteriser. It builds and tests on Linux.
- **One frame buffer.** The renderer draws every frame into one `Canvas` of art pixels: the
  board (into its own level-sized canvas, only the part in view, then copied through the
  camera), the HUD, the panel, overlays, text. `Renderer.swift` dispatches by screen;
  `RenderBoard`, `RenderPanel`, `RenderTree` and `RenderMenu` draw each part. No views or nodes per pixel. The alpha byte is the glow mask.
- **Presentation** (`App/PixelView.swift`, `App/Shaders.metal`): the canvas is uploaded as one
  `rgba8` texture; the present pass reads exact texels (`texture.read`) at a whole-number
  scale. Bloom is a separate, optional post-pass (off by default) so the base image is always
  pixel-exact.
- **Grid check.** `GridTests` upscales every staged scene and asserts every N x N block is one
  colour, and that a zoomed board is whole zoom x zoom blocks. CI also renders all scenes with
  `gp-render` and runs `tools/gridcheck.py` on them and on the iPhone Duo simulator screenshots.
- **Camera** (`Camera.swift`): zoom is canvas pixels per board pixel. Pinch is continuous;
  release eases to the nearest level (0.5, 1, 2, 3, 4; 0.5 is an exact every-other-pixel
  subsample) and snaps the origin to a whole pixel. The board camera may overscroll (any board
  point can reach the view's centre), so a level opens with the spawn in the middle. One-finger
  drags on the board pan; a short hold (`PointerTracker.holdTime`) on an open cell places a
  ball and a drag from there aims it; a long hold on a pixel says what it is. Touches never damage anything. The skill tree uses the
  same camera with levels 0.5, 1 and 2 and half overscroll, and opens framed on the nodes showing
  (`SkillTree.focus`).
- **Ball physics** (`Sim.swift`): a ball is a circle of `Tuning.ballRadius` cells. Each step
  finds the first point on its path where it touches a cell (`Game.touch`: a flat side, or a
  corner's round) and mirrors it there, so a bounce is the same at any frame rate and any ball
  speed, and cells packed side by side act as one flat wall. Nothing about a bounce is random,
  with one exception: a ball that repeats one of its last `Tuning.loopMemory` wall bounces is in
  a loop that touches only walls and would never earn again, so that bounce is turned by up to
  `Tuning.loopNudge`. `PhysicsTests` holds all of this.
- **Saves**: versioned JSON in Application Support (`SaveCodec`), autosaved every 10 s and on
  backgrounding; an unreadable save is moved aside, never overwritten.
