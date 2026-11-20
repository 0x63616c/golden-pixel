# Golden Pixel: launch marketing kit

Everything for launching Golden Pixel: what it is, who it's for, how it sounds, and what to
post where. The App Store listing itself (name, subtitle, keywords, description) lives in
`fastlane/metadata/en-US/`; this kit stays consistent with it.

| File | What |
| --- | --- |
| `README.md` | This file: positioning, audience, voice, launch plan |
| `press-kit.md` | presskit()-style fact sheet for press and creators |
| `trailer.md` | 25 s App Preview / trailer storyboard, App Store preview rules |
| `social/launch-posts.md` | 5 launch posts for X and Bluesky |
| `social/reddit.md` | 3 Reddit drafts (r/incremental_games, r/iosgaming, r/PixelArt) and a TouchArcade forum thread |
| `social/video-scripts.md` | 3 TikTok / Shorts / Reels scripts with shot lists |
| `social/hashtags.md` | Hashtag and tag sets per platform |
| `assets/` | Generated cards, logo, icon and press screenshots (see below) |
| `tools/make-assets.py` | Builds `assets/` from real game renders |

**Name:** the brand is **Golden Pixel**. The App Store name is "Golden Pixel: Idle Breaker" and
the subtitle is "Bricks, Balls & Buried Gold". Say "Golden Pixel" everywhere else; use the long
name only where a store search needs it.

## Positioning

**Tagline:** Break the blue. Find the gold.

**One-liner:** Golden Pixel is a free idle brick breaker for iPhone: your balls dig through a
dark, pixel-perfect map toward one hidden golden pixel.

**Elevator pitch (60 words):** Every level of Golden Pixel starts as a small pocket of light in
a buried map. You flick balls into the dark like a slingshot; they bounce forever, breaking
blue pixels, and every break pushes the light three cells further. Spend coins on more balls
and glowing mint shards on a skill tree, then crack the golden pixel. Free, no ads, no
in-app purchases.

**Longer pitch (for press emails):** Golden Pixel is an idle brick breaker drawn on a single
pixel grid. You place balls by holding an open spot and pulling back like a slingshot; from
then on they bounce on their own, chipping blocks whose shade of blue tells you exactly how
many hits they have left. Fog of war hides everything more than three cells from open space,
so each level is a dig: toward the faint glow of the golden pixel, past mint shards that
buy a skill tree of seven ball types (Basic, Fast, Heavy, Volt, Bomb, Sniper, Ghost). The gold
is the level's boss; break it and it's a permanent star that makes every later level faster.
It was built for the iPhone Duo's big inner screen, where every art pixel is exactly 6 x 6
device pixels. It's free, with no ads, no in-app purchases and no tracking.

## Audience

1. **Idle and incremental fans** (r/incremental_games, idle-game TikTok). They want numbers
   that climb, meaningful upgrade choices, and a game that respects their time. What hooks
   them: real choices in the tree, a boss gold that scales x1.5 a level, permanent stars,
   offline earnings, and above all **no ads and no IAP**, which is rare in mobile idle games
   and the thing they complain about most.
2. **Pixel-art fans** (r/PixelArt, Bluesky art crowd). What hooks them: a strict grid, flat
   colour, a dithered fog reveal, no blur at any zoom. The craft story (one frame buffer, a
   grid check in CI) is the content here, not the gameplay loop.
3. **iPhone Duo and foldable owners.** A new screen shape with few apps made for it. What
   hooks them: a game made for the inner screen at its native scale, landscape, using the
   whole panel. Also plays on every other iPhone, letterboxed.
4. **Brick-breaker and satisfying-video fans** (TikTok, Shorts). They don't need the system;
   they need 40 balls ricocheting through a wall of blue and the light flooding in.

## Key selling points (in priority order)

1. **Free. No ads. No in-app purchases. No tracking.** Lead with this for idle players.
2. **Dig through the dark.** Fog of war is the core mechanic: every break pushes the light out
   three cells, and the gold glows faintly through the black.
3. **Slingshot launch, then hands off.** Hold, pull back, let go; the ball bounces forever.
4. **Durability you can read.** One blue hue; lighter means closer to breaking. No numbers on
   the board, no crack marks.
5. **Seven ball types, one skill tree** paid in glowing mint shards: damage, speed, crits,
   Lantern, Radar and Sonar to find the gold.
6. **The gold is a boss**, and every golden pixel you break is a star for good.
7. **Pixel-perfect.** One grid, flat colour, no anti-aliasing, at every zoom from 0.5x to 4x.
8. **Made for iPhone Duo's inner screen**; plays on every iPhone.
9. **Keeps digging while you're away** (offline earnings).

## Voice and tone

Calm, exact, a little bit mysterious. The game is dark and quiet with one warm light in it;
the copy should feel the same. Short sentences. Concrete nouns (pixels, balls, shards, gold)
over adjectives. Confident about craft, never about hype.

