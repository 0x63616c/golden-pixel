import XCTest
@testable import GoldenPixelCore

final class CameraTests: XCTestCase {
    let side = Tuning.boardCells * Tuning.cellPixels
    func cam() -> Camera { Camera(boardW: side, boardH: side, viewW: side, viewH: side) }

    func settle(_ c: inout Camera) { for _ in 0..<600 { c.update(1.0 / 60) } }

    func assertOnGrid(_ c: Camera, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(c.isAtRest, file: file, line: line)
        XCTAssertEqual(c.zoom, c.zoom.rounded(), file: file, line: line)
        XCTAssertEqual(c.origin.x, c.origin.x.rounded(), accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(c.origin.y, c.origin.y.rounded(), accuracy: 1e-9, file: file, line: line)
    }

    func assertInside(_ c: Camera, file: StaticString = #filePath, line: UInt = #line) {
        let o = c.origin
        XCTAssertLessThanOrEqual(o.x, 1e-9, file: file, line: line)
        XCTAssertLessThanOrEqual(o.y, 1e-9, file: file, line: line)
        XCTAssertGreaterThanOrEqual(o.x + Double(side) * c.zoom, Double(side) - 1e-9, file: file, line: line)
        XCTAssertGreaterThanOrEqual(o.y + Double(side) * c.zoom, Double(side) - 1e-9, file: file, line: line)
    }

    func testStartsFitToScreenOnTheGrid() {
        let c = cam()
        XCTAssertEqual(c.zoom, 1)
        XCTAssertEqual(c.origin.x, 0); XCTAssertEqual(c.origin.y, 0)
        assertOnGrid(c)
    }

    func testViewAndBoardMappingsAreInverse() {
        var c = cam()
        c.pinch(factor: 2.3, at: 100, 70)
        let b = c.toBoard(37.5, 211.25)
        let v = c.toView(b.x, b.y)
        XCTAssertEqual(v.x, 37.5, accuracy: 1e-9); XCTAssertEqual(v.y, 211.25, accuracy: 1e-9)
    }

    func testPinchKeepsThePointUnderTheFingers() {
        var c = cam()
        let before = c.toBoard(164, 164)
        c.pinch(factor: 1.6, at: 164, 164)
        let after = c.toBoard(164, 164)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-6); XCTAssertEqual(before.y, after.y, accuracy: 1e-6)
        XCTAssertEqual(c.zoom, 1.6, accuracy: 1e-9)
    }

    func testReleaseEasesToTheNearestWholeZoomOnTheGrid() {
        for (factor, expected) in [(1.4, 1.0), (1.6, 2.0), (2.7, 3.0), (3.4, 3.0), (9.0, 4.0), (0.3, 1.0)] {
            var c = cam()
            c.pinch(factor: factor, at: 90, 200)
            XCTAssertFalse(c.isAtRest || factor == 1)
            c.settle()
            settle(&c)
            XCTAssertEqual(c.zoom, expected, "factor \(factor)")
            assertOnGrid(c)
            assertInside(c)
        }
    }

    func testPanFollowsTheFingerAndIsClampedToTheBoard() {
        var c = cam()
        c.pan(40, 40)
        XCTAssertEqual(c.origin.x, 0, "at fit there is nowhere to pan")
        c.toggle(at: 164, 164); settle(&c)
        XCTAssertEqual(c.zoom, Camera.closeUp)
        let o = c.origin
        c.pan(10, -6)
        XCTAssertEqual(c.origin.x, o.x + 10, accuracy: 1e-9)
        XCTAssertEqual(c.origin.y, o.y - 6, accuracy: 1e-9)
        assertOnGrid(c)
        c.pan(10_000, 10_000); assertInside(c); assertOnGrid(c)
        XCTAssertEqual(c.origin.x, 0); XCTAssertEqual(c.origin.y, 0)
        c.pan(-10_000, -10_000); assertInside(c); assertOnGrid(c)
        XCTAssertEqual(c.origin.x, Double(side) - Double(side) * c.zoom)
    }

    func testDoubleTapTogglesBetweenFitAndCloseUp() {
        var c = cam()
        c.toggle(at: 60, 60)
        settle(&c)
        XCTAssertEqual(c.zoom, Camera.closeUp)
        assertOnGrid(c); assertInside(c)
        // The tapped spot is now near the middle of the view (or as near as the edge allows).
        let p = c.toView(60, 60)
        XCTAssertLessThan(abs(p.x - 120), 60)
        c.toggle(at: 10, 10)
        settle(&c)
        XCTAssertEqual(c.zoom, 1)
        XCTAssertEqual(c.origin.x, 0); XCTAssertEqual(c.origin.y, 0)
    }

    func testOddViewSizesStillLandOnTheGrid() {
        var c = Camera(boardW: side, boardH: side, viewW: 331, viewH: 317)
        c.pinch(factor: 2.9, at: 101, 33)
        c.settle(); settle(&c)
        assertOnGrid(c)
    }

    // MARK: Gestures in the game

