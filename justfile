# Golden Pixel — run `just` to list recipes.

default:
    @just --list

# Core unit tests (pure Swift; Linux or macOS)
test:
    swift test

# Render staged scenes to PNG at art scale 3 with bloom (no Xcode needed)
render out="build/render":
    swift run -c release gp-render all {{out}} --scale 3

# Rebuild the app icon's layer SVGs in the Icon Composer document (ios/AppIcon.icon), plus the
# flat 1024 px PNGs in build/ for reference. icon.json (glass, shadows, appearances) is edited in
# Icon Composer: open ios/AppIcon.icon.
icon:
    swift run -c release gp-render icon-layers ios/AppIcon.icon/Assets
    swift run -c release gp-render icon build

# Preview the Icon Composer icon as iOS draws it, in every appearance, into <out>
icon-preview out="build/icon-preview":
    #!/usr/bin/env bash
    set -euo pipefail
    ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
    mkdir -p {{out}}
    for r in Default Dark TintedLight TintedDark ClearLight ClearDark; do
        "$ictool" ios/AppIcon.icon --export-image --output-file {{out}}/$r.png \
            --platform iOS --rendition $r --width 1024 --height 1024 --scale 1 >/dev/null
    done
    echo "wrote {{out}}/{Default,Dark,TintedLight,TintedDark,ClearLight,ClearDark}.png"

# Regenerate the Xcode project from ios/project.yml
ios-project:
    ios/ios.sh project

# Build and run on a simulator: duo (default), iphone or max (SCENE=mid just ios-sim for a staged scene)
ios-sim sim="duo":
    ios/ios.sh sim {{sim}}

# Build and install on a plugged-in iPhone
ios-device *args:
    ios/ios.sh device {{args}}

# Simulator screenshots + recordings of staged scenes: duo (default), iphone or max
shots out="build/shots" sim="duo":
    ios/ios.sh shots {{out}} {{sim}}

# The same scenes on the Duo, iPhone 18 Pro and Pro Max, plus side-by-side sheets in <out>/sheets
compare out="build/compare" *sims:
    ios/ios.sh compare {{out}} {{sims}}

# Upload a TestFlight build from this Mac (needs ASC_* in fastlane/.env); CI does this on main
beta:
    bundle exec fastlane ios beta

# TestFlight processing state of the latest builds
beta-status:
    bundle exec fastlane ios status

# App Store screenshots (duo, iphone, max simulators) into fastlane/screenshots/en-US
appstore-shots out="build/appstore":
    ios/ios.sh appstore {{out}}

# Audit the App Store listing in the repo: limits, ASO, screenshots, privacy (--online checks URLs)
appstore-check *args:
    python3 tools/appstore.py check {{args}}

# Read-only App Store Connect state: versions, attached build, listing, screenshots, builds
appstore-status:
    bundle exec fastlane ios appstore_status

# Point git at the repo hooks
hooks:
    git config core.hooksPath .githooks