**Do**

- Say what happens: "every break pushes the light three cells further".
- Use the game's own words: pixels, blue, gold, mint shards, stars, dig, the dark.
- Show it. Every post gets a real render, card or capture.
- Be upfront: solo dev, free, no ads, no IAP, made for one screen first.
- Write UI-style text in caps when it's on an image (the game's type is all-caps on cards).
- Credit the font (Pixel Operator 8, CC0) when talking about the look.

**Don't**

- Don't say "addictive", "revolutionary", "the best", "must-play" or "#1".
- Don't promise features that aren't in the build (no multiplayer, cloud sync, iPad).
- Don't say "AI" anything; the art is the game's own renderer.
- Don't scale images by non-whole factors or blur them; use `assets/` or `gp-render` output.
- Don't add glows, bevels, gradients or drop shadows to the logo or screenshots.
- Don't post the same text to every subreddit; each draft in `social/reddit.md` is tailored.
- Don't use emoji runs or more than 3 to 5 hashtags.
- Don't mention prices in the App Store preview (Apple's rule); "free" is fine everywhere else.

## Visual kit

Palette (from `Core/Sources/GoldenPixelCore/Palette.swift`): black `#000000`; panel greys
`#0b0c10` to `#343948`; text `#eef0f5`; blue durability ladder `#b9d2ff` `#74a3ff` `#3a78f0`
`#2858c4` `#22408a` `#1d2c52`; gold `#ffd23f` (gold and coins only); mint `#4dffc3` (shards
only); accent blue `#3d7bff`. Type: Pixel Operator 8, caps, at whole multiples only.

### Generated assets

Run from the repo root (needs Swift and Pillow):

```sh
python3 -m venv /tmp/gp-venv && /tmp/gp-venv/bin/pip install Pillow   # once
/tmp/gp-venv/bin/python marketing/tools/make-assets.py               # render the game + compose
/tmp/gp-venv/bin/python marketing/tools/make-assets.py --no-render   # recompose from the last renders
```

The script renders the game fresh each run (`gp-render` scenes, the menu's wordmark, and
`gp-render icon`), so **re-run it after any change to the icon, logo, palette or scenes**. Each
card is laid out on one art grid and enlarged by a whole factor with nearest-neighbour
only; `tools/gridcheck.py --scale N` passes on every card at 100%.

| File | Size | Use |
| --- | --- | --- |
| `assets/og-1200x630.png` | 1200 x 630 (2x) | Link preview (Open Graph, X, Bluesky), Product Hunt, press emails |
| `assets/header-1920x1080.png` | 1920 x 1080 (3x) | X/Bluesky/YouTube/itch header, press hero, wallpaper |
| `assets/square-1080x1080.png` | 1080 x 1080 (3x) | Instagram, X/Bluesky image post, Reddit thumbnail |
| `assets/story-1080x1920.png` | 1080 x 1920 (3x) | Stories, TikTok/Shorts cover; text kept in the middle 66% |
| `assets/tree-1080x1080.png` | 1080 x 1080 (2x) | Feature card: the skill tree and the 7 balls in their colours |
| `assets/icon-1024.png` | 1024 x 1024 (16x) | App icon with stepped corners, transparent |
| `assets/logo-x4.png`, `logo-x8.png` | 916 x 448, 1832 x 896 | Wordmark with its 2-px black keyline, transparent |
| `assets/screens/*-1900x1336.png` | 1900 x 1336 (4x) | Press screenshots: menu, start, mid, late, zoom, sheet, tree, gold |

For a bespoke size, run `swift run -c release gp-render <scene> <dir> --scale N` (any whole N)
or compose with the helpers in `make-assets.py`.

## Launch plan

Release date: **TBD**. "L" below is launch day. Times: post at 9 to 11 am US Eastern on a
Tuesday to Thursday for press and Reddit; X/Bluesky/TikTok can follow your own audience's peak.

### Pre-launch (L-21 to L-1)

