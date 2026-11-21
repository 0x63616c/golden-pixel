#!/usr/bin/env bash
# Build, install and launch the native iOS app. Used by the justfile and CI:
#   ios/ios.sh project                 regenerate GoldenPixel.xcodeproj from project.yml
#   ios/ios.sh sim [duo|iphone|max]    build + run on a simulator (default: the iPhone Duo)
#                                      muted (-GPMute); SOUND=1 for music and effects
#   ios/ios.sh device [debug]          build (Release by default) + install + launch on a USB/Wi-Fi iPhone
#   ios/ios.sh archive <build>         archive + export an App Store .ipa into ios/build/export
#                                      (CI: signs with the App Store Connect API key in ASC_KEY_PATH)
#   ios/ios.sh shots <out-dir> [sim]   simulator screenshots + a short recording of staged scenes
#   ios/ios.sh compare <out-dir> [sim...]   the same screenshots on every simulator (default: duo
#                                      iphone max), one folder each, plus side-by-side sheets
#   ios/ios.sh appstore [raw-dir]      App Store screenshots: STORE_SCENES on duo, iphone and max,
#                                      raw captures in raw-dir (build/appstore), deliver-ready
#                                      files in fastlane/screenshots/en-US (tools/appstore.py shots)
# Simulators: duo = iPhone Duo (the target), iphone = iPhone 18 Pro, max = iPhone 18 Pro Max;
# and the smallest screens, se = iPhone SE (3rd generation), mini = iPhone 13 mini.
# Pick a specific phone with DEVICE=<name or UDID> (see `xcrun devicectl list devices`).
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")" && pwd)"
CALLER_DIR=$PWD
cd "$IOS_DIR"
BUNDLE_ID=co.worldwidewebb.goldenpixel
SIM_NAME="GP Duo"
SIM_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo
# The staged scenes every screenshot run captures (see Scenes.names in the core).
SHOT_SCENES=(menu start mid zoom zoomout sheet launch pause late full tree gold howto settings levelselect)
# The App Store screenshots, in listing order (the first one or two carry the page; at most 10).
# The appstore skill keeps this list current; see docs/release.md for the shot plan.
STORE_SCENES=(hero aim goldhunt tree goldbreak sheet menu)

