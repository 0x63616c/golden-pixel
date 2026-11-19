#!/usr/bin/env bash
# Build, install and launch the native iOS app. Used by the justfile and CI:
#   ios/ios.sh project                 regenerate GoldenPixel.xcodeproj from project.yml
#   ios/ios.sh sim                     build + run on the "GP Duo" simulator (iPhone Duo)
#   ios/ios.sh device [debug]          build (Release by default) + install + launch on a USB/Wi-Fi iPhone
#   ios/ios.sh archive <build>         archive + export an App Store .ipa into ios/build/export
#                                      (CI: signs with the App Store Connect API key in ASC_KEY_PATH)
#   ios/ios.sh shots <out-dir>         simulator screenshots + a short recording of staged scenes
# Pick a specific phone with DEVICE=<name or UDID> (see `xcrun devicectl list devices`).
set -euo pipefail

IOS_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$IOS_DIR"
BUNDLE_ID=co.worldwidewebb.goldenpixel
SIM_NAME="GP Duo"
SIM_TYPE=com.apple.CoreSimulator.SimDeviceType.iPhone-Duo

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

ensure_project() { [[ -d GoldenPixel.xcodeproj && GoldenPixel.xcodeproj -nt project.yml ]] || project; }

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
    -skipPackagePluginValidation build
}

sim() {
  local udid; udid=$(sim_udid)
  say "Building for simulator $SIM_NAME ($udid)"
  build_sim "$udid"
  xcrun simctl boot "$udid" 2>/dev/null || true
  open -a "Simulator" 2>/dev/null || true
  xcrun simctl install "$udid" build/sim/Build/Products/Debug-iphonesimulator/GoldenPixel.app
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" ${SCENE:+-GPScene "$SCENE"}
}

shots() {
  local out=${1:-build/shots}
  mkdir -p "$out"
  say "Device types with Duo in the name:"
  xcrun simctl list devicetypes | grep -i duo || true
  local udid; udid=$(sim_udid)
  say "Building for $SIM_NAME ($udid)"
  build_sim "$udid"
  say "Booting"
  boot_sim "$udid"
  say "Installing"
  xcrun simctl install "$udid" build/sim/Build/Products/Debug-iphonesimulator/GoldenPixel.app
  # The device profile, so the report can quote the simulator's own screen numbers.
  local profile
  profile=$(find "$(xcode-select -p)/../Developer/Platforms/iPhoneOS.platform" /Library/Developer/CoreSimulator /Applications/Xcode*.app -path "*iPhone Duo*.simdevicetype*" -name profile.plist 2>/dev/null | head -1 || true)
  [[ -n "$profile" ]] && plutil -convert json -o "$out/duo-profile.json" "$profile" || true
  # The Duo simulator has two displays; the inner (larger) one is the game's target.
  local inner outer
  # simctl's display ids for the Duo profile: 3 = LCD-1 inner 2007x2853, 1 = LCD cover 1398x2034.
  if [[ "$SIM_TYPE" == *Duo* ]]; then inner=3; outer=1; fi
  if [[ -n "$outer" ]]; then
    # A booted Duo starts folded with the inner screen black; unfold it flat.
    unfold "$udid"
  fi
  say "Inner display ${inner:-default}, outer display ${outer:-none}"
  mkdir -p "$out/outer"
  for scene in title start mid zoom upgrades late skills gold; do
    say "Scene $scene"
    limit 60 xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -GPScene "$scene" >/dev/null
    sleep 4
    limit 30 xcrun simctl io "$udid" screenshot ${inner:+--display=$inner} "$out/$scene.png"
    [[ -n "$outer" ]] && { limit 30 xcrun simctl io "$udid" screenshot --display="$outer" "$out/outer/$scene.png" || true; }
  done
  for scene in start late gold; do
    say "Recording $scene"
    limit 60 xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" -GPScene "$scene" >/dev/null
    sleep 1
    xcrun simctl io "$udid" recordVideo ${inner:+--display=$inner} --codec=h264 --force "$out/$scene.mp4" &
    local rec=$!
    sleep 7
    kill -INT "$rec"; wait "$rec" || true
  done
  ls -la "$out"
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
    -destination "id=$dev" -derivedDataPath build/device -allowProvisioningUpdates build
  xcrun devicectl device install app --device "$dev" "build/device/Build/Products/$config-iphoneos/GoldenPixel.app"
  xcrun devicectl device process launch --device "$dev" --terminate-existing "$BUNDLE_ID" || true
}

archive() {
  local build=${1:?build number}
  ensure_project
  local auth=()
  if [[ -n "${ASC_KEY_PATH:-}" ]]; then
    auth=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  fi
  say "Archiving build $build"
  rm -rf build/GoldenPixel.xcarchive build/export
  xbuild -project GoldenPixel.xcodeproj -scheme GoldenPixel -configuration Release \
    -destination "generic/platform=iOS" -archivePath build/GoldenPixel.xcarchive \
    -allowProvisioningUpdates ${auth[@]+"${auth[@]}"} CURRENT_PROJECT_VERSION="$build" archive
  say "Exporting the App Store .ipa"
  xbuild -exportArchive -archivePath build/GoldenPixel.xcarchive -exportOptionsPlist ExportOptions.plist \
    -exportPath build/export -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
  ls -la build/export
}

case "${1:-}" in
  project) project ;;
  sim) sim ;;
  shots) shift; shots "$@" ;;
  device) shift; device "$@" ;;
  archive) shift; archive "$@" ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