| When | What | Where |
| --- | --- | --- |
| L-21 | Claim handles (`@goldenpixelgame` or similar) on X, Bluesky, TikTok, YouTube, Instagram. Set header + avatar from `assets/`. Pin the OG card. | All |
| L-21 | Put up a one-page site (or itch.io page) with the trailer, `press-kit.md` content, and the press zip. Point `fastlane/metadata/en-US/marketing_url.txt` at it if it replaces GitHub. | Web |
| L-21 to L-7 | Weekly dev posts: the grid check, the dithered fog reveal, the slingshot, the colour ladder. One GIF/clip each. Reply to everyone. | X, Bluesky, r/PixelArt (once) |
| L-14 | Public TestFlight link (optional) and an App Store **pre-order** page if you want a launch-day spike from pre-orders. | App Store Connect |
| L-14 | Feedback Friday thread: post the TestFlight with an honest "looking for feedback on pacing" ask; leave feedback on others' games too. | r/incremental_games |
| L-10 | Email the indie press list (below) with the press kit, a TestFlight or promo code, and the release date under embargo. | Email |
| L-7 | First TikTok/Short: "Satisfying" script (video-scripts.md #1). | TikTok, Shorts, Reels |
| L-3 | Second clip: "The fog" (script #2). Post the trailer to YouTube as unlisted, ready to flip. | TikTok, Shorts, YouTube |

### Launch day (L)

1. Release in App Store Connect early morning; check the live listing and that the link works.
2. Flip the trailer to public. Post launch post #1 on X and Bluesky with the trailer; pin it.
3. TouchArcade forums: new thread in the released-games forum (check the current section
   names) with the TouchArcade draft at the end of `social/reddit.md`.
4. If L is a Saturday: r/iosgaming Developer Saturday post. Otherwise schedule it for the next
   Saturday; don't post it on another day.
5. r/incremental_games: the launch post only if your last post there was 30+ days ago (Rule
   1D); otherwise Feedback Friday.
6. Email press again: "out now" with the App Store link (short, one paragraph).
7. Product Hunt: optional (see below). If you do it, launch 12:01 am Pacific with the OG card,
   tree card and trailer as gallery.
8. Spend the day replying. Every comment answered within a few hours is worth more than
   another post.

### First two weeks

| Day | What |
| --- | --- |
| L+1 | Third clip: "The gold" (script #3). Thank-you post with the first player numbers you're happy to share. |
| L+2 | r/PixelArt post (the craft angle, not the launch). |
| L+3 to L+5 | Answer reviews in App Store Connect. Collect bug reports; ship a quick fix build if needed. |
| L+5 | Saturday: r/iosgaming Developer Saturday (if not done on L). |
| L+7 | Dev-story thread on X/Bluesky: "how the whole game is one frame buffer" (press-kit.md has the facts). |
| L+7 | Follow up with press who opened but didn't reply (one nudge only). |
| L+10 | Clip of a player-requested moment (a huge late-game board, a Ghost ball build). |
| L+14 | Update post: what changed since launch, what's next. Ask for App Store ratings in that post, never in the game with a nag. |

### Channels and what goes where

| Channel | Post | Asset |
| --- | --- | --- |
| X | Launch posts (`social/launch-posts.md`), clips, dev threads | Trailer, square, OG card |
| Bluesky | Same posts (300-char limit; all drafts fit), more craft and pixel-art focus | Square, tree card, GIFs |
| r/incremental_games | Feedback Friday pre-launch; one launch post (30-day rule) | Square card or a screenshot; text post with App Store link |
| r/iosgaming | Developer Saturday post only, link straight to the App Store | Screenshot or trailer |
| r/PixelArt | The craft: grid, palette, dither fog. Not a store ad. | `screens/zoom`, `screens/mid`, a crisp GIF |
| TouchArcade forums | Release thread (released iPhone games section); keep updating it | Trailer + screenshots |
| TikTok / Shorts / Reels | 3 scripts in `social/video-scripts.md`, then weekly | Simulator recordings, story card as cover |
| YouTube | Trailer, then shorts | Header, trailer |
| Product Hunt | Optional. Games rarely rank but it's a free backlink; skip it if launch day is busy. | OG card, tree card, trailer |
| Press | Embargoed email L-10, "out now" email on L | `press-kit.md`, `assets/` zip |

### Indie and mobile press list (to verify and fill in)

Pick 10 to 20 who cover iOS indies and idle games; find the right writer, not the generic inbox.

- TouchArcade (news tips, forums)
- Pocket Gamer (and Pocket Gamer's "best new mobile games" roundups)
- 148Apps / AppAdvice / iMore-style iOS sites still active
- Gamezebo
- Pocket Tactics
- Rock Paper Shotgun / Eurogamer / PC Gamer only if a mobile writer there covers idle games
- Idle-game YouTubers and TikTokers (search "idle game review", "incremental game" channels)
- Pixel-art creators on Bluesky and X who repost process work
- Foldable-phone sites and YouTube channels covering iPhone Duo apps
- Newsletters: indie game newsletters that take submissions (search "indie game newsletter submit")

Track who you emailed, when, and the reply in a simple sheet.

## You need to decide or supply

- **Developer name** for credits and press (`press-kit.md` has `[DEVELOPER NAME]`).
- **Contact email** for press (`[PRESS EMAIL]`); not a personal one if you can help it.
- **Website / press page URL** (`[WEBSITE]`); currently the listing points at the GitHub repo.
- **Launch date** and whether to use App Store pre-orders.
- **Social handles** to register.
- **Trailer music:** use the game's own sound effects, or a track you hold rights to in all
  territories (Apple's rule).
- Whether to do **Product Hunt** at all.
