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
  level.
- **Small, countable coins.** Every block pays 1 coin (a sparkling one 5), before Greed and
  stars; toughness only costs time, so soft pockets are the money and hard rock is in the
  way. Every ball type's first ball costs 1 coin, and each one after costs a fixed step more
  (`BallType.costStep`: basic +8, heavy +60, ghost +400), so prices stay in the hundreds.
  Unlocking a type in the tree (shards) is what a new type really costs: 2 to 6 shards.
  Every other rank in the tree is 1 shard, a specialisation 2 (182 for the whole tree).
- **Pause and restart.** The panel's pause button (two bars) opens: RESUME, RESTART LEVEL (asks first),
  MAIN MENU. The main menu itself is just PLAY/CONTINUE, HOW TO PLAY and SETTINGS, plus LEVELS
  once a level is cleared.
- **Level select.** LEVELS lists every level up to the furthest reached. The current level
  (gold) carries on where it was; any other starts fresh, and leaving a level in progress takes
  a second tap. Only a level's first clear gives a star, so replays are for fun.
- **Shards buy the skill tree.** Solid glowing mint shard pixels (one hit each) pay shards; a level's shards add up
  to the whole tree, and deeper shards pay more. You sense a shard through the dark once your
  light gets within 6 cells, but only the two closest show at once.
  The tree holds the general skills and every ball type's upgrades (unlock, damage, speed,
  special, two specialisations).
- **Break the gold to clear the level.** It's the level's boss: hundreds of hits (400 on level
  1, x1.5 a level), draining dim from the top as it takes damage. Each first clear is a star for good (+5% damage, +10%
  coins). Every level starts fresh: coins, shards, tree and balls reset.
- Levels are 93 to 107 cells across, much bigger than the screen, and take 8 to 12
  minutes for the first four levels, then 15 to 25 (`swift run -c release gp-sim` checks it); the camera starts on the
  spawn and pinches between 0.5x, 1x, 2x, 3x and 4x.

## The levels

Each level is a place: its own outline and one idea about space. You find the shape by
digging it out, and breaking the gold lights the whole of it. `swift run -c release gp-render
levels build/levels` draws all seven on one sheet (rock, durability, spawn, shards, gold).

| | Level | The place | The idea |
| --- | --- | --- | --- |
| 1 | FIRST LIGHT | An open cave with a wobbly rim and a few boulders | Nothing in the way: learn the dig. The gold hides on the far side. |
| 2 | HOURGLASS | Two bulbs joined by a neck nine cells wide | Spawn at the foot, gold at the head: everything goes through the neck, so where you put a ball starts to matter. |
| 3 | CROSSROADS | Four round petals off a hub with a boulder in the middle | You start in the bottom petal. Each of the other three has a walled shrine with its door on the far side: the gold in one, a rich shard in the other two. The hub is where you choose. |
| 4 | HONEYCOMB | Nineteen six-sided rooms | Most walls have a door, some don't, so the way from the bottom room to the gold in a top one winds a little. |
| 5 | NAUTILUS | A shell: one passage coiling inward, halving in width each turn, crossed by curved chamber walls | A long way round to a gold that is close by, at the very middle of the coil. |
| 6 | LABYRINTH | A square maze round a treasure room | The maze's walls are its toughest rock, not solid: a ball can break through, it just takes far longer than the corridor. Only the posts and the treasure room (one door, on the far side) are unbreakable. Dead ends hold shards. |
| 7 | CITADEL | A castle: corner towers, two walls and a keep, each two cells thick | No two gates line up, so the way in goes round: towers, side gates, the far gate, back round to the keep. A shard in every tower. |

Later levels (DEEP 1, 2, ...) reuse the seven shapes with new seeds.

What makes a level play well here:

- **Keep the dig wide.** Balls can't be steered once placed, so a ball is only useful while it
  can reach rock. In an open space every flight ends on a block; down a long walled corridor
  most end on a wall, and the further the dig face gets the less each ball does. A level made
  of solid-walled corridors is a slog (`gp-sim` shows it as a long "longest gap"). So walls
  are accents: necks, gates, rooms with wide doors. Where a shape needs a maze of walls, they
  are hard rock (`Plan.hard`), which every hit still wears down.
- **The shape sets the length.** There is no payout dial: a level's clear time comes from how
  far the gold is by the dig and how much rock is in the way. Check with `gp-sim` after any
  change (`--place face` plays as someone who puts balls where the digging is, which is
  quicker on the winding levels).
- **Dead ends pay.** A shape lists its side rooms and dead ends (`Plan.treasures`) and each
  gets a shard.

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
- **Deeper is tougher, with patches.** Rock hardens the further the dig has to go to reach it
  from the spawn (round walls, not through them), broken up by soft pockets to dig toward
  and hard clumps to go round. Each level's mix of shades comes
  from a seeded table that leans tougher each level; only the layout is designed. Walls are
  the only unbreakable cells; the golden pixel and the mint shards are their own kinds.
- **Rounded corners.** The Duo's inner screen has heavily rounded corners
  (`Tuning.cornerRadius`): no button or text sits in them, and every button is at least
  `Tuning.minTouch` (22 art px = 44 pt) square. `UISafetyTests` checks both.
- **Fog of war.** Visible = within 3 cells (Chebyshev) of open space. A level starts as the
  spawn pocket plus a 3-cell border; every break pushes the light 3 cells further, opening
  by dithering each cell in from black. Unrevealed cells are pure black. The gold pulses
  faintly a few cells into the dark once you've dug within 5 cells of it, sensed shards breathe in dim mint; Lantern widens the
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
- Music: eleven CC0 tracks, listed with their artists and sources in docs/music.md. Baked with
  tools/bake-music.py.
