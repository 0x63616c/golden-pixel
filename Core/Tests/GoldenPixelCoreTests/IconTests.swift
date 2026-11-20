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

    /// The Icon Composer layers stacked back to front on the dark are exactly the flat icon. Only
    /// the rays sit over another layer (the blocks), as in the logo; the gold and the ball stand
    /// alone, so their glass never doubles anything up.
    func testLayersStackIntoTheFlatIcon() {
        let flat = Icon.draw()
        var stacked = [Pixel](repeating: Palette.black, count: flat.pixels.count)
        var owners = [[Icon.Layer]](repeating: [], count: flat.pixels.count)
        for layer in Icon.Layer.allCases {
            for (i, p) in Icon.draw(layer).pixels.enumerated() where p != Palette.black {
                stacked[i] = p; owners[i].append(layer)
            }
        }
        XCTAssertEqual(stacked, flat.pixels)
        for o in owners where o.count > 1 { XCTAssertEqual(o, [.board, .rays]) }
    }

    /// Each layer's SVG is whole-art-pixel rects on a 32-unit viewBox at 1024 pt that cover
    /// exactly that layer's pixels, in its colours.
    func testLayerSVGsAreWholePixelRects() throws {
        let pattern = try Regex(##"<rect x="(\d+)" y="(\d+)" width="(\d+)" height="(\d+)" fill="#([0-9a-f]{6})"/>"##)
        for layer in Icon.Layer.allCases {
            let svg = Icon.svg(layer), c = Icon.draw(layer)
            XCTAssertTrue(svg.contains(#"width="1024" height="1024" viewBox="0 0 32 32""#))
            var covered = [Pixel](repeating: Palette.black, count: c.pixels.count)
            for m in svg.matches(of: pattern) {
                let n = (1...4).map { Int(m.output[$0].substring!)! }
                let hex = UInt32(m.output[5].substring!, radix: 16)!
                for y in n[1]..<(n[1] + n[3]) {
                    for x in n[0]..<(n[0] + n[2]) {
                        XCTAssertEqual(covered[y * Icon.size + x], Palette.black, "\(layer) overlaps at \(x),\(y)")
                        covered[y * Icon.size + x] = rgb(hex)
                    }
                }
            }
            XCTAssertEqual(covered, c.pixels, "\(layer)")
        }
    }
}