    func game() -> (Game, Renderer) {
        let g = Game(seed: 4)
        g.ui.started = true
        let r = Renderer()
        r.render(g)
        return (g, r)
    }

    func canvasPoint(_ g: Game, cell x: Int, _ y: Int) -> Point {
        let cp = Tuning.cellPixels
        let v = g.ui.camera.toView(Double(x * cp + cp / 2), Double(y * cp + cp / 2))
        return Point(g.ui.layout.board.x + Int(v.x), g.ui.layout.board.y + Int(v.y))
    }

    func testDoubleTapOnOpenSpaceZoomsButOnABlockJustHits() {
        let (g, r) = game()
        let b = g.board
        let open = canvasPoint(g, cell: b.spawn.x, b.spawn.y)
        g.handle(.tap(open, time: 1.0))
        g.handle(.tap(open, time: 1.2))
        for _ in 0..<120 { g.update(1.0 / 60) }
        XCTAssertEqual(g.ui.camera.zoom, Camera.closeUp)
        r.render(g)

        let block = b.kind.indices.first { b.kind[$0] == .block && b.revealed[$0] }!
        let bp = canvasPoint(g, cell: block % b.size, block / b.size)
        let hp = b.hp[block]
        g.handle(.tap(bp, time: 5.0))
        g.handle(.tap(bp, time: 5.1))
        XCTAssertLessThan(b.hp[block], hp, "taps on a block always hit it")
        XCTAssertEqual(g.ui.camera.zoom, Camera.closeUp, "and never toggle the zoom")
    }

    func testDragOnOpenSpacePansAndDragOnBlocksChips() {
        let (g, r) = game()
        let b = g.board
        let open = canvasPoint(g, cell: b.spawn.x, b.spawn.y)
        g.handle(.tap(open, time: 1)); g.handle(.tap(open, time: 1.1))
        for _ in 0..<120 { g.update(1.0 / 60) }
        r.render(g)
        let o = g.ui.camera.origin
        let from = canvasPoint(g, cell: b.spawn.x, b.spawn.y)
        let money = g.progress.money
        g.handle(.drag(from: from, to: Point(from.x + 6, from.y)))
        g.handle(.release(from))
        XCTAssertEqual(g.ui.camera.origin.x, min(0, o.x + 6), accuracy: 1e-9)
        XCTAssertEqual(g.progress.money, money)

        r.render(g)
        let block = b.kind.indices.first { b.kind[$0] == .block && b.revealed[$0] }!
        let bp = canvasPoint(g, cell: block % b.size, block / b.size)
        let before = g.ui.camera.origin
        let hp = b.hp[block]
        g.handle(.drag(from: bp, to: Point(bp.x + 1, bp.y)))
        g.handle(.release(bp))
        XCTAssertEqual(g.ui.camera.origin.x, before.x, "a swipe from a block chips; it doesn't pan")
        XCTAssertLessThan(b.hp[block], hp)
    }

    func testASecondFingerCancelsTheTapAndPinches() {
        var t = PointerTracker()
        XCTAssertEqual(t.began(Point(100, 100), id: 1, at: 0), [])
        XCTAssertEqual(t.began(Point(140, 100), id: 2, at: 0.05), [])
        let g = t.moved(Point(160, 100), id: 2, at: 0.1)
        guard case .pinch(let center, let factor, let dx, _)? = g.first else { return XCTFail("expected a pinch") }
        XCTAssertEqual(factor, 1.5, accuracy: 1e-9)
        XCTAssertEqual(center, Point(130, 100))
        XCTAssertEqual(dx, 10)
        XCTAssertEqual(t.ended(Point(160, 100), id: 2, at: 0.2), [.pinchEnded])
        XCTAssertEqual(t.moved(Point(90, 100), id: 1, at: 0.25), [], "the leftover finger is ignored")
        XCTAssertEqual(t.ended(Point(90, 100), id: 1, at: 0.3), [], "and never becomes a tap")
        XCTAssertEqual(t.began(Point(10, 10), id: 3, at: 1), [])
        XCTAssertEqual(t.ended(Point(10, 10), id: 3, at: 1.1), [.tap(Point(10, 10), time: 1.1)], "fresh touches work again")
    }

    func testPinchZoomsTheBoardButNotTheUI() {
        let (g, r) = game()
        let panelBefore = g.ui.layout.panel
        let cards = g.ui.hits.filter { if case .buyBall = $0.action { return true }; return false }.map(\.rect)
        g.handle(.pinch(center: Point(150, 150), factor: 2.2, dx: 0, dy: 0))
        g.handle(.pinchEnded)
        for _ in 0..<120 { g.update(1.0 / 60) }
        r.render(g)
        XCTAssertEqual(g.ui.camera.zoom, 2)
        XCTAssertEqual(g.ui.layout.panel, panelBefore)
        XCTAssertEqual(g.ui.hits.filter { if case .buyBall = $0.action { return true }; return false }.map(\.rect), cards)
    }
}
