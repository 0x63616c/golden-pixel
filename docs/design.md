# Design

**The board is the hero.** Everything else is a panel on the right: coins, shards, the TREE
and MENU buttons, and one row per ball type.

## How a level plays

- **Only balls break pixels.** Taps on the board just say what's there; drags pan.
- **Coins buy balls.** Tap a ball row for its info sheet (big BUY button); drag a row to aim
  it like a slingshot (it launches opposite the drag, with a dotted path preview) and let go
  to buy.
- **Shards buy the skill tree.** Glowing mint shard pixels pay shards; a level's shards add up
  to the whole tree. You sense a shard through the dark once your light gets within 6 cells.
  The tree holds the general skills and every ball type's upgrades (unlock, damage, speed,
  special, two specialisations).
- **Break the gold to clear the level.** Each gold is a star for good (+5% damage, +10%
  coins). Every level starts fresh: coins, shards, tree and balls reset.
- Levels are 45 to 67 cells across, much bigger than the screen; the camera starts on the
  spawn and pinches between 0.5x, 1x, 2x, 3x and 4x.

## Rules of the look

- **One grid.** 475 x 334 art pixels, 6 device pixels each on the Duo. Everything lands on it:
  cells, balls, sparks, lightning, the radar outline, text and icons. No anti-aliasing, no
  gradients (ordered dither instead), no sub-pixel positions.
- **Cells are 10 x 10.** Balls are 5 x 5 circles with a true centre pixel; trails are drawn
  through past centre pixels so the tail is centred.
- **Durability is brightness alone.** Blocks are one blue hue: bright = tough, faint = one
  hit left. A block steps down one shade per hit unit (bigger hits skip steps), flashing white
  for one frame per hit; the hit after the faintest shade breaks it. No crack marks.
- **Flat.** One colour per surface: no highlights, shadows or bevels on cells, sprites,
  cards or buttons. Packed cells read as one surface with no lines between them. Walls are a
  neutral dark grey, never brighter than the blocks, so nothing pale floats in the dark.
- **Durability is per cell.** Every breakable cell rolls its own starting shade from a seeded
  table that leans tougher each level. Walls are the only unbreakable cells; the golden pixel
  and the mint shards are their own kinds.
- **Rounded corners.** The Duo's inner screen has heavily rounded corners
  (`Tuning.cornerRadius`): no button or text sits in them, and every button is at least
  `Tuning.minTouch` (22 art px = 44 pt) square. `UISafetyTests` checks both.
- **Fog of war.** Visible = within 3 cells (Chebyshev) of open space. A level starts as the
  spawn pocket plus a 3-cell border; every break pushes the light 3 cells further, opening
  by dithering each cell in from black. Unrevealed cells are pure black. The gold pulses
  faintly a few cells into the dark, sensed shards breathe in dim mint; Lantern widens the
  radius, Radar boxes the gold, Sonar pings.
- **Type.** Pixel Operator 8 (CC0): 7-pixel caps, proportional. HUD icons are 7 x 7.
- **Palette.** Black and cool greys, a blue durability ramp, gold for the gold and coins
  only, mint for shards.

## Compared with the web version

The web Golden Pixel used many random pixel weights and only showed three pixels in from the
edge. This version keeps that 3-cell rule and makes it the core mechanic (fog you dig through),
puts everything on one pixel grid at the Duo's native scale, replaces stat dumps with icon
cards (details on long-press), and adds pinch zoom for close looks at the balls and colours.

## Credits

- Font: Pixel Operator 8 by Jayvee Enaguas (HarvettFox96), CC0 1.0
  (tools/fonts/PixelOperator-LICENSE.txt). Baked with tools/bake-font.py.
