# Architecture

```
touches ──► PointerTracker ──► Gesture ──► Game.handle ──► Game (rules, sim, camera)
                                                            │
CADisplayLink (MTKView) ──► Game.update(dt) ──► Renderer.render ──► Canvas (475x334 RGBA)
                                                                     │ one texture upload
                                            Metal: glow pass (optional) + present pass
                                            (exact texel reads, whole scale, centred)
```

- **GoldenPixelCore** (Swift package, no platform imports; a test enforces it) holds all of
  it: levels, fog, economy, simulation, UI layout and hit-testing, the camera, the font and
  sprites, and the CPU rasteriser. It builds and tests on Linux.
- **One frame buffer.** The renderer draws every frame into one `Canvas` of art pixels: the
  board (into its own 330 x 330 canvas, then copied through the camera at a whole zoom), the
  HUD, the panel, overlays, text. No views or nodes per pixel. The alpha byte is the glow mask.
- **Presentation** (`App/PixelView.swift`, `App/Shaders.metal`): the canvas is uploaded as one
  `rgba8` texture; the present pass reads exact texels (`texture.read`) at a whole-number
  scale. Bloom is a separate, optional post-pass (off by default) so the base image is always
  pixel-exact.
- **Grid check.** `GridTests` upscales every staged scene and asserts every N x N block is one
  colour, and that a zoomed board is whole zoom x zoom blocks. CI also renders all scenes with
  `gp-render` and runs `tools/gridcheck.py` on them and on the iPhone Duo simulator screenshots.
- **Camera** (`Camera.swift`): zoom is canvas pixels per board pixel. Pinch is continuous;
  release eases to the nearest whole zoom (1 to 4) and snaps the origin to a whole pixel.
  One-finger drags that start on open space or fog pan; ones that start on a block chip
  blocks. Double-tap on open space toggles fit and 2x; taps on blocks always hit.
- **Saves**: versioned JSON in Application Support (`SaveCodec`), autosaved every 10 s and on
  backgrounding; an unreadable save is moved aside, never overwritten.
