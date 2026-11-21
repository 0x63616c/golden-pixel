# App Store release

The checklist and reference for putting Golden Pixel on the App Store. The routine that runs it
is the `appstore` skill (`.claude/skills/appstore/SKILL.md`); TestFlight builds are separate
(`docs/ios.md`, the `testflight` skill).

Golden Pixel is **free**: no price, no ads, no in-app purchases, no accounts, no data collected.

## 1. Prepared in the repo

| Piece | Where | Notes |
| --- | --- | --- |
| Listing text | `fastlane/metadata/en-US/*.txt` | name, subtitle, keywords, promotional text, description, release notes, support/marketing/privacy URLs |
| Categories, copyright | `fastlane/metadata/*.txt` | Games > Casual + Action; secondary Entertainment |
| Review notes | `fastlane/metadata/review_information/notes.txt` | contact details come from `GP_REVIEW_*` in `fastlane/.env` or are entered once by hand |
| Age rating answers | `fastlane/app_rating_config.json` | all "None"/"No": expect **4+** |
| Privacy label answers | `fastlane/app_privacy_details.json` | "Data Not Collected" (entered by hand, see section 2) |
| Privacy manifest | `ios/PrivacyInfo.xcprivacy` (in `project.yml`) | no tracking, no data; UserDefaults `CA92.1`, boot-time clock `35F9.1` |
| Export compliance | `ios/Info.plist` `ITSAppUsesNonExemptEncryption = false` | no custom crypto, no network |
| Privacy policy, support pages | `site/privacy.md`, `site/support.md` (`site/privacy.html` is a styled copy) | live once pushed to `main` (GitHub URLs in the metadata) |
| Screenshots | `ios/ios.sh appstore` → `fastlane/screenshots/en-US` (gitignored) | `STORE_SCENES` in `ios/ios.sh`; `tools/appstore.py shots` names, orders and strips alpha |
| Audit | `just appstore-check` (`tools/appstore.py check`) | limits, ASO rules, screenshot sizes/alpha/staleness, privacy, compliance |
| Lanes | `fastlane/Fastfile` | `appstore_status` (read-only), `metadata` and `release` (write, need `GP_ASC_WRITE=1`) |

## 2. By hand, in App Store Connect / Apple Developer

Things the API key can't do, or that only the account holder should decide. Do each one once;
the skill asks about any it can't verify.

- [ ] **Agreements**: Business > Agreements: accept any pending Apple Developer Program License
      Agreement update (a pending one blocks submission). A free app needs **no** Paid Apps
      agreement, tax forms or banking.
- [ ] **EU trader status (Digital Services Act)**: App Store Connect > Business (or the app's
      App Information): declare trader or non-trader. Without it the app can't go on sale in the
      EU. Trader status publishes an address, phone and email on the product page.
- [x] **Pricing and Availability**: price **Free** (USD 0.00, the old tier 0), set by API on
      2026-11-20; every country except mainland China (its AI-content and security forms block
      submission, and games there need a license). Untick **iPhone and iPad apps on Apple Silicon Macs** and **Apple Vision Pro**:
      the game needs touch and a whole-number pixel scale. Leave pre-orders off.
