# Design

**The board is the hero.** Everything else is a thin panel on the right, icons and numbers.

## Rules of the look

- **One grid.** 475 x 334 art pixels, 6 device pixels each on the Duo. Everything lands on it:
  cells, balls, sparks, lightning, the radar outline, text and icons. No anti-aliasing, no
  gradients (ordered dither instead), no sub-pixel positions.
- **Cells are 8 x 8.** Balls are 5 x 5 sprites, smaller than a cell.
- **One light, top-left.** Packed cells are flat colour, so a mass of cells reads as one
  surface with no lines between cells. Only faces open to dug space are shaded: 1 pixel of
  highlight on exposed top and left faces, 1 pixel of shadow on exposed bottom and right
  faces. Walls, balls, icons, cards and buttons follow the same rule.
- **Durability is per cell.** Every breakable cell rolls its own tier (green, lime, amber,
  pink, crimson) from a seeded table that leans tougher each level. Walls are the only
  unbreakable cells; the golden pixel is its own kind.
- **Cracks** grow inside the cell in three stages, the last one black at the core.
- **Fog of war.** Visible = within 3 cells (Chebyshev) of open space. A level starts as the
  spawn pocket plus a 3-cell border; every break pushes the light 3 cells further, opening
  with a square iris per cell. Unrevealed cells are pure black. The gold pulses faintly a few
  cells into the dark; Lantern widens the radius, Radar boxes the gold, Sonar pings.
- **Type.** Pixel Operator 8 (CC0): 7-pixel caps, proportional. HUD icons are 7 x 7.
- **Palette.** "Vercel Neon": black, Vercel greys, gold for the gold and money only.

## Compared with the web version

The web Golden Pixel used many random pixel weights and only showed three pixels in from the
edge. This version keeps that 3-cell rule and makes it the core mechanic (fog you dig through),
puts everything on one pixel grid at the Duo's native scale, replaces stat dumps with icon
cards (details on long-press), and adds pinch zoom for close looks at the cracks and balls.

## Credits

- Font: Pixel Operator 8 by Jayvee Enaguas (HarvettFox96), CC0 1.0
  (tools/fonts/PixelOperator-LICENSE.txt). Baked with tools/bake-font.py.
