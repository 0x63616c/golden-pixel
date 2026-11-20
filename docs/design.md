# Design

**The board is the hero.** Everything else is a panel on the right: coins, shards, the TREE
and pause buttons, and one row per unlocked ball type.

## How a level plays

- **Only balls break pixels.** Touches never damage the board; drags pan, a hold says what a
  cell is.
- **Coins buy balls.** A level starts with no balls and coins for exactly one basic ball. The
  panel lists only unlocked types; tap one to select it (lit row, colour bar). Hold an open
  spot on the board where you want the ball for a moment (a tick, and a ghost ball appears
  inside a ring wider than your fingertip, so you see the hold take; it fades out as you
  pull), then pull back like a slingshot: it flies the opposite way to your pull, and four dots of one size in front of
  the ghost show that way; let go to buy it. A plain tap on an open
  spot uses the last direction. A quick one-finger drag always pans, so open levels stay easy
  to move around; two fingers pan and zoom. Tap the selected row again (or hold any row) for its info sheet. Coins read in
  full (1,800) below a million.
- **Durability you can count.** One shade is one hit from an unupgraded basic ball, on every
  level; level length comes from each level's coin payout (`Tuning.levelPayout`).
- **Pause and restart.** The panel's pause button (two bars) opens: RESUME, RESTART LEVEL (asks first),
  MAIN MENU. The main menu itself is just PLAY/CONTINUE, HOW TO PLAY and SETTINGS.
- **Shards buy the skill tree.** Solid glowing mint shard pixels (one hit each) pay shards; a level's shards add up
  to the whole tree, and deeper shards pay more. You sense a shard through the dark once your
  light gets within 6 cells, but only the two closest show at once.
  The tree holds the general skills and every ball type's upgrades (unlock, damage, speed,
  special, two specialisations).
- **Break the gold to clear the level.** It's the level's boss: hundreds of hits (400 on level
  1, x1.5 a level), draining dim from the top as it takes damage. Each gold is a star for good (+5% damage, +10%
  coins). Every level starts fresh: coins, shards, tree and balls reset.
- Levels are 93 to 107 cells across, much bigger than the screen, and take 15 to 25
  minutes (`swift run -c release gp-sim` checks it); the camera starts on the
  spawn and pinches between 0.5x, 1x, 2x, 3x and 4x.

## Rules of the look

- **One grid.** 475 x 334 art pixels, 6 device pixels each on the Duo. Everything lands on it:
  cells, balls, sparks, lightning, the radar outline, text and icons. No anti-aliasing, no
  gradients (ordered dither instead), no sub-pixel positions.
- **Cells are 10 x 10.** Balls are 5 x 5 circles with a true centre pixel; trails are drawn
  through past centre pixels so the tail is centred.
- **Durability is lightness alone.** Blocks are one blue hue: deep = tough, pale = one hit
  left. A block steps one shade paler per hit unit (bigger hits skip steps), flashing white
  for one frame per hit; the hit after the palest shade breaks it. No crack marks.
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