- [x] **App Privacy** (published by fastlane on 2026-11-20): set the Privacy Policy URL (`fastlane/metadata/en-US/privacy_url.txt`),
      then Get Started > "No, we do not collect data from this app" > Publish. (fastlane's
      `upload_app_privacy_details_to_app_store` needs an Apple ID login, not the API key, so this
      stays manual. It's one click.)
- [ ] **Age rating**: uploaded by the `metadata` lane; open App Information > Age Rating and
      confirm it shows **4+** and "Made for Kids" is off.
- [ ] **App Review contact**: first and last name, email and phone in the version's App Review
      Information (or `GP_REVIEW_FIRST_NAME`, `GP_REVIEW_LAST_NAME`, `GP_REVIEW_EMAIL`,
      `GP_REVIEW_PHONE` in `fastlane/.env`). Sign-in required: **off**.
- [ ] **Publish the pages**: commit and push `site/privacy.md` and `site/support.md`, then
      `just appstore-check --online` must show the URLs as 200. Optional nicer URLs: GitHub Pages
      (repo Settings > Pages) and update the three `*_url.txt` files.
- [ ] **Copyright** (`fastlane/metadata/copyright.txt`): make it match the seller name on the
      developer account.
- [ ] **Local API key** for the skill: `fastlane/.env` (gitignored) with `ASC_KEY_ID`,
      `ASC_ISSUER_ID`, `ASC_KEY_CONTENT`, the same key the `testflight` environment holds.
      GitHub secrets can't be read back, so take it from where you stored the `.p8`.
- [ ] **After approval**: the version waits in "Pending Developer Release". Press **Release This
      Version** when ready (the `release` lane submits with manual release).

## 3. Run the skill

Ask for an App Store release (`/appstore`). It audits what exists against App Store Connect,
regenerates screenshots, updates the listing and checks it, picks a TestFlight build, and asks
before each write: once to upload the listing and screenshots, once to submit for review.

---

## Reference

### Name, subtitle, keywords

| Option | Name (≤30) | Subtitle (≤30) | Why |
| --- | --- | --- | --- |
| **Chosen** | `Golden Pixel: Idle Breaker` (26) | `Bricks, Balls & Buried Gold` (27) | Name carries the brand plus the genre ("idle", "breaker"), the strongest-weighted field. Subtitle adds "bricks", "balls", "gold" and reads as a hook. Already the setup lane's first fallback name. |
| Brand only | `Golden Pixel` (12) | `Idle Brick Breaker in the Dark` (30) | Cleanest brand, matches the home-screen name; genre terms move to the weaker subtitle. |
| Brick-first | `Golden Pixel - Brick Breaker` (28) | `Idle balls dig through the fog` (30) | Targets "brick breaker" exactly; "idle" drops to the subtitle. |

No App Store app is called "Golden Pixel" (searched 2026-11-20; nearest: "Gold Pixel Miner -
Boss Battle", "Golden Stones"). The App Store Connect record already holds the name.

Keywords (`keywords.txt`, 97/100): `breakout,incremental,clicker,arcade,retro,8bit,dig,miner,cave,offline,block,bounce,smash,foldable`.

Rules (`tools/appstore.py check` enforces the mechanical ones):

- Apple combines words across name, subtitle and keywords, so never repeat a word from the name
  or subtitle; plurals are matched for you ("brick" would waste space next to "Bricks").
- Commas only, no spaces. Use the space up.
- No pricing words ("free", "sale") in name, subtitle or keywords: guideline 2.3.7. Say "free"
  in the promotional text and description instead (both do).
- No competitor names or Apple trademarks. "foldable" is fair: the game is built for iPhone Duo.
- Competitors seen: Idle Brick Breaker - Breakout, Idle Breaker, Idle Brix, Brick Inc.,
  Endless Brick Breakout, Idle Balls.

The description's first three lines are what shows before "more": a hook, the one-line pitch,
and "No ads. No in-app purchases. No accounts. No tracking." Every claim must match the code
(ball kinds: `BallKind` in `Config.swift`; levels: `Levels.swift`). Nothing happens while the app is closed:
don't promise offline earnings.

### Privacy and compliance answers

| Question | Answer | Why |
| --- | --- | --- |
| App Privacy: data collected? | **No** ("Data Not Collected") | No network code, no analytics, ads or SDKs; the save is `Application Support/golden-pixel/save.json` on device (`App/GameHost.swift`). `tools/appstore.py check` greps for APIs that would change this. StoreKit is used once, to ask for a rating (`App/Rating.swift`: Apple's prompt and a link to the review page); it sells and reads nothing, and the check fails on any purchase API. |
| Tracking / IDFA | No | No AdSupport or AppTrackingTransparency; `NSPrivacyTracking = false`. |
| Export compliance | No non-exempt encryption | `ITSAppUsesNonExemptEncryption = false`; the app makes no network calls. |
| Content rights: third-party content? | **Yes, with rights** | The Pixel Operator 8 font is CC0 (`tools/fonts/PixelOperator-LICENSE.txt`), and so is every music track (`docs/music.md`). Set in the `release` lane. |
| Age rating | Every content question None/No; no ads, UGC, chat, web access, gambling, contests, loot boxes or parental controls | Result: 4+. |
| Made for Kids | No | General-audience game. |
| Sign-in for review | Not needed | No accounts. |

### Screenshots

Requirements (App Store Connect Help, "Screenshot specifications", checked 2026-11-20). PNG or
JPEG, no alpha, 1 to 10 per class. Landscape sizes:

| Simulator (`ios.sh`) | Class (fastlane) | Size | Status |
| --- | --- | --- | --- |
| `iphone` (iPhone 18 Pro) | Dynamic Island medium, 6.3" (`APP_IPHONE_61`) | 2622 x 1206 | **Required** |
| `max` (iPhone 18 Pro Max) | Dynamic Island large, 6.9" (`APP_IPHONE_67`) | 2868 x 1320 | Required unless 6.5" Face ID shots are given (this covers it) |
| `duo` inner | iPhone Duo (`APP_IPHONE_DUO`) | 2853 x 2007 | Optional; adds the "made for iPhone Duo" badge; **required from April 2027** for apps built with the iOS 27.1 SDK or later (we use Xcode 27.2) |
| `duo` outer (cover) | iPhone Duo (`APP_IPHONE_DUO`) | 2034 x 1398 | Same date. Needs a folded capture: today `capture` unfolds the Duo, so the cover screen is black and `appstore.py shots` skips it |

fastlane 2.241.2 (the `Gemfile.lock` version) knows all four sizes. Files are named
`<sim>_<NN>_<scene>.png`; deliver groups them by size and keeps the name order.

Shot list (first one or two carry the page). Today's `STORE_SCENES` uses the scenes that exist:
`late zoomout tree sheet mid menu`. The target list needs new staged scenes in
`Core/Sources/GoldenPixelCore/Scenes.swift` (a core change):

| # | Scene | Shows | Caption idea | Exists? |
| --- | --- | --- | --- | --- |
| 1 | `hero` | late game, all ball types, camera on an active dig face (pale-to-deep blue blocks, a "+1 SHARD" banner), no walls filling half the board | Break the dark, one pixel at a time | New: `late` re-framed |
| 2 | `goldhunt` | the golden pixel on screen, part drained, Radar box round it, balls on it | Find the golden pixel | New |
| 3 | `aim` | slingshot: ghost ball and aim dots clearly visible in open space, row lit | Hold, pull back, launch | New: `launch` doesn't show the aim clearly |
| 4 | `zoomout` | 0.5x: the lit pocket in the fog | Light spreads with every break | Yes |
| 5 | `tree` | the skill tree with a card open | Grow a skill tree | Yes |
| 6 | `sheet` | a ball's info card | Seven balls to unlock | Yes |
| 7 | `goldbreak` | the moment the gold breaks (today's `gold` shows the next level's empty start) | Break the gold, go deeper | New |
| 8 | `menu` | title screen | — | Yes, but see below |

Other screenshot fixes, all outside this repo's release tooling:

- **Build label**: `App/GameHost.swift` sets the real build label over every staged scene, so
  `menu` shows "1.0.0 (N) commit". Store shots want no label: a launch flag (e.g. `-GPStore 1`)
  that leaves it empty.
- **Cover screen**: fold the Duo (hinge) before capturing display 1, for the outer set.
- **Captions**: none for now. If wanted, draw them in the canvas in Pixel Operator 8 (a
  staged-scene caption band), so they stay on the pixel grid. Never add them as a soft overlay.
