import XCTest
@testable import GoldenPixelCore

final class GameTests: XCTestCase {
    func testBallsStayInsideTheBoardAndOutOfWalls() {
        let g = Scenes.make("late")
        for _ in 0..<(60 * 10) {
            g.update(1.0 / 60)
            for b in g.balls {
                XCTAssertTrue(b.x > 0 && b.y > 0 && b.x < Double(g.board.size) && b.y < Double(g.board.size))
                if b.phaseLeft <= 0 { XCTAssertNotEqual(g.board.kindAt(Int(b.x), Int(b.y)), .wall) }
            }
        }
    }

    func testBreakingTheGoldClearsTheLevelAfterAPause() {
        let g = Game(seed: 5)
        g.ui.started = true
        let sp = g.progress.skillPoints
        let i = g.board.index(g.board.gold.x, g.board.gold.y)
        g.board.hp[i] = 0.001
        g.tap(cellX: g.board.gold.x, cellY: g.board.gold.y)
        XCTAssertTrue(g.events.contains(.goldBroken))
        XCTAssertEqual(g.progress.skillPoints, sp + Economy.skillPointsForClear(1))
        XCTAssertNotNil(g.clearTimer)
        XCTAssertEqual(g.progress.level, 1)
        for _ in 0..<Int(Tuning.levelClearPause * 60 + 10) { g.update(1.0 / 60) }
        XCTAssertEqual(g.progress.level, 2)
        XCTAssertEqual(g.board.level, 2)
        XCTAssertEqual(g.progress.maxLevel, 2)
    }

    func testMoneyComesFromBreakingBlocks() {
        let g = Game(seed: 11)
        g.ui.started = true
        for _ in 0..<(60 * 20) { g.update(1.0 / 60) }
        XCTAssertGreaterThan(g.progress.money, 0)
        XCTAssertEqual(g.progress.money, g.progress.runEarnings, accuracy: 1e-6)
    }

    func testTitleScreenWaitsForATap() {
        let g = Game(seed: 1)
        for _ in 0..<120 { g.update(1.0 / 60) }
        XCTAssertEqual(g.progress.money, 0)
        g.handle(.tap(Point(10, 10)))
        XCTAssertTrue(g.ui.started)
    }

    func testSaveRoundTripResumesTheBoard() {
        let g = Scenes.make("mid")
        let data = SaveCodec.encode(g.saveFile(now: 1000))
        let s = SaveCodec.decode(data)!
        XCTAssertEqual(s.version, SaveFile.currentVersion)
        let g2 = Game()
        g2.load(s, now: 1000)
        XCTAssertEqual(g2.progress, g.progress)
        XCTAssertEqual(g2.board.kind, g.board.kind)
        XCTAssertEqual(g2.board.revealed, g.board.revealed)
        XCTAssertEqual(g2.balls.count, g.balls.count)
    }

    func testSaveFromTheFutureIsNotLoaded() {
        let json = #"{"version": 99, "progress": {}, "savedAt": 0}"#
        XCTAssertNil(SaveCodec.decode(Data(json.utf8)))
        XCTAssertNil(SaveCodec.decode(Data("garbage".utf8)))
    }

    func testOfflineEarningsOnLoad() {
        var p = Progress(); p.incomeRate = 5
        let g = Game()
        let away = g.load(SaveFile(progress: p, board: nil, savedAt: 0), now: 3600)
        XCTAssertEqual(away, 5 * 3600 * g.mods.offline, accuracy: 1e-6)
        XCTAssertEqual(g.progress.money, away, accuracy: 1e-6)
    }

    func testGestures() {
        var t = PointerTracker()
        _ = t.began(Point(10, 10), at: 0)
        XCTAssertEqual(t.ended(Point(11, 10), at: 0.1), [.tap(Point(11, 10), time: 0.1)])

        _ = t.began(Point(10, 10), at: 0)
        XCTAssertEqual(t.tick(at: 0.2), [])
        XCTAssertEqual(t.tick(at: 0.5), [.longPress(Point(10, 10))])
        XCTAssertEqual(t.ended(Point(10, 10), at: 0.6), [.release(Point(10, 10))])

        _ = t.began(Point(10, 10), at: 0)
        XCTAssertEqual(t.moved(Point(20, 10), at: 0.05), [.drag(from: Point(10, 10), to: Point(20, 10))])
        XCTAssertEqual(t.tick(at: 1), [], "a drag never turns into a long-press")
        XCTAssertEqual(t.ended(Point(20, 10), at: 1), [.release(Point(20, 10))])
    }

    func testTappingACardBuysABall() {
        var p = Progress(); p.money = 1000
        let g = Game(progress: p)
        g.ui.started = true
        let r = Renderer()
        r.render(g)
        let card = g.ui.hits.first { $0.action == .buyBall(.basic) }!
        let n = g.balls.count
        g.handle(.tap(Point(card.rect.x + 2, card.rect.y + 2)))
        XCTAssertEqual(g.balls.count, n + 1)
    }

    func testLongPressShowsDetailsWithoutBuying() {
        var p = Progress(); p.money = 1000
        let g = Game(progress: p)
        g.ui.started = true
        Renderer().render(g)
        let card = g.ui.hits.first { $0.action == .buyBall(.basic) }!
        g.handle(.longPress(Point(card.rect.x + 2, card.rect.y + 2)))
        XCTAssertNotNil(g.ui.tooltip)
        XCTAssertEqual(g.progress.money, 1000)
    }
}
