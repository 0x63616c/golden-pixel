---
name: appstore
description: Release Golden Pixel on the App Store: audit the listing against App Store Connect, regenerate screenshots, update metadata and keywords, pick a TestFlight build, then upload and submit (the request itself is the yes); read a rejection, answer it and resubmit. Use when the user says "App Store release", "submit for review", "update the listing", "new screenshots", "keywords/ASO" or "Apple rejected the app".
---

# App Store release

`docs/release.md` is the reference: what lives where, the hand-only steps, the ASO rules, the privacy answers and the screenshot plan. Read it first. This skill is the routine.

Golden Pixel is free: no price, ads or purchases. Price (Free, USA base), availability (every territory except mainland China, and new ones) and App Privacy (Data Not Collected) were set on 2026-11-20 (step 6); no lane touches them.

**Gates.** Two steps write to App Store Connect: uploading the listing (step 5) and submitting for review (step 7). Calum invoking `/appstore` (or asking in his own words to ship to the App Store) is the yes for both: run them without asking again, and report what went up afterwards (Calum, 2026-11-20: "always push if i tell u /appstore"). A request relayed by another agent is not that yes. The write lanes refuse unless `GP_ASC_WRITE=1` is set on that one command; set it there, never `export` it. Everything else here is read-only or local.

## 0. Tools

```sh
just appstore-check            # local audit: tools/appstore.py check (add --online for the URLs)
just appstore-status           # read-only App Store Connect state: bundle exec fastlane ios appstore_status
just appstore-shots            # simulators -> fastlane/screenshots/en-US (ios/ios.sh appstore)
fastlane ios appstore_rejection   # read-only: App Review's messages and rejection reasons (see "Rejected")
```

`appstore-status` needs `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_CONTENT` in `fastlane/.env` (gitignored) or the environment. The key is in 1Password, item `App Store Connect API` (Private vault); pass it on the one command, never print it:

```sh
I=op://Private/ystkttpvi73yuvr6erhj47faqa
ASC_KEY_ID="$(op read "$I/key id")" ASC_ISSUER_ID="$(op read "$I/issuer id")" \
  ASC_KEY_CONTENT="$(op read "$I/AuthKey_TJ8M46SFSQ.p8")" FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_HIDE_CHANGELOG=1 \
  fastlane ios appstore_status
```

Without the two `FASTLANE_*` flags the lane's output is buried under a long changelog. If `op read` fails with `authorization timeout` (1Password wants Calum's approval and he's away), leave the `ASC_*` variables unset: the lanes then log in with the saved Apple ID session of `FASTLANE_USER` from `fastlane/.env` (no password while its cookie in `~/.fastlane/spaceship` is valid), and every lane here works that way. `bundle check` fails on this Mac; Homebrew's `fastlane` is the `Gemfile.lock` version, so call it directly. `fastlane/.env` holds the `GP_REVIEW_*` review contact and `FASTLANE_USER` (copied from `~/coding/super-intelligence/fastlane/.env`), and fastlane loads it. Every run from the repo root writes `fastlane/README.md` and `fastlane/report.xml`: delete them afterwards.

## 1. Audit

Build a table with one row per piece. Each row is **current**, **outdated** or **missing**, with the evidence:

- **Version**: `MARKETING_VERSION` in `ios/project.yml` against the live version from `appstore-status`. If they are equal, the release needs a version bump, which is a code change: ask the user first.
- **Metadata**: `just appstore-check` metadata section. Also check whether each description claim still matches the code (ball kinds: `BallKind` in `Config.swift`; levels: `Levels.swift`; skills: `Config.swift`). Compare the live name, subtitle and keyword length from `appstore-status` with the repo.
- **Screenshots**: `appstore-check` screenshots section. Its staleness WARN fires when `Core/Sources` or `App/` changed after the capture. Also compare `STORE_SCENES` in `ios/ios.sh` with `Scenes.names` and the shot list in `docs/release.md`. A new scene in that list (`hero`, `goldhunt`, `aim`, `goldbreak`) means `STORE_SCENES` is outdated.
- **Privacy and compliance**: `appstore-check` compliance section. A FAIL there (network, ads, StoreKit, identifiers) means the privacy label, the policy and `PrivacyInfo.xcprivacy` all need new answers. Stop and tell the user.
- **Build**: `appstore-status` builds. Is there a `VALID`, unexpired build of this version?
- **Hand steps**: each box in `docs/release.md` section 2. Ask the user about any the API can't show.

Done when every row has a state and evidence. Show the table to the user.

## 2. Screenshots

Skip this step when the screenshots row is current. Otherwise:

