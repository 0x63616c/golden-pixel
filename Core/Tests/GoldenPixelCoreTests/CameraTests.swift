import XCTest
@testable import GoldenPixelCore

final class CameraTests: XCTestCase {
    /// A level-sized board seen through the Duo's board view.
    let boardSide = 590, viewW = 325, viewH = 334
    func cam() -> Camera { Camera(boardW: boardSide, boardH: boardSide, viewW: viewW, viewH: viewH) }

    func settle(_ c: inout Camera) { for _ in 0..<600 { c.update(1.0 / 60) } }

    func assertOnGrid(_ c: Camera, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(c.isAtRest, file: file, line: line)
        XCTAssertTrue(Camera.boardLevels.contains(c.zoom), file: file, line: line)
        XCTAssertEqual(c.origin.x, c.origin.x.rounded(), accuracy: 1e-9, file: file, line: line)
        XCTAssertEqual(c.origin.y, c.origin.y.rounded(), accuracy: 1e-9, file: file, line: line)
    }

    /// The view never shows past the board's edge, unless the whole board fits, when it is centred.
    func assertInside(_ c: Camera, file: StaticString = #filePath, line: UInt = #line) {
        let o = c.origin, w = Double(boardSide) * c.zoom
        if w <= Double(viewW) {
            XCTAssertEqual(o.x, ((Double(viewW) - w) / 2).rounded(), accuracy: 1, file: file, line: line)
        } else {
            XCTAssertLessThanOrEqual(o.x, 1e-9, file: file, line: line)
            XCTAssertGreaterThanOrEqual(o.x + w, Double(viewW) - 1e-9, file: file, line: line)
        }
    }

    func testStartsAtZoomOneOnTheGrid() {
        let c = cam()
        XCTAssertEqual(c.zoom, 1)
        assertOnGrid(c)
    }

