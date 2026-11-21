#!/bin/bash
# review-recording.sh <udid> <GoldenPixel.app> <out.mp4>
#
# The screen recording App Review asks a new app for: from the Home Screen, launch the app and
# play the typical flow with real touches (AXe), on a booted, unfolded iPhone Duo simulator of
# your own (951 x 669 pt landscape; see SKILL.md "Rejected"). Reinstalls the app first, so the
# save is fresh. Every coordinate is in points, read off screenshots: after a layout change,
# screenshot each step again (axe screenshot) before trusting them.
set -euo pipefail
U=${1:?simulator udid}; APP=${2:?path to GoldenPixel.app}; OUT=${3:?out.mp4}
BUNDLE=co.worldwidewebb.goldenpixel
TMP=$(mktemp -d)
ZERO=eff9a7a1d9adcf597c07c4b1dccc61da   # md5 of the shard counter's pixels while it reads 0

step() { echo "$(date +%T) $*"; }
tap() { step tap "$@"; axe tap -x "$1" -y "$2" --udid "$U" >/dev/null 2>&1; }
hold() { step hold "$@"; axe touch -x "$1" -y "$2" --down --up --delay "$3" --udid "$U" >/dev/null 2>&1; }
sling() { step sling "$@"; axe drag --start-x "$1" --start-y "$2" --end-x "$3" --end-y "$4" --hold 0.7 --duration 1.0 --udid "$U" >/dev/null 2>&1; }
pinch() { step pinch "$@"; axe gesture pinch --scale "$1" -x 325 -y 333 --radius "$2" --udid "$U" >/dev/null 2>&1; }
shards() {   # 0 while the shard counter still reads 0
  axe screenshot --udid "$U" --output "$TMP/poll.png" >/dev/null 2>&1
  local sum; sum=$(ffmpeg -v error -y -i "$TMP/poll.png" -vf crop=70:70:2045:175 -f rawvideo -pix_fmt rgb24 - | md5)
  [[ "$sum" == "$ZERO" ]] && echo 0 || echo 1
}

xcrun simctl terminate "$U" $BUNDLE >/dev/null 2>&1 || true
xcrun simctl uninstall "$U" $BUNDLE
xcrun simctl install "$U" "$APP"
# Mute it: an icon tap passes no -GPMute, and a simulator plays through the Mac's speakers.
# The global domain reaches the app; a plist written into its container did not.
xcrun simctl spawn "$U" defaults write -g GPMute -bool YES
axe button home --udid "$U" >/dev/null 2>&1 || true
sleep 1.5
axe swipe --start-x 700 --start-y 480 --end-x 250 --end-y 480 --duration 0.3 --udid "$U" >/dev/null 2>&1   # Home Screen page 2
sleep 1.5

xcrun simctl io "$U" recordVideo --display=3 --codec=h264 --force "$OUT" >/dev/null 2>&1 &
REC=$!
trap 'kill -INT $REC 2>/dev/null || true; wait $REC 2>/dev/null || true' EXIT
sleep 3

tap 763 182; sleep 2                   # the app's icon (a new simulator puts it here) -> main menu
# Refuse to go on with audible music: an unmuted app holds its .m4a tracks open.
PID=$(xcrun simctl spawn "$U" launchctl list | awk '/UIKitApplication:co.worldwidewebb.goldenpixel/ {print $1}')
if [[ -z "$PID" || "$PID" == "-" ]] || lsof -p "$PID" 2>/dev/null | grep -q '\.m4a'; then
  xcrun simctl terminate "$U" $BUNDLE || true
  echo "The app is not running or not muted: stopped"; exit 1
fi
sleep 2.5
tap 359 509; sleep 4.5                 # HOW TO PLAY
tap 127 49; sleep 1.2                  # back
tap 475 433; sleep 2.5                 # PLAY: level 1
sling 364 380 364 290; sleep 11        # ball 1, straight down at the mint shard pixel
sling 300 330 380 300; sleep 12        # ball 2 if 9 coins are in, else just the aim
hold 800 193 0.8; sleep 2.5            # hold the BASIC row: its info card
tap 474 476; sleep 2                   # BUY
tap 731 175; sleep 3                   # close the card
pinch 0.5 150; sleep 3                 # zoom out
pinch 2 75; sleep 2                    # and back in
got=0
for _ in $(seq 1 40); do got=$(shards); [[ $got == 1 ]] && break; sleep 0.7; done
step "shards before the tree: $got"
sleep 1
tap 767 119; sleep 2                   # TREE
tap 445 238; sleep 2.5                 # BASIC DAMAGE
[[ $got == 1 ]] && { tap 765 560; sleep 2.5; }   # buy it with the shard
tap 509 238; sleep 2.5                 # BASIC SPEED
tap 857 35; sleep 5                    # close the tree, watch the dig
tap 905 119; sleep 2                   # pause
tap 474 437; sleep 2.5                 # MAIN MENU
tap 591 509; sleep 2                   # SETTINGS
tap 680 259; sleep 1.2                 # MUSIC off
tap 680 259; sleep 1.2                 # MUSIC on
tap 680 403; sleep 1.5                 # GLOW on
tap 217 77; sleep 2                    # back
tap 475 433; sleep 5                   # CONTINUE LV 1
kill -INT $REC; wait $REC 2>/dev/null || true
trap - EXIT
xcrun simctl terminate "$U" $BUNDLE >/dev/null 2>&1 || true
rm -rf "$TMP"
ls -la "$OUT"