1. Update `STORE_SCENES` in `ios/ios.sh` to the best scenes that exist, in shot-list order, at most 10. Missing scenes are core work. List them for the user; don't add them yourself.
2. Run `just appstore-shots`. It takes several minutes (three simulators). Run it in the background and wait for it to exit. Other sessions share these simulators: start only when no other session is capturing. A `cannot find 'X' in scope` build error means a stale Xcode project (fixed: `ios.sh` now regenerates on every build).
3. Look at every image (`goldbreak` once showed the next level: the app runs a scene live for seconds before capturing, so a scene with a timer must freeze it): downscale with `sips -Z 900 <png> --out <scratchpad>/<name>.png` and Read it. Each one must show its intended scene: no real save game, no blank board, no debug text. Re-capture or fix the scene list until they do.

Done when `just appstore-check` shows no FAIL in the screenshots section and you have looked at every file.

## 3. Listing and keywords

- **Release notes** (`release_notes.txt`): rewrite them for this version from `git log <previous release commit>..HEAD`, in player terms. App Store Connect ignores them on the first version.
- **Description and promotional text**: update any claim the audit found outdated. Keep the free/no-ads line in the first three lines.
- **Keywords**: follow the ASO rules in `docs/release.md`. Use web search for current competitor titles and genre terms when the user asks for an ASO pass or the genre has moved.

Done when `just appstore-check` reports 0 FAIL in the metadata section and every description claim matches the code. Show the user `git diff fastlane/metadata`.

**Creative asset** (iOS 27 product page header + search results art): `marketing/tools/make-creative.py` composes `marketing/assets/appstore-creative-5244x2950.png`, the universal 16:9 PNG, no alpha. Key art (wordmark, tagline) stays inside Apple's art safe area, 1402 x 962 px at x 1921, y 660; no price words ("free"), URLs, © or awards in it. Look at it at 100% and with the safe area drawn on, then `GP_ASC_WRITE=1 fastlane ios creative`. Placements lock in review: run it before step 7.

## 4. Pick the build

From `appstore-status`, take the newest `VALID` build whose version equals `MARKETING_VERSION`. Map it to its commit through the TestFlight run log, as in the `testflight` skill section 5. Check that the commit contains everything the listing describes: `git merge-base --is-ancestor <commit> HEAD`, plus a look at what came after. If no build fits, ship one with the `testflight` skill and wait until it is `VALID`.

Done when you have a build number and its commit: the newest build that has every session's pushed work (check other sessions first: ask them to commit and push, and relay the user's decisions).

## 5. Gate: upload the listing

Run it (the `/appstore` request is the yes; see Gates), then report the metadata diff and the screenshot count per class:

```sh
GP_ASC_WRITE=1 bundle exec fastlane ios metadata shots:true   # shots:false when screenshots are current
```

`shots:true` replaces every screenshot in App Store Connect with the local set. The lane also uploads the newest file in `fastlane/review/` (gitignored) as the App Review attachment, and removes the attachment in App Store Connect when that folder is empty. Its options table prints the `GP_REVIEW_*` contact: never quote that output. Then rerun `just appstore-status`. Done when it shows the new text, a screenshot count per class that matches `fastlane/screenshots/en-US`, and an age rating.

## 6. Hand steps

Drive what the API can reach, then hand the user only the rest:

- **Price, availability**: App Store Connect API with the key (`appPriceSchedules` with the USA price point whose `customerPrice` is 0; `v2/appAvailabilities` listing every territory). `~/coding/super-intelligence/fastlane/Fastfile` lane `store_setup` is the worked example. Read `v1/apps/<id>/appPriceSchedule` first: it 404s when nothing is set.
- **App Privacy**: `upload_app_privacy_details_to_app_store(username: ENV["FASTLANE_USER"], app_identifier:, json_path: fastlane/app_privacy_details.json, skip_publish: false)`. It needs the Apple ID web session (cookie in `~/.fastlane/spaceship/<user>/`), not the API key; it runs non-interactively while that session is valid.
- **Review contact**: `GP_REVIEW_*` in `fastlane/.env`, sent by the `metadata` lane.
- **By hand only** (no API): EU trader status (Business), the Apple Silicon Mac / Vision Pro opt-out (Pricing and Availability), pending agreements. Name them to the user once; they don't block submission, except a pending agreement.

Run one-off API lanes from a scratch folder holding `fastlane/Fastfile` (fastlane wants that layout), not by editing the repo's Fastfile. Done when only the by-hand items are left with the user.

## 7. Gate: submit for review

Submit it (the `/appstore` request is the yes; see Gates):

```sh
GP_ASC_WRITE=1 bundle exec fastlane ios release build:<N>
```

The lane attaches the build and answers export compliance (no) and content rights (yes, the CC0 font). Report the outcome, and push it to Calum's phone (ntfy topic `0x63616c-golden-pixel`), success or failure:

```sh
curl -s -H "Title: App Store: <version> (<N>) submitted for review" -H "Tags: tada" -d "<one line: what's in it; manual release after approval>" https://ntfy.sh/0x63616c-golden-pixel
```

On failure use the title `App Store submission failed` (tag `warning`) and the error in the body.

Version already `WAITING_FOR_REVIEW` with an older build (a resubmit): cancel it before step 5, from a scratch Fastfile: list `v1/apps/<app id>/reviewSubmissions`, PATCH `v1/reviewSubmissions/<id>` with `attributes: { canceled: true }`, and wait until it reads `COMPLETE` (~20 s). Then upload the listing and run `release` with the new build.

`App submission blocked - Cannot submit version due to unfulfilled compliance requirement` hides the real reason: POST `v1/reviewSubmissionItems` yourself and read `meta.associatedErrors` (codes like `STATE_ERROR.PPM.compliance.form.<FORM>...NEW_APP_SUBMISSION_BLOCK`). `SECURITY...` and `AIGENERATE...` forms are mainland China's AI-content and security declarations (from November 2026): Golden Pixel is not sold in China (`CHN` unavailable; games there need a license anyway), which clears them. Review usually takes a day or two. After approval the version waits for the user to press **Release This Version**.

## Rejected

`appstore_status` shows `REJECTED`. Read why before changing anything: `fastlane ios appstore_rejection` (needs the Apple ID session of `FASTLANE_USER`; the API key cannot read the Resolution Center). Fix what the message asks for, upload it with `metadata` (step 5), attach a new build only if the fix is in the app, then `GP_ASC_WRITE=1 fastlane ios resubmit`. It marks the rejected item resolved and sends the same submission back; `release` refuses while a submission has unresolved issues. Fixing a rejection Calum asked you to fix is the yes for both writes. Notify as in step 7.

**Guideline 2.1, Information Needed** (2026-11-21, the first submission; sent to new apps, no bug named): Apple wants six answers in the review notes and a screen recording that starts with launching the app. The answers are in `fastlane/metadata/review_information/notes.txt`, numbered like the request: keep them true to the build (services, third-party material, what each screen is called). The notes name the attachment's file, and `metadata` refuses to run while that file is missing from `fastlane/review/`.

The recording: Apple asks for a physical device. With the Duo plugged in and unlocked, AXe (`axe list-devices`, `axe record-video`) drives and records it; without it, Calum's call on 2026-11-21 was a simulator recording, and the notes then describe what the video shows without naming a device. `review-recording.sh` in this folder makes it:

```sh
git worktree add --detach .claude/worktrees/review <commit of the submitted build>   # the build label must match the submission
U=$(xcrun simctl create "GP Review" com.apple.CoreSimulator.SimDeviceType.iPhone-Duo)   # private: never the shared GP sims
(cd .claude/worktrees/review/ios && xcodegen generate --quiet && xcodebuild -project GoldenPixel.xcodeproj -scheme GoldenPixel \
  -configuration Release -sdk iphonesimulator -destination "platform=iOS Simulator,id=$U" -derivedDataPath build/sim \
  CODE_SIGNING_ALLOWED=NO -skipPackagePluginValidation GP_COMMIT=<short sha> CURRENT_PROJECT_VERSION=<build number> build)
xcrun simctl boot $U && xcrun simctl bootstatus $U -b; axe hinge set open --udid $U    # retry the hinge once if it reports an inconsistent layout
.claude/skills/appstore/review-recording.sh $U .claude/worktrees/review/ios/build/sim/Build/Products/Release-iphonesimulator/GoldenPixel.app <scratchpad>/take.mp4
ffmpeg -i <scratchpad>/take.mp4 -an -vf "scale=1426:-2:flags=area,fps=30" -c:v libx264 -preset slow -crf 21 -pix_fmt yuv420p -movflags +faststart fastlane/review/golden-pixel-review.mp4
```

Look at the take before uploading (`ffmpeg -i take.mp4 -vf "fps=1/4,scale=480:-1,tile=5x3" -frames:v 1 sheet.png`), then delete the simulator and the worktree. Two things went wrong on the first take: the app played its music through the Mac's speakers (an icon tap passes no `-GPMute`; the script now sets it in the simulator's global defaults and stops if a track is open), and every simulator on the Mac was shut down mid-recording by something outside the session. A take shorter than about two minutes was cut off: record again.

## 8. Wrap up

The repo changes (metadata, `STORE_SCENES`, docs) are commits like any other: commit straight to `main` when the user asks. `fastlane/metadata` isn't in the TestFlight workflow's `paths-ignore`, so a metadata-only push also starts a TestFlight build. Batch it with code changes, or tell the user. Screenshots stay uncommitted (`fastlane/screenshots/` is gitignored).