    func testLookAtCentresThePoint() {
        var c = cam()
        c.look(at: 300, 280)
        let v = c.toView(300, 280)
        XCTAssertEqual(v.x, Double(viewW) / 2, accuracy: 1)
        XCTAssertEqual(v.y, Double(viewH) / 2, accuracy: 1)
        assertOnGrid(c)
        c.look(at: 0, 0)
        assertInside(c)
        XCTAssertEqual(c.origin.x, 0); XCTAssertEqual(c.origin.y, 0)
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
        c.look(at: 295, 295)
        let before = c.toBoard(164, 164)
        c.pinch(factor: 1.6, at: 164, 164)
        let after = c.toBoard(164, 164)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-6); XCTAssertEqual(before.y, after.y, accuracy: 1e-6)
        XCTAssertEqual(c.zoom, 1.6, accuracy: 1e-9)
    }

    func testReleaseEasesToTheNearestLevelOnTheGrid() {
        for (factor, expected) in [(1.3, 1.0), (1.6, 2.0), (2.7, 3.0), (3.4, 3.0), (9.0, 4.0), (0.6, 0.5), (0.8, 1.0), (0.1, 0.5)] {
            var c = cam()
            c.look(at: 295, 295)
            c.pinch(factor: factor, at: 90, 200)
            c.settle()
            settle(&c)
            XCTAssertEqual(c.zoom, expected, "factor \(factor)")
            assertOnGrid(c)
            assertInside(c)
        }
    }

    /// At 0.5 the board is an exact subsample: every view pixel maps to an even board pixel.
    func testHalfZoomIsAnExactSubsample() {
        var c = cam()
        c.pinch(factor: 0.5, at: 160, 160)
        c.settle(); settle(&c)
        XCTAssertEqual(c.zoom, 0.5)
        for vx in 0..<20 {
            let b = c.toBoard(Double(vx), 0)
            XCTAssertEqual(b.x, b.x.rounded(), accuracy: 1e-9)
        }
        c.pan(7, 3)
        assertOnGrid(c)
    }

    func testPanFollowsTheFingerAndIsClampedToTheBoard() {
        var c = cam()
        c.look(at: 295, 295)
        let o = c.origin
        c.pan(10, -6)
        XCTAssertEqual(c.origin.x, o.x + 10, accuracy: 1e-9)
        XCTAssertEqual(c.origin.y, o.y - 6, accuracy: 1e-9)
        assertOnGrid(c)
        c.pan(10_000, 10_000); assertInside(c); assertOnGrid(c)
        XCTAssertEqual(c.origin.x, 0); XCTAssertEqual(c.origin.y, 0)
        c.pan(-10_000, -10_000); assertInside(c); assertOnGrid(c)
        XCTAssertEqual(c.origin.x, Double(viewW) - Double(boardSide) * c.zoom)
    }

    func testDoubleTapTogglesBetweenOneAndCloseUp() {
        var c = cam()
        c.look(at: 295, 295)
        c.toggle(at: 160, 160)
        settle(&c)
        XCTAssertEqual(c.zoom, Camera.closeUp)
        assertOnGrid(c); assertInside(c)
        c.toggle(at: 10, 10)
        settle(&c)
        XCTAssertEqual(c.zoom, 1)
        assertOnGrid(c)
    }

    func testOddViewSizesStillLandOnTheGrid() {
        var c = Camera(boardW: 450, boardH: 450, viewW: 331, viewH: 317)
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

    /// Every level opens with the spawn in the middle of the board view, even though the
    /// spawn sits near the level's edge: the board camera may look past the edge.
    func testLevelsStartWithTheSpawnInTheMiddle() {
        for level in 1...7 {
            let g = Game(progress: { var p = GoldenPixelCore.Progress(); p.level = level; return p }())
            let cp = Double(Tuning.cellPixels)
            let v = g.ui.camera.toView((Double(g.board.spawn.x) + 0.5) * cp, (Double(g.board.spawn.y) + 0.5) * cp)
            XCTAssertEqual(v.x, Double(g.ui.camera.viewW) / 2, accuracy: 1, "level \(level)")
            XCTAssertEqual(v.y, Double(g.ui.camera.viewH) / 2, accuracy: 1, "level \(level)")
        }
    }

    func testOverscrollLetsAnyBoardPointReachTheCentre() {
        var c = Camera(boardW: boardSide, boardH: boardSide, viewW: viewW, viewH: viewH, overscroll: 1)
        c.look(at: 5, Double(boardSide) - 5)
        let v = c.toView(5, Double(boardSide) - 5)
        XCTAssertEqual(v.x, Double(viewW) / 2, accuracy: 1)
        XCTAssertEqual(v.y, Double(viewH) / 2, accuracy: 1)
        c.pan(-10_000, -10_000)
        XCTAssertEqual(c.toView(Double(boardSide), Double(boardSide)).x, Double(viewW) / 2, accuracy: 1, "but no further")
        assertOnGrid(c)
    }

    func testDragOnTheBoardAlwaysPans() {
        let (g, r) = game()
        let b = g.board
        let block = b.kind.indices.first { b.kind[$0] == .block && b.revealed[$0] }!
        let from = canvasPoint(g, cell: block % b.size, block / b.size)
        let o = g.ui.camera.origin
        let hp = b.hp[block]
        g.handle(.drag(from: from, to: Point(from.x + 6, from.y - 4)))
        g.handle(.release(from))
        XCTAssertEqual(g.ui.camera.origin.x, min(0, o.x + 6), accuracy: 1e-9)
        XCTAssertEqual(b.hp[block], hp, "a swipe never chips")
        r.render(g)
    }

    func testASecondFingerCancelsTheTapAndPinches() {
        var t = PointerTracker()
        XCTAssertEqual(t.began(Point(100, 100), id: 1, at: 0), [.down(Point(100, 100))])
        XCTAssertEqual(t.began(Point(140, 100), id: 2, at: 0.05), [])
        let g = t.moved(Point(160, 100), id: 2, at: 0.1)
        guard case .pinch(let center, let factor, let dx, _)? = g.first else { return XCTFail("expected a pinch") }
        XCTAssertEqual(factor, 1.5, accuracy: 1e-9)
        XCTAssertEqual(center, Point(130, 100))
        XCTAssertEqual(dx, 10)
        XCTAssertEqual(t.ended(Point(160, 100), id: 2, at: 0.2), [.pinchEnded])
        XCTAssertEqual(t.moved(Point(90, 100), id: 1, at: 0.25), [], "the leftover finger is ignored")
        XCTAssertEqual(t.ended(Point(90, 100), id: 1, at: 0.3), [], "and never becomes a tap")
        XCTAssertEqual(t.began(Point(10, 10), id: 3, at: 1), [.down(Point(10, 10))])
        XCTAssertEqual(t.ended(Point(10, 10), id: 3, at: 1.1), [.tap(Point(10, 10), time: 1.1)], "fresh touches work again")
    }

    func testPinchZoomsTheBoardButNotTheUI() {
        let (g, r) = game()
        let panelBefore = g.ui.layout.panel
        let rows = g.ui.hits.filter { if case .ballRow = $0.action { return true }; return false }.map(\.rect)
        g.handle(.pinch(center: Point(150, 150), factor: 2.2, dx: 0, dy: 0))
        g.handle(.pinchEnded)
        for _ in 0..<120 { g.update(1.0 / 60) }
        r.render(g)
        XCTAssertEqual(g.ui.camera.zoom, 2)
        XCTAssertEqual(g.ui.layout.panel, panelBefore)
        XCTAssertEqual(g.ui.hits.filter { if case .ballRow = $0.action { return true }; return false }.map(\.rect), rows)
    }
}
