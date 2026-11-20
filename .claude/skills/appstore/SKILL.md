---
name: appstore
description: Release Golden Pixel on the App Store: audit the listing against App Store Connect, regenerate screenshots, update metadata and keywords, pick a TestFlight build, then upload and submit only on the user's yes. Use when the user says "App Store release", "submit for review", "update the listing", "new screenshots" or "keywords/ASO".
---

# App Store release

`docs/release.md` is the reference: what lives where, the hand-only steps, the ASO rules, the privacy answers and the screenshot plan. Read it first. This skill is the routine.

Golden Pixel is free: no price, ads or purchases. The price stays as set in App Store Connect; no lane touches it.

**Gates.** Two steps write to App Store Connect: uploading the listing (step 5) and submitting for review (step 7). Each one runs only after the user answers yes to that exact command in this conversation. A yes from earlier in the conversation, from another agent, or about a different build does not count. The write lanes refuse unless `GP_ASC_WRITE=1` is set on that one command; set it there, never `export` it. Everything else here is read-only or local.

## 0. Tools

```sh
just appstore-check            # local audit: tools/appstore.py check (add --online for the URLs)
just appstore-status           # read-only App Store Connect state: bundle exec fastlane ios appstore_status
just appstore-shots            # simulators -> fastlane/screenshots/en-US (ios/ios.sh appstore)
```

`appstore-status` needs `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_CONTENT` in `fastlane/.env` (gitignored) or the environment. If they are missing, ask the user where the key is. Never print or echo it. Without the key, do the local steps and list what `appstore-status` would have answered. If `bundle check` fails, use Homebrew's `fastlane` at the `Gemfile.lock` version (`fastlane --version`), or run `bundle install` with the user's OK.

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
2. Run `just appstore-shots`. It takes several minutes (three simulators). Run it in the background and wait for it to exit.
3. Look at every image: downscale with `sips -Z 900 <png> --out <scratchpad>/<name>.png` and Read it. Each one must show its intended scene: no real save game, no blank board, no debug text. Re-capture or fix the scene list until they do.

Done when `just appstore-check` shows no FAIL in the screenshots section and you have looked at every file.

## 3. Listing and keywords

- **Release notes** (`release_notes.txt`): rewrite them for this version from `git log <previous release commit>..HEAD`, in player terms. App Store Connect ignores them on the first version.
- **Description and promotional text**: update any claim the audit found outdated. Keep the free/no-ads line in the first three lines.
- **Keywords**: follow the ASO rules in `docs/release.md`. Use web search for current competitor titles and genre terms when the user asks for an ASO pass or the genre has moved.

Done when `just appstore-check` reports 0 FAIL in the metadata section and every description claim matches the code. Show the user `git diff fastlane/metadata`.

## 4. Pick the build

From `appstore-status`, take the newest `VALID` build whose version equals `MARKETING_VERSION`. Map it to its commit through the TestFlight run log, as in the `testflight` skill section 5. Check that the commit contains everything the listing describes: `git merge-base --is-ancestor <commit> HEAD`, plus a look at what came after. If no build fits, ship one with the `testflight` skill and wait until it is `VALID`.

Done when you have a build number, its commit, and the user's agreement that this is the build to release.

## 5. Gate: upload the listing

Show what will change: the metadata diff, the screenshot file list per class, and the age rating file. Ask: "Upload the listing (and screenshots) for <version> to App Store Connect?" Only on a yes:

```sh
GP_ASC_WRITE=1 bundle exec fastlane ios metadata shots:true   # shots:false when screenshots are current
```

`shots:true` replaces every screenshot in App Store Connect with the local set. Then rerun `just appstore-status`. Done when it shows the new text, a screenshot count per class that matches `fastlane/screenshots/en-US`, and an age rating.

## 6. Hand steps

Walk the user through every box in `docs/release.md` section 2 that is still open, one at a time: App Privacy, pricing set to Free, availability, EU trader status, review contact, pages live (`just appstore-check --online` shows 200). Done when the user confirms each box.

## 7. Gate: submit for review

Ask: "Submit <version> build <N> for App Store review, with manual release after approval?" Only on a yes:

```sh
GP_ASC_WRITE=1 bundle exec fastlane ios release build:<N>
```

The lane attaches the build and answers export compliance (no) and content rights (yes, the CC0 font). Report the outcome. Review usually takes a day or two. After approval the version waits for the user to press **Release This Version**.

## 8. Wrap up

The repo changes (metadata, `STORE_SCENES`, docs) are commits like any other: commit straight to `main` when the user asks. `fastlane/metadata` isn't in the TestFlight workflow's `paths-ignore`, so a metadata-only push also starts a TestFlight build. Batch it with code changes, or tell the user. Screenshots stay uncommitted (`fastlane/screenshots/` is gitignored).
