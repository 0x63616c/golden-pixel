import XCTest
@testable import GoldenPixelCore

/// The Duo's inner screen has heavily rounded corners: nothing you press may sit in them, and
/// everything you press is at least `Tuning.minTouch` (22 art px = 44 pt) square.
final class UISafetyTests: XCTestCase {
    /// Backgrounds that fill the screen or the board: pressing them anywhere is fine.
    func isBackground(_ a: Action) -> Bool {
        switch a {
        case .board, .tree, .panel, .none, .closeSheet: return true
        default: return false
        }
    }

    func testCornerTestRejectsTheCorners() {
        let L = Layout.make(width: Tuning.canvasWidth, height: Tuning.canvasHeight)
        XCTAssertFalse(L.onScreen(2, 2))
        XCTAssertFalse(L.onScreen(L.width - 3, 3))
        XCTAssertFalse(L.onScreen(4, L.height - 4))
        XCTAssertTrue(L.onScreen(L.width / 2, 0))
        XCTAssertTrue(L.onScreen(Tuning.cornerRadius, Tuning.cornerRadius))
        XCTAssertFalse(L.safe(Rect(L.width - 30, 1, 29, 18)), "the old skills close button")
    }

    func testEveryButtonIsOutOfTheCornersAndBigEnough() {
        for name in Scenes.names where name != "portrait" {
            let g = Scenes.make(name)
            let r = Renderer()
            r.render(g)
            let L = g.ui.layout
            for h in g.ui.hits where !isBackground(h.action) {
                if case .selectSkill = h.action {
                    // Tree nodes pan with the map; they only need to be big enough.
                } else {
                    XCTAssertTrue(L.safe(h.rect), "\(name): \(h.action) at \(h.rect) is in a rounded corner")
                }
                if h.info.isEmpty {
                    XCTAssertGreaterThanOrEqual(min(h.rect.w, h.rect.h), Tuning.minTouch, "\(name): \(h.action) at \(h.rect) is too small")
                }
            }
        }
    }

    /// The panel's own corners are empty: just its background colour.
    func testNothingIsDrawnInThePanelsCorners() {
        for name in ["start", "mid", "late"] {
            let g = Scenes.make(name)
            g.banners.removeAll()
            let r = Renderer()
            r.render(g)
            let L = g.ui.layout
            for y in 0..<L.height { for x in L.panel.x..<L.width where !L.onScreen(x, y) || !L.onScreen(x + 1, y + 1) {
                XCTAssertEqual(r.canvas.get(x, y), Palette.panel0, "\(name) \(x),\(y)")
            } }
        }
    }
    /// The build label shows on the menu and the settings card, in muted type, clear of the
    /// rounded corners and of every button.
    func testBuildLabelIsDrawnClearOfCornersAndButtons() {
        for name in ["menu", "settings"] {
            let a = Scenes.make(name), b = Scenes.make(name)
            XCTAssertFalse(a.buildLabel.isEmpty, "\(name): staged scenes carry a sample label")
            // Same length, different glyphs: the layout is identical, so only the label differs.
            b.buildLabel = "9.9.9 (999999999999) zzzzzzz"
            XCTAssertEqual(PixelFont.measure(a.buildLabel), PixelFont.measure(b.buildLabel))
            let ra = Renderer(), rb = Renderer()
            ra.render(a); rb.render(b)
            let L = a.ui.layout
            var x0 = Int.max, y0 = Int.max, x1 = Int.min, y1 = Int.min, muted = 0
            for y in 0..<L.height { for x in 0..<L.width where ra.canvas.get(x, y) != rb.canvas.get(x, y) {
                x0 = min(x0, x); y0 = min(y0, y); x1 = max(x1, x); y1 = max(y1, y)
                if ra.canvas.get(x, y).rgbOnly == Palette.muted.rgbOnly { muted += 1 }
            } }
            XCTAssertGreaterThan(muted, 20, "\(name): the label is drawn in muted ink")
            guard x0 <= x1 else { continue }
            let tag = Rect(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
            XCTAssertLessThanOrEqual(tag.h, PixelFont.capHeight + 2, "\(name): one small line")
            let r = Tuning.cornerRadius
            XCTAssertTrue(L.safe(tag), "\(name): label at \(tag) is in a rounded corner")
            XCTAssertTrue(tag.x >= r && tag.maxX <= L.width - r || tag.y >= r && tag.maxY <= L.height - r,
                          "\(name): label at \(tag) is within the corner radius")
            for h in a.ui.hits where !isBackground(h.action) {
                let overlap = tag.x < h.rect.maxX && h.rect.x < tag.maxX && tag.y < h.rect.maxY && h.rect.y < tag.maxY
                XCTAssertFalse(overlap, "\(name): label at \(tag) overlaps \(h.action) at \(h.rect)")
            }
        }
    }
}
