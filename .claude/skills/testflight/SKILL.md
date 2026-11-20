---
name: testflight
description: Ship a Golden Pixel TestFlight build: preflight, commit and push to main, watch the TestFlight workflow, report the build number. Use when the user says "push to testflight", "deploy", "ship a build", "send it to my phone", or gives feedback on a build soon after a push.
---

# Ship a TestFlight build

A push to `main` runs the `TestFlight` workflow (`.github/workflows/testflight.yml`): core tests, `fastlane ios beta` (archive, sign, upload), then `fastlane ios status wait:900`. It takes about 10 min. The `CI` workflow (`ci.yml`) also runs on the push; it is separate and slower (~30 min), and the build does not wait for it.

Commit straight to `main`, no branch or PR. The user asking to ship is the ask to commit and push.

## 1. Preflight

Run from the repo root. Every check is green before you commit.

```sh
swift test
swift run -c release gp-render all build/render
```

Grid check needs Pillow. Make a venv in the session scratchpad once:

```sh
python3 -m venv "<scratchpad>/gp-venv" && "<scratchpad>/gp-venv/bin/pip" install --quiet pillow
"<scratchpad>/gp-venv/bin/python" tools/gridcheck.py build/render/*.png
```

If `App/` or `ios/` changed since `origin/main` (`git diff --name-only origin/main -- App ios` plus `git status --short -- App ios`), build the app for the simulator:

```sh
cd ios
xcodegen generate --quiet   # when project.yml changed or GoldenPixel.xcodeproj is missing
xcodebuild -project GoldenPixel.xcodeproj -scheme GoldenPixel \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/sim \
  CODE_SIGNING_ALLOWED=NO build -quiet
```

On a failure, fix it and rerun the failing check; ship nothing red.

## 2. Commit and push

- `git log --oneline origin/main..HEAD` (after `git fetch origin main`): commits already on local `main` ship with this push. Name them in the report.
- `git status --short`, then `git add` the paths that belong to this change by name. Other agents may have work in the tree; ask when ownership is unclear.
- Read `git diff --cached` after staging: it is what ships, and another session can edit a file between your review and your `git add`. For a hunk you did not review, `git restore --staged <path>` and ask, or stage what it depends on and rerun the preflight check it touches. Every path the staged `ios/project.yml` names is tracked or staged (`git ls-files --error-unmatch <path>`).
- Leave out `Gemfile.lock`, `.claude/worktrees/`, `build/`, `ios/build/`, `fastlane/.env*`, `*.p8` and anything else secret. Never print secrets.
- Conventional Commit message (`feat: ...`, `fix: ...`), then `git push origin main`. The pre-commit hook reruns `swift test` when `Core/` is staged.
- Batch related changes into one push: each push to `main` is a build.
- A push touching only `docs/**`, `site/**` or `.md` files anywhere (`**.md`, skills included) starts no build. To ship one anyway: `gh workflow run testflight.yml --ref main -f changelog="<what to test>"`.

## 3. Watch the run

Find the run for the pushed SHA in the foreground (it appears within seconds) and print its URL:

```sh
sha=$(git rev-parse HEAD)
until id=$(gh run list --workflow testflight.yml --commit "$sha" --json databaseId -q '.[0].databaseId') && [ -n "$id" ]; do sleep 5; done
gh run view "$id" --json databaseId,url -q '"\(.databaseId) \(.url)"'
```

Then watch it in one background Bash command (`run_in_background: true`) and wait for its exit notification instead of polling:

```sh
gh run watch <id> --exit-status --compact --interval 30
```

Runs share a non-cancelling concurrency group, so a new run can sit `pending` behind the previous one. Tell the user the run URL and that it takes ~10 min.

## 4. Report

**Success.** Read the build number and Apple's processing state from the log:

```sh
gh run view "$id" --log | grep -E 'Uploaded \*\*|Processing state.*\(20[0-9]{10}\)' | head -3
```

The build number (`CFBundleVersion`) is set in `fastlane/Fastfile` lane `beta`: the UTC time when the lane starts, `YYYYMMDDHHMM` (e.g. `202611201804`), passed to `ios/ios.sh archive` as `CURRENT_PROJECT_VERSION`. It is not the GitHub run number. Version is `MARKETING_VERSION` in `ios/project.yml` (e.g. `1.0.0`). Tell the user: "TestFlight shows `1.0.0 (<build>)`; the app shows the same build number." If the state is `VALID` it is installable now; if `PROCESSING`, Apple needs a few more minutes.

**Failure.** Run `gh run view "$id" --log-failed`, find the first real error (not the cascade after it), tell the user the step and the error in a sentence or two, and propose a fix. Common steps: `Check secrets` (missing ASC secret in the `testflight` environment), `Core tests`, `Build and upload` (signing or `Build N is not above the latest TestFlight build`: rerun a minute later with `gh run rerun "$id"`).

**Canceled.** The watch exits 1 and `gh run view "$id" --json conclusion` says `cancelled`: someone stopped it on purpose, usually another session that pushed a fix on top. Find the replacement with the run list in section 5. If a newer run's `headSha` contains your commit (`git merge-base --is-ancestor <your-sha> <headSha>`), read what the commits in between changed, watch that run and report its build. With no newer run, ask the user before rerunning.

## 5. Feedback after a push

The user often tests the previous build without realising. Before changing code for feedback that arrives soon after a push, find which build they are on:

```sh
gh run list --workflow testflight.yml --branch main --limit 5 \
  --json databaseId,headSha,status,conclusion,createdAt,displayTitle
```

Ask for (or read from their screenshot) the build number in TestFlight or the app, match it to a run (its `Uploaded **... (<build>)**` log line), and check whether the fix is in that build: `git merge-base --is-ancestor <fix-sha> <run-headSha>`. If it is not, say "you're on build X; the fix lands in build Y (ready ~HH:MM)" and change nothing. Only debug when the reported build already contains the fix.
