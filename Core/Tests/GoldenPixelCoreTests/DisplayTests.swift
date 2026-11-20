import XCTest
@testable import GoldenPixelCore

/// The canvas on each screen: an art pixel is 2 points everywhere (6 device pixels at @3x), so
/// a smaller phone shows a smaller canvas at the same physical size, never smaller pixels.
final class DisplayTests: XCTestCase {
    func testTheDuoKeepsItsCanvas() {
        let d = Device.duo.display
        XCTAssertEqual(d.scale, Tuning.artScale)
        XCTAssertEqual(d.width, Tuning.canvasWidth)
        XCTAssertEqual(d.height, Tuning.canvasHeight)
        XCTAssertEqual(d.originX, 1)
        XCTAssertEqual(d.originY, 1)
        XCTAssertEqual(d.insets, Insets(bottom: 17), "the home indicator: 34 pt")
        XCTAssertEqual(d.corner, Tuning.cornerRadius)
    }

    func testPhonesGetTheSameScaleAndASmallerCanvas() {
        let pro = Device.pro.display
        XCTAssertEqual(pro.scale, 6)
        XCTAssertEqual(pro.width, 437)
        XCTAssertEqual(pro.height, 201)
        XCTAssertEqual(pro.insets, Insets(left: 31, right: 31, bottom: 10), "62 pt for the island's side, 20 pt for the home indicator")
        let max = Device.proMax.display
        XCTAssertEqual(max.scale, 6)
        XCTAssertEqual(max.width, 478)
        XCTAssertEqual(max.height, 220)
        XCTAssertEqual(max.insets, Insets(left: 31, right: 31, bottom: 10))
    }

    /// Two points, to the nearest whole device pixel (the mini draws 2.88 pixels per point).
    func testAnArtPixelIsTwoPointsOnEveryDevice() {
        for d in Device.all {
            XCTAssertEqual(Double(d.display.scale), (2 * d.pointScale).rounded(), "\(d.name)")
        }
    }

    func testASquareScreenHasNoCornersAndNoInsets() {
        let se = Device.se.display
        XCTAssertEqual(se.scale, 4)
        XCTAssertEqual(se.width, 333)
        XCTAssertEqual(se.height, 187)
        XCTAssertEqual(se.insets, .zero)
        XCTAssertEqual(se.corner, 0)
    }

    /// Part of an art pixel under an inset counts as the whole pixel.
    func testInsetsRoundUpToWholeArtPixels() {
        let mini = Device.mini.display
        XCTAssertEqual(mini.insets, Insets(left: 24, right: 24, bottom: 10), "20 pt = 57.6 px = 9.6 art px")
    }

    func testEveryDeviceHasTheRoomTheLayoutNeeds() {
        for d in Device.all {
            let s = d.display
            let w = s.width - s.insets.left - s.insets.right, h = s.height - s.insets.top - s.insets.bottom
            XCTAssertGreaterThanOrEqual(w, Tuning.minSafeLong, d.name)
            XCTAssertGreaterThanOrEqual(h, Tuning.minSafeShort, d.name)
        }
    }

    /// A screen too small for the layout at 2 points per art pixel gets smaller pixels rather
    /// than a canvas nothing fits on.
    func testAScreenThatIsTooSmallStepsTheScaleDown() {
        let d = Display.fit(pixelWidth: 960, pixelHeight: 640, pointScale: 2)
        XCTAssertEqual(d.scale, 3)
        XCTAssertEqual(d.width, 320)
        XCTAssertEqual(d.height, 213)
    }

    func testTheCanvasIsCentredInTheDrawable() {
        for d in Device.all {
            let s = d.display
            XCTAssertEqual(s.originX, (d.pixelWidth - s.width * s.scale) / 2, d.name)
            XCTAssertEqual(s.originY, (d.pixelHeight - s.height * s.scale) / 2, d.name)
            XCTAssertLessThan(d.pixelWidth - s.width * s.scale, s.scale, d.name)
            XCTAssertLessThan(d.pixelHeight - s.height * s.scale, s.scale, d.name)
        }
    }

    /// The panel's content stops at the safe area; its background and the board run to the
    /// screen's edges.
    func testThePanelSitsInsideTheSafeArea() {
        let d = Device.pro.display
        let L = Layout.make(width: d.width, height: d.height, insets: d.insets, corner: d.corner)
        XCTAssertEqual(L.safeArea, Rect(31, 0, 375, 191))
        XCTAssertEqual(L.board, Rect(0, 0, 256, 201))
        XCTAssertEqual(L.panel, Rect(256, 0, 181, 201))
        XCTAssertEqual(L.panelContent, Rect(256, 0, 150, 191))
        XCTAssertEqual(L.boardContent, Rect(31, 0, 225, 191))
        XCTAssertTrue(L.short)
        XCTAssertTrue(L.safe(Rect(300, 20, 40, 30)))
        XCTAssertFalse(L.safe(Rect(400, 20, 30, 30)), "under the island's inset")
        XCTAssertFalse(L.safe(Rect(300, 170, 40, 30)), "under the home indicator")
    }

    func testTheDuoLayoutIsUnchangedWithoutInsets() {
        let L = Layout.make(width: Tuning.canvasWidth, height: Tuning.canvasHeight)
        XCTAssertEqual(L.board, Rect(0, 0, 325, 334))
        XCTAssertEqual(L.panel, Rect(325, 0, 150, 334))
        XCTAssertEqual(L.panelContent, L.panel)
        XCTAssertFalse(L.short)
    }
}
