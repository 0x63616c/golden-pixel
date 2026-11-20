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
}
