import XCTest
@testable import GoldenPixelCore

final class IconTests: XCTestCase {
    /// 32 art px at a whole scale fills the 1024 px App Store icon exactly.
    func testIconFillsTheAppStoreSize() {
        XCTAssertEqual(Icon.size * Icon.scale, 1024)
        let c = Icon.draw()
        XCTAssertEqual(c.width, Icon.size); XCTAssertEqual(c.height, Icon.size)
        XCTAssertFalse(PNG.encode(c, scale: Icon.scale).isEmpty)
    }

    /// Flat and on-palette: every pixel is one of a handful of `Palette` colours, with no glow
    /// byte (the icon has no bloom).
    func testIconUsesFewPaletteColours() {
        let c = Icon.draw()
        let allowed = Set(([Palette.black, Palette.gold, Palette.goldLight, Palette.goldDim, Palette.white] + Palette.ladder).map(\.rgbOnly))
        let used = Set(c.pixels)
        XCTAssertTrue(used.allSatisfy { $0.glow == 0 })
        XCTAssertTrue(used.isSubset(of: allowed), "off-palette: \(used.subtracting(allowed))")
        XCTAssertLessThanOrEqual(used.count, 9)
    }

    /// The gold and the ball stay clear of iOS's rounded-corner mask (radius about 22% of the
    /// side), so nothing that matters is clipped.
    func testGoldAndBallClearTheCornerMask() {
        let c = Icon.draw(), n = Double(Icon.size), r = 0.2237 * n
        func masked(_ x: Int, _ y: Int) -> Bool {
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            let cx = min(max(px, r), n - r), cy = min(max(py, r), n - r)
            return (px - cx) * (px - cx) + (py - cy) * (py - cy) > r * r
        }
        let key: Set<Pixel> = [Palette.gold.rgbOnly, Palette.goldLight.rgbOnly, Palette.white.rgbOnly]
        for y in 0..<c.height {
            for x in 0..<c.width where key.contains(c.get(x, y)) {
                XCTAssertFalse(masked(x, y), "key pixel at \(x),\(y) falls in a rounded corner")
            }
        }
    }

    /// The tinted variant is pure grey with the golden pixel the brightest thing on it.
    func testTintedIsGreyWithTheGoldBrightest() {
        let colour = Icon.draw(), tinted = Icon.draw(.tinted)
        var goldLevel: UInt8 = 0, otherMax: UInt8 = 0
        for i in tinted.pixels.indices {
            let p = tinted.pixels[i]
            XCTAssertTrue(p.red == p.green && p.green == p.blue && p.glow == 0)
            if colour.pixels[i] == Palette.gold.rgbOnly { goldLevel = p.red } else { otherMax = max(otherMax, p.red) }
        }
        XCTAssertEqual(goldLevel, 255)
        XCTAssertLessThan(otherMax, goldLevel)
    }
}
