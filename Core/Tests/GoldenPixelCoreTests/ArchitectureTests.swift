import XCTest

/// Structure rules. When one fails, its message says what to do instead.
final class ArchitectureTests: XCTestCase {
    static let core = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/GoldenPixelCore")

    func testCoreHasNoPlatformImports() throws {
        let banned = ["import UIKit", "import SwiftUI", "import Metal", "import MetalKit", "import AVFoundation", "import CoreGraphics"]
        let files = try FileManager.default.contentsOfDirectory(at: Self.core, includingPropertiesForKeys: nil).filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        for f in files {
            let s = try String(contentsOf: f, encoding: .utf8)
            for b in banned {
                XCTAssertFalse(s.contains(b), "\(f.lastPathComponent) has `\(b)`: GoldenPixelCore stays platform-free; put platform code in App/.")
            }
        }
    }
}