# An output folder as the caller meant it: relative paths are relative to where they ran us.
outdir() { [[ "$1" = /* ]] && echo "$1" || echo "$CALLER_DIR/$1"; }

# Picks the simulator the following steps use, by short name.
use_sim() {
  local types=com.apple.CoreSimulator.SimDeviceType
  case "$1" in
    duo) SIM_NAME="GP Duo"; SIM_TYPE=$types.iPhone-Duo ;;
    iphone) SIM_NAME="GP iPhone"; SIM_TYPE=$types.iPhone-18-Pro ;;
    max) SIM_NAME="GP Max"; SIM_TYPE=$types.iPhone-18-Pro-Max ;;
    se) SIM_NAME="GP SE"; SIM_TYPE=$types.iPhone-SE-3rd-generation ;;
    mini) SIM_NAME="GP mini"; SIM_TYPE=$types.iPhone-13-mini ;;
    *) die "Unknown simulator '$1' (duo, iphone, max, se or mini)" ;;
  esac
}

# Run a command with a time limit (macOS has no `timeout`).
limit() { local secs=$1; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }

say() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mxx  %s\033[0m\n' "$*" >&2; exit 1; }

# Run xcodebuild quietly; on failure, show the errors and explain the common signing problems.
xbuild() {
  local log; log=$(mktemp)
  if [[ -n "${CI:-}" ]]; then
    # CI: stream the interesting lines so a slow or stuck build is visible in the log.
    set +e
    xcodebuild "$@" 2>&1 | tee "$log" | grep --line-buffered -E "error:|\*\* |Resolve Package|Fetching|CompileSwift.*GoldenPixel"
    local rc=${PIPESTATUS[0]}
    set -e
    if [[ $rc -eq 0 ]]; then rm -f "$log"; return; fi
  elif xcodebuild "$@" >"$log" 2>&1; then rm -f "$log"; return; fi
  grep -E "error:|BUILD FAILED|ARCHIVE FAILED|EXPORT FAILED" "$log" | sort -u | head -40 >&2
  if grep -q "No Accounts" "$log"; then
    die "Xcode isn't signed in to your Apple account (Xcode > Settings > Accounts, team X9E4HG27NK)."
  elif grep -q "No profiles for\|requires a provisioning profile" "$log"; then
    die "No provisioning profile. Locally: plug in the phone and run once from Xcode. CI: the API key needs the Admin role for cloud signing."
  fi
  tail -80 "$log" >&2
  die "xcodebuild failed. Full log: $log"
}

project() {
  command -v xcodegen >/dev/null || die "xcodegen not found (brew install xcodegen)"
  xcodegen generate --quiet
}

# Short commit for the in-app build label (Info.plist GPCommit), "+" if tracked files have
# uncommitted changes; "dev" outside a git checkout.
commit() {
  local sha; sha=$(git -C "$IOS_DIR" rev-parse --short=7 HEAD 2>/dev/null) || { echo dev; return; }
  [[ -z $(git -C "$IOS_DIR" status --porcelain --untracked-files=no 2>/dev/null) ]] || sha+="+"
  echo "$sha"
}

# Always regenerate: sources are globbed, so a new file (App/Music.swift) changes the project
# without touching project.yml. It takes about a second.
ensure_project() { project; }

# Simulators play through the Mac's speakers: launch muted unless SOUND=1.
mute_flag() { [[ "${SOUND:-}" == 1 ]] || echo "-GPMute YES"; }

sim_udid() {
  local udid
  udid=$(xcrun simctl list devices available -j | python3 -c "
import json,sys
for devs in json.load(sys.stdin)['devices'].values():
    for d in devs:
        if d['name'] == '$SIM_NAME': print(d['udid']); sys.exit()")
  [[ -n "$udid" ]] || udid=$(xcrun simctl create "$SIM_NAME" "$SIM_TYPE")
  [[ -n "$udid" ]] || die "Could not create a $SIM_TYPE simulator (xcrun simctl list devicetypes)"
  echo "$udid"
}

build_sim() {
  ensure_project
  local udid=$1
  xbuild -project GoldenPixel.xcodeproj -scheme GoldenPixel -configuration Debug -sdk iphonesimulator \
    -destination "platform=iOS Simulator,id=$udid" -derivedDataPath build/sim CODE_SIGNING_ALLOWED=NO \
    -skipPackagePluginValidation GP_COMMIT="$(commit)" build
}

sim() {
  use_sim "${1:-${SIM:-duo}}"
  local udid; udid=$(sim_udid)
  say "Building for simulator $SIM_NAME ($udid)"
  build_sim "$udid"
  boot_sim "$udid"
  # Bring Simulator up on this device (not whichever one it showed last).
  open -a "Simulator" --args -CurrentDeviceUDID "$udid" 2>/dev/null || true
  # A booted Duo starts folded with the inner screen black; unfold it flat.
  [[ "$SIM_TYPE" == *Duo* ]] && unfold "$udid"
  xcrun simctl install "$udid" build/sim/Build/Products/Debug-iphonesimulator/GoldenPixel.app
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" ${SCENE:+-GPScene "$SCENE"} $(mute_flag)
}

# Boots the simulator, retrying from a clean shutdown once; first boots on CI runners are flaky.
boot_sim() {
  local udid=$1 try
  for try in 1 2 3; do
    xcrun simctl boot "$udid" 2>/dev/null || true
    if limit 240 xcrun simctl bootstatus "$udid" -b; then return; fi
    say "Boot attempt $try timed out; shutting down and retrying"
    limit 60 xcrun simctl shutdown "$udid" 2>/dev/null || true
    [[ $try -eq 2 ]] && { limit 60 xcrun simctl erase "$udid" || true; }
  done
  die "Simulator didn't boot after 3 attempts"
}

# simctl has no fold control, so use the hinge CLI (MIT, pinned) to unfold the Duo simulator.
HINGE_REPO=https://github.com/artemnovichkov/hinge.git
HINGE_SHA=06cb720276281da7f1aadd3874acb0d0ae5eb2b5
unfold() {
  local dir=build/tools/hinge
  if [[ ! -x "$dir/bin/hinge" ]]; then
    rm -rf "$dir"; mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" fetch -q --depth 1 "$HINGE_REPO" "$HINGE_SHA"
    git -C "$dir" checkout -q FETCH_HEAD
  fi
  say "Unfolding the Duo flat"
  HINGE_DEVICE=$1 limit 120 "$dir/bin/hinge" open || say "hinge open failed; screenshots may be black"
  sleep 4
  HINGE_DEVICE=$1 limit 60 "$dir/bin/hinge" posture || true
}

shots() {
  local out; out=$(outdir "${1:-build/shots}")
  use_sim "${2:-${SIM:-duo}}"
  capture "$out" record
}

# The same scenes on several simulators, one folder each, then tools/compare.py stacks them
# into one sheet per scene (at 1 px per point, so the phones keep their relative sizes).
compare() {
  local out; out=$(outdir "${1:-build/compare}")
  [[ $# -gt 0 ]] && shift
  local sims=("$@") s
  [[ ${#sims[@]} -gt 0 ]] || sims=(duo iphone max)
  for s in "${sims[@]}"; do use_sim "$s"; done   # reject a bad name before the first build
  for s in "${sims[@]}"; do
    use_sim "$s"
    capture "$out/$s"
    # What the glass hides: the screen's outline (the mask as alpha) and the safe area the
    # app saw (PixelView writes it for staged scenes). Both go next to the folder, not in it.
    local udid; udid=$(sim_udid)
    local display=""; [[ "$SIM_TYPE" == *Duo* ]] && display=3
    limit 30 xcrun simctl io "$udid" screenshot --mask=alpha ${display:+--display=$display} "$out/$s.mask.png" || true
    cp "$(xcrun simctl get_app_container "$udid" "$BUNDLE_ID" data)/Library/Application Support/golden-pixel/safe-area.json" \
      "$out/$s.safe-area.json" 2>/dev/null || say "No safe-area.json from $SIM_NAME"
  done
  local py=(python3)
  command -v uv >/dev/null && py=(uv run --quiet --with pillow python3)
  "${py[@]}" ../tools/compare.py "$out" "${sims[@]}"
  # Grid check at each phone's own scale (2 points per art pixel; the safe-area file carries
  # the points). The corners (the screen's mask) and the system's insets (the island, the
  # home indicator) are not the game's pixels.
  for s in "${sims[@]}"; do
    say "Grid check: $s"
    local skip=()
    [[ -f "$out/$s.safe-area.json" ]] && skip=(--safe-area "$out/$s.safe-area.json")
    "${py[@]}" ../tools/gridcheck.py --corner 120 ${skip[@]+"${skip[@]}"} "$out/$s"/*.png
  done
}

# App Store screenshots: STORE_SCENES on the Duo (inner screen; optional until April 2027, adds
# the Duo badge), the iPhone 18 Pro (6.3", required) and the 18 Pro Max (6.9", required), then
# tools/appstore.py arranges them for fastlane deliver. Uploading is a separate, gated step.
appstore() {
  local out; out=$(outdir "${1:-build/appstore}")
  local known scene sim
  known=$(sed -n '/static let names/,/]/p' ../Core/Sources/GoldenPixelCore/Scenes.swift)
  for scene in "${STORE_SCENES[@]}"; do
    # An unknown scene name launches the real game with the simulator's save: refuse early.
    grep -q "\"$scene\"" <<<"$known" || die "STORE_SCENES: '$scene' is not in Scenes.names"
  done
  SHOT_SCENES=("${STORE_SCENES[@]}")
  STORE_SHOTS=1   # launches with -GPStore YES: no build label in store screenshots
  for sim in duo iphone max; do
    use_sim "$sim"
    capture "$out/$sim"
  done
  local py=(python3)
  command -v uv >/dev/null && py=(uv run --quiet --with pillow python3)
  # Absolute paths: appstore.py runs from the repo root, so a relative ../fastlane lands outside it.
  "${py[@]}" ../tools/appstore.py shots "$out" "$(cd .. && pwd)/fastlane/screenshots/en-US" "${STORE_SCENES[@]}"
}

# A capture run leaves nothing running: a staged scene redraws every frame and holds a core
# until it is quit, and an idle booted simulator is not idle either (its PosterBoard respawns
# in a loop). On exit, also after a failure, quit the app on every simulator the run used and
# shut down the ones it booted; a simulator that was already booted stays up.
CAPTURED=() BOOTED=()
release_sims() {
  local u
  for u in ${CAPTURED[@]+"${CAPTURED[@]}"}; do
    limit 30 xcrun simctl terminate "$u" "$BUNDLE_ID" >/dev/null 2>&1 || true
  done
  for u in ${BOOTED[@]+"${BOOTED[@]}"}; do
    limit 60 xcrun simctl shutdown "$u" >/dev/null 2>&1 || true
  done
}

# Screenshots of every staged scene on the current simulator, into <out>; with a second
# argument, short recordings too.
capture() {
  local out=$1 record=${2:-}
  mkdir -p "$out"
  local udid; udid=$(sim_udid)
  say "Building for $SIM_NAME ($udid)"
  build_sim "$udid"
  say "Booting"
  trap release_sims EXIT
  CAPTURED+=("$udid")
  xcrun simctl list devices booted | grep -q "$udid" || BOOTED+=("$udid")
  boot_sim "$udid"
  say "Installing"
  xcrun simctl install "$udid" build/sim/Build/Products/Debug-iphonesimulator/GoldenPixel.app
  # The Duo simulator has two displays; the inner (larger) one is the game's target.
  local inner="" outer=""
  if [[ "$SIM_TYPE" == *Duo* ]]; then
    say "Device types with Duo in the name:"
    xcrun simctl list devicetypes | grep -i duo || true
    # The device profile, so the report can quote the simulator's own screen numbers.
    local profile
    profile=$(find "$(xcode-select -p)/../Developer/Platforms/iPhoneOS.platform" /Library/Developer/CoreSimulator /Applications/Xcode*.app -path "*iPhone Duo*.simdevicetype*" -name profile.plist 2>/dev/null | head -1 || true)
    [[ -n "$profile" ]] && plutil -convert json -o "$out/duo-profile.json" "$profile" || true
    # simctl's display ids for the Duo profile: 3 = LCD-1 inner 2007x2853, 1 = LCD cover 1398x2034.
    inner=3; outer=1
    # A booted Duo starts folded with the inner screen black; unfold it flat.
    unfold "$udid"
    mkdir -p "$out/outer"
  fi
  say "Inner display ${inner:-default}, outer display ${outer:-none}"
  local scene
  for scene in "${SHOT_SCENES[@]}"; do
    say "Scene $scene"
    limit 60 xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -GPScene "$scene" ${STORE_SHOTS:+-GPStore YES} $(mute_flag) >/dev/null
    sleep 4
    limit 30 xcrun simctl io "$udid" screenshot ${inner:+--display=$inner} "$out/$scene.png"
    [[ -n "$outer" ]] && { limit 30 xcrun simctl io "$udid" screenshot --display="$outer" "$out/outer/$scene.png" || true; }
  done
  if [[ -n "$record" ]]; then
    for scene in menu late gold; do
      say "Recording $scene"
      limit 60 xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -GPScene "$scene" $(mute_flag) >/dev/null
      sleep 1
      xcrun simctl io "$udid" recordVideo ${inner:+--display=$inner} --codec=h264 --force "$out/$scene.mp4" &
      local rec=$!
      sleep 7
      kill -INT "$rec"; wait "$rec" || true
    done
    ls -la "$out"
  fi
  # Quit the last scene now, so a run over several simulators does not stack up busy apps.
  limit 30 xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

pick_device() {
  if [[ -n "${DEVICE:-}" ]]; then echo "$DEVICE"; return; fi
  local json; json=$(mktemp)
  xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || true
  python3 - "$json" <<'PY'
import json, sys
devs = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
ok = [d for d in devs if d.get("hardwareProperties", {}).get("platform") == "iOS"
      and d.get("hardwareProperties", {}).get("reality") == "physical"]
if ok:
    print(ok[0].get("hardwareProperties", {}).get("udid") or ok[0]["identifier"])
PY
  rm -f "$json"
}

device() {
  ensure_project
  local config=Release
  [[ "${1:-}" == "debug" ]] && config=Debug
  local dev; dev=$(pick_device)
  [[ -n "$dev" ]] || die "No iPhone found. Plug it in, unlock it, tap Trust, and turn on Developer Mode."
  say "Building $config for device"
  xbuild -project GoldenPixel.xcodeproj -scheme GoldenPixel -configuration "$config" \
    -destination "id=$dev" -derivedDataPath build/device -allowProvisioningUpdates GP_COMMIT="$(commit)" build
  xcrun devicectl device install app --device "$dev" "build/device/Build/Products/$config-iphoneos/GoldenPixel.app"
  xcrun devicectl device process launch --device "$dev" --terminate-existing "$BUNDLE_ID" || true
}

archive() {
  local build=${1:?build number}
  local sha; sha=$(commit)
  ensure_project
  local auth=()
  if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  fi
  say "Archiving build $build ($sha)"
  rm -rf build/GoldenPixel.xcarchive build/export
  xbuild -project GoldenPixel.xcodeproj -scheme GoldenPixel -configuration Release \
    -destination "generic/platform=iOS" -archivePath build/GoldenPixel.xcarchive \
    -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} CURRENT_PROJECT_VERSION="$build" GP_COMMIT="$sha" archive
  say "Exporting the App Store .ipa"
  xbuild -exportArchive -archivePath build/GoldenPixel.xcarchive -exportOptionsPlist ExportOptions.plist \
    -exportPath build/export -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
  ls -la build/export
}

case "${1:-}" in
  project) project ;;
  sim) shift; sim "$@" ;;
  shots) shift; shots "$@" ;;
  compare) shift; compare "$@" ;;
  appstore) shift; appstore "$@" ;;
  device) shift; device "$@" ;;
  archive) shift; archive "$@" ;;
  *) sed -n '2,15p' "$IOS_DIR/$(basename "$0")"; exit 1 ;;
esac
