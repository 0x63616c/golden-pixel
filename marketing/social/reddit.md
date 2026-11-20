# Reddit drafts (and a TouchArcade thread)

Three posts, one per community, each written for that community's culture. Reddit's general
rule of thumb still applies: be a member, not a billboard. Comment on other people's posts in
the weeks before, disclose that you're the developer, answer every reply, and don't
cross-post the same text.

**Check the sidebar before posting.** Reddit blocks automated fetching, so the rules below come
from mirrors of the subreddits as of November 2026 and may have changed. Re-read each
subreddit's rules on the day.

---

## r/incremental_games

**Culture:** experienced idle players and many devs. They value depth, honest numbers and
respect for their time, and they are openly hostile to ads, energy timers and pay-to-skip.
Mobile games get a fair hearing if they're clean. Low-effort "check out my game" posts get
downvoted.

**Rules to know:**

- Rule 1D (as of late 2026): **30 days between new posts** about your game, and the post must
  link to something playable.
- Before launch, use the weekly **Feedback Friday** thread (works in progress; comment on other
  people's games too and include a link).
- Disclose you're the developer.

**When:** pre-launch in Feedback Friday (TestFlight link); the post below on launch day or
when 30 days have passed since your last post.

**Flair:** the game/release flair if offered (check the list).

**Title:**

> Golden Pixel: an idle brick breaker where you dig through fog toward a boss pixel (iOS, free, no ads, no IAP)

**Body:**

> Hi all, I'm the solo dev. Golden Pixel just came out on iPhone and I'd love this sub's take
> on the pacing.
>
> **The loop**
>
> - Each level is a big buried map (93 to 107 cells across). You start in a small pocket of
>   light with enough coins for one ball.
> - Place balls with a slingshot (hold an open spot, pull back, let go). They bounce forever
>   and chip blocks; blocks pay coins; coins buy more balls of any type you've unlocked.
> - Fog of war: you only see 3 cells past open space. Every break pushes the light 3 cells
>   further. The gold glows faintly through the dark.
> - Durability is shown as lightness: one blue hue, one shade paler per hit from an
>   unupgraded basic ball. No hidden HP.
> - Mint shards in the rock pay out shards, which buy a skill tree: general skills (damage,
>   speed, crits, coins, idle earnings, Lantern/Radar/Sonar to find the gold) and a branch per
>   ball type, each with two specialisations. A level's shards add up to the whole tree.
> - The golden pixel is the boss: 400 hits on level 1, x1.5 per level. Breaking it ends the
>   level.
>
> **Prestige**
>
> Every level starts fresh (coins, shards, tree, balls). What you keep is stars: each gold is
> a permanent +5% damage and +10% coins. Levels are tuned (with a headless sim) to take about
> 15 to 25 minutes each, with no long stretch where there's nothing to buy.
>
> **Monetisation:** none. Free, no ads, no IAP, no tracking. Offline earnings are a skill, not
> a purchase.
>
> **Seven ball types:** Basic, Fast (sometimes hits twice), Heavy (pierces what it breaks),
> Volt (chains to nearby pixels), Bomb (area damage), Sniper (turns toward the nearest pixel
> after each bounce), Ghost (phases through pixels every few seconds).
>
> It was built for the iPhone Duo's inner screen but plays on any iPhone (landscape).
>
> App Store: [LINK]
>
> Things I'd especially like feedback on: is 15 to 25 minutes a level the right length, does
> the full reset each level feel fair with stars as the carry-over, and which ball feels
> under- or overpowered.

**Attach:** none needed (text post), or `assets/tree-1080x1080.png` as the first comment.

---

## r/iosgaming

**Culture:** iPhone players looking for good games, especially premium-feeling ones without
predatory monetisation. Short, clear posts with screenshots do best.

**Rules to know:**

- **Developer self-promotion only on Saturdays** ("Developer Saturday"). Posts on other days
  are removed and can get you banned.
- Use the **Developer Saturday (Self-Promo) [DEV]** flair.
- Link **directly to the App Store** (no blogs, link shorteners or landing pages).
- Disclose that you're the developer.

**When:** the first Saturday on or after launch.

**Title:**

> [DEV] Golden Pixel: a free idle brick breaker where you dig through the dark for one golden pixel. No ads, no IAP.

**Body (with an image or the trailer):**

> Hey r/iosgaming, I made Golden Pixel, and it's out now.
>
> You flick balls into a dark, pixel-perfect map like a slingshot. They bounce forever,
> breaking blue blocks (the paler a block, the closer it is to breaking), and every break
> pushes the light a little further into the fog. Coins buy more balls, mint shards buy a
> skill tree with seven ball types, and the golden pixel hidden somewhere in each level is
> the boss.
>
> - Free, no ads, no in-app purchases, no accounts, no tracking
> - Keeps earning while you're away
> - Pixel-perfect at every zoom (one art pixel = 6 x 6 screen pixels on iPhone Duo)
> - Made for iPhone Duo's inner screen; works on every iPhone in landscape
>
> App Store: [LINK]
>
> Happy to answer anything about how it was made.

**Attach:** `assets/screens/late-1900x1336.png` or the trailer.

---

## r/PixelArt

**Culture:** artists. They care about technique: clean scaling, palette, readability, dither.
Game promotion with no art discussion gets removed or ignored; a process post about the art
does well. They are strict about integer scaling (blurry or mixed-scale images get called
out) and ban AI-generated art.

**Rules to know:**

- The image must be pixel art you made, shown at a whole-number scale (all of `assets/`
  passes the grid check).
- No AI art. Disclose that it's your game; promotion should be secondary to the art.
- Use the **OC** flair (or the game-art flair, if there is one).
- Store links usually belong in a comment, not the post body; check the current rule.

**When:** L+2, or any time; it's not a launch post.

**Title:**

> I made a whole game on one pixel grid: 475 x 334 canvas, flat colour, durability as a single blue ramp

**Image:** `assets/screens/zoom-1900x1336.png` and `screens/mid-1900x1336.png` (gallery), or a
short crisp GIF of blocks breaking with the dithered fog reveal.

**Body:**

> This is Golden Pixel, an iPhone game I made where everything is drawn into one 475 x 334
> canvas and shown at exactly 6 screen pixels per pixel on iPhone Duo. A few rules I held
> myself to:
>
> - **Flat:** one colour per surface. No highlights, shadows or bevels on blocks, balls or UI.
> - **Durability is lightness alone.** Blocks are one blue hue in a six-step ramp (#1d2c52 to
>   #b9d2ff). Each hit makes a block one step paler, with a one-frame white flash.
> - **No gradients:** the fog reveal dithers each cell in from black with an ordered Bayer
>   pattern.
> - **Reserved colours:** gold only for the golden pixel and coins, mint only for shards, so
>   they read instantly in a sea of blue.
> - **Type** is Pixel Operator 8 (CC0), 7-px caps; icons are 7 x 7 to match.
> - **Zoom** steps are 0.5x, 1x, 2x, 3x, 4x, and 0.5x is an exact every-other-pixel subsample,
>   so nothing ever goes soft.
>
> There's a test that renders every screen, scales it up and fails the build if any N x N
> block isn't one colour.
>
> Happy to talk palette or the dither. (It's free on the App Store if you want to see it
> move; link in the comments.)

**First comment:** `App Store: [LINK]. Free, no ads, no IAP.`

---

## TouchArcade forums

**Where:** the released iPhone and iPad games forum (check the current section names; there's
usually a separate one for upcoming games, which suits a pre-launch thread). One thread per
game; keep updating the same thread with news and builds.

**Title** (use the forum's convention if it has one, such as an `[iPhone]` tag):

> Golden Pixel: Idle Breaker, an idle brick breaker you dig through (free, no ads, no IAP)

**Body:**

> Hi TouchArcade, I'm the developer of Golden Pixel, out now on iPhone.
>
> **App Store:** [LINK]
> **Price:** Free. No ads, no in-app purchases.
> **Trailer:** [YOUTUBE LINK]
>
> Golden Pixel is an idle brick breaker drawn on a single pixel grid. Each level is a big map
> buried in fog. Hold an open spot and pull back like a slingshot to launch a ball; it
> bounces forever, breaking blue blocks whose shade shows how many hits they have left, and
> every break pushes the light further into the dark. Coins buy more balls, mint shards buy
> a skill tree of seven ball types, and somewhere in each level the golden pixel waits: the
> level's boss. Each gold you break is a permanent star.
>
> Made for the iPhone Duo's inner screen at its native pixel scale; plays on every iPhone in
> landscape.
>
> Screenshots below. I'll keep this thread updated and I'm reading every reply.

**Attach:** 3 to 4 images from `assets/screens/` (start, mid, tree, gold).
