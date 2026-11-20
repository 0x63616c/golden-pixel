# Golden Pixel — run `just` to list recipes.

default:
    @just --list

# Core unit tests (pure Swift; Linux or macOS)
test:
    swift test

# Render staged scenes to PNG at art scale 3 with bloom (no Xcode needed)
render out="build/render":
    swift run -c release gp-render all {{out}} --scale 3

# Render the 1024 px app icon (and its tinted greyscale) into the asset catalog
icon:
    swift run -c release gp-render icon build
    # gp-render writes stored (uncompressed) PNGs; sips recompresses them (3 MB -> ~20 KB).
    for f in icon icon-tinted; do \
        dst=ios/Assets.xcassets/AppIcon.appiconset/${f/icon/icon-1024}.png; \
        sips -s format png build/$f.png --out $dst >/dev/null 2>&1 || cp build/$f.png $dst; \
    done

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

# Point git at the repo hooks
hooks:
    git config core.hooksPath .githooks
