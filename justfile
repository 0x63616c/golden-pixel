# Golden Pixel — run `just` to list recipes.

default:
    @just --list

# Core unit tests (pure Swift; Linux or macOS)
test:
    swift test

# Render staged scenes to PNG at art scale 3 with bloom (no Xcode needed)
render out="build/render":
    swift run -c release gp-render all {{out}} --scale 3

# Render the 1024 px app icon and copy it into the asset catalog
icon:
    swift run -c release gp-render icon build/icon.png
    sips -s format png --deleteProperty hasAlpha build/icon.png --out ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png 2>/dev/null || cp build/icon.png ios/Assets.xcassets/AppIcon.appiconset/icon-1024.png

# Regenerate the Xcode project from ios/project.yml
ios-project:
    ios/ios.sh project

# Build and run on the iPhone Duo simulator (SCENE=mid just ios-sim for a staged scene)
ios-sim:
    ios/ios.sh sim

# Build and install on a plugged-in iPhone
ios-device *args:
    ios/ios.sh device {{args}}

# Duo simulator screenshots + recordings of staged scenes
shots out="build/shots":
    ios/ios.sh shots {{out}}

# Upload a TestFlight build from this Mac (needs ASC_* in fastlane/.env); CI does this on main
beta:
    bundle exec fastlane ios beta

# TestFlight processing state of the latest builds
beta-status:
    bundle exec fastlane ios status

# Point git at the repo hooks
hooks:
    git config core.hooksPath .githooks
