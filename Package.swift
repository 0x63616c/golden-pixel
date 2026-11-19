// swift-tools-version: 6.2
// GoldenPixelCore: every game rule, the simulation and the pixel renderer, in plain Swift.
// It builds and tests on macOS and Linux (`swift test`); the iOS app (App/) only adds
// Metal presentation, touch, haptics and sound on top of it.
import PackageDescription

let package = Package(
    name: "GoldenPixel",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "GoldenPixelCore", targets: ["GoldenPixelCore"]),
    ],
    targets: [
        .target(name: "GoldenPixelCore", path: "Core/Sources/GoldenPixelCore"),
        // Renders scenes to PNG without a device (`just render`): previews, icons and docs art.
        .executableTarget(name: "gp-render", dependencies: ["GoldenPixelCore"], path: "Core/Sources/gp-render"),
        .testTarget(name: "GoldenPixelCoreTests", dependencies: ["GoldenPixelCore"], path: "Core/Tests/GoldenPixelCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
