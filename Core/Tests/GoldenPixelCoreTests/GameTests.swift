import XCTest
@testable import GoldenPixelCore

final class GameTests: XCTestCase {
    func play(_ p: GoldenPixelCore.Progress = GoldenPixelCore.Progress(), seed: UInt64 = 1) -> (Game, Renderer) {
        let g = Game(progress: p, seed: seed)
        g.ui.screen = .game
        let r = Renderer()
        r.render(g)
        return (g, r)
    }

    func hitRect(_ g: Game, _ a: Action) -> Rect? { g.ui.hits.last { $0.action == a }?.rect }
    func centre(_ r: Rect) -> Point { Point(r.x + r.w / 2, r.y + r.h / 2) }

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

    /// Breaking the gold earns a star for good, then the next level starts as a fresh run.
    func testBreakingTheGoldGivesAStarAndStartsAFreshLevel() {
        var p = Progress()
        p.money = 500; p.shards = 4; p.skillRanks["core"] = 1
        p.balls[BallKind.basic.rawValue] = BallProgress(owned: 9)
        let (g, _) = play(p, seed: 5)
        let i = g.board.index(g.board.gold.x, g.board.gold.y)
        g.damageCell(i, g.board.hp[i] + 1)
        XCTAssertTrue(g.events.contains(.goldBroken))
        XCTAssertEqual(g.progress.stars, 1)
        XCTAssertNotNil(g.clearTimer)
        XCTAssertEqual(g.progress.level, 1)
        for _ in 0..<Int(Tuning.levelClearPause * 60 + 10) { g.update(1.0 / 60) }
        XCTAssertEqual(g.progress.level, 2)
        XCTAssertEqual(g.board.level, 2)
        XCTAssertEqual(g.progress.maxLevel, 2)
        XCTAssertEqual(g.progress.stars, 1, "stars are for good")
        XCTAssertEqual(g.progress.shards, 0)
        XCTAssertEqual(g.progress.skillRanks, SkillNode.startingRanks)
        XCTAssertEqual(g.balls.count, 1)
        XCTAssertGreaterThan(g.mods.damage, 1, "the star's bonus applies")
    }

    func testBreakingAShardPaysItsShards() {
        let (g, _) = play()
        let b = g.board
        let i = b.kind.indices.first { b.kind[$0] == .shard }!
        let v = b.shardValue[i]
        g.damageCell(i, b.hp[i] + 1)
        XCTAssertEqual(b.kind[i], .empty)
        XCTAssertEqual(g.progress.shards, v)
        XCTAssertTrue(g.events.contains(.shardBroken))
    }

    func testMoneyComesFromBreakingBlocks() {
        let (g, _) = play(seed: 11)
        for _ in 0..<(60 * 20) { g.update(1.0 / 60) }
        XCTAssertGreaterThan(g.progress.money, 0)
        XCTAssertEqual(g.progress.money, g.progress.runEarnings, accuracy: 1e-6)
        XCTAssertEqual(g.progress.levelTime, 20, accuracy: 0.1)
    }

    func testTheGameWaitsOnTheMenu() {
        let g = Game(seed: 1)
        XCTAssertEqual(g.ui.screen, .menu)
        for _ in 0..<120 { g.update(1.0 / 60) }
        XCTAssertEqual(g.progress.money, 0)
        let r = Renderer()
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .play)!)))
        XCTAssertEqual(g.ui.screen, .game)
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .openMenu)!)))
        XCTAssertEqual(g.ui.screen, .menu, "MENU goes back to the menu")
    }

    func testResetNeedsTwoTaps() {
        var p = Progress(); p.stars = 4; p.maxLevel = 5; p.level = 5
        let g = Game(progress: p)
        g.ui.screen = .settings
        let r = Renderer()
        r.render(g)
        let reset = centre(hitRect(g, .resetProgress)!)
        g.handle(.tap(reset, time: 1))
        XCTAssertEqual(g.progress.stars, 4)
        r.render(g)
        g.handle(.tap(reset, time: 2))
        XCTAssertEqual(g.progress.stars, 0)
        XCTAssertEqual(g.progress.level, 1)
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

    func testOldAndFutureSavesAreNotLoaded() {
        XCTAssertNil(SaveCodec.decode(Data(#"{"version": 99, "progress": {}, "savedAt": 0}"#.utf8)))
        XCTAssertNil(SaveCodec.decode(Data(#"{"version": 1, "progress": {}, "savedAt": 0}"#.utf8)))
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

    /// Tapping a ball row opens its sheet; the sheet's BUY button buys one.
    func testTappingABallRowOpensItsSheetAndBuyBuys() {
        var p = Progress(); p.money = 1000
        let (g, r) = play(p)
        g.handle(.tap(centre(hitRect(g, .ballRow(.basic))!)))
        XCTAssertEqual(g.ui.sheet, .basic)
        XCTAssertEqual(g.balls.count, 1, "a tap on the row never buys")
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .buyBall(.basic))!)))
        XCTAssertEqual(g.balls.count, 2)
        XCTAssertEqual(g.progress.money, 975)
    }

    /// Slingshot: drag from a ball row and let go; the ball flies the opposite way.
    func testDraggingABallRowAimsAndBuysOnRelease() {
        var p = Progress(); p.money = 1000
        let (g, _) = play(p)
        let from = centre(hitRect(g, .ballRow(.basic))!)
        let to = Point(from.x + 30, from.y + 40)
        g.handle(.drag(from: from, to: Point(from.x + 5, from.y)))
        g.handle(.drag(from: Point(from.x + 5, from.y), to: to))
        XCTAssertNotNil(g.ui.aim)
        XCTAssertEqual(g.balls.count, 1, "nothing is bought while aiming")
        XCTAssertFalse(g.predictPath(g.ui.aim!.direction!).isEmpty, "the preview shows a path")
        g.handle(.release(to))
        XCTAssertNil(g.ui.aim)
        XCTAssertEqual(g.balls.count, 2)
        let b = g.balls.last!
        XCTAssertEqual(b.vx, -0.6, accuracy: 1e-9)
        XCTAssertEqual(b.vy, -0.8, accuracy: 1e-9)
    }

    func testAShortPullCancelsTheAim() {
        var p = Progress(); p.money = 1000
        let (g, _) = play(p)
        let from = centre(hitRect(g, .ballRow(.basic))!)
        g.handle(.drag(from: from, to: Point(from.x + 4, from.y)))
        g.handle(.release(Point(from.x + 4, from.y)))
        XCTAssertEqual(g.balls.count, 1)
        XCTAssertEqual(g.progress.money, 1000)
    }

    /// Only balls break pixels: taps, double-taps, long-presses and drags on the board never
    /// damage anything.
    func testTouchingTheBoardNeverDamagesPixels() {
        let (g, r) = play(seed: 4)
        g.balls.removeAll()
        let b = g.board
        let hp = b.hp
        let L = g.ui.layout
        var t = 1.0
        for y in stride(from: L.board.y + 5, to: L.board.maxY, by: 23) {
            for x in stride(from: L.board.x + 5, to: L.board.maxX, by: 23) {
                g.handle(.tap(Point(x, y), time: t)); t += 1
                g.handle(.longPress(Point(x, y)))
                g.handle(.drag(from: Point(x, y), to: Point(x + 2, y + 1)))
                g.handle(.release(Point(x + 2, y + 1)))
                r.render(g)
            }
        }
        XCTAssertEqual(b.hp, hp)
        XCTAssertEqual(g.progress.money, 0)
    }

    func testTappingTheBoardSaysWhatIsThere() {
        let (g, _) = play(seed: 4)
        let b = g.board
        let i = b.kind.indices.first { b.kind[$0] == .block && b.revealed[$0] }!
        XCTAssertEqual(g.describe(cellX: i % b.size, cellY: i / b.size)?.first, "PIXEL")
        let hidden = b.kind.indices.first { b.kind[$0] == .block && !b.revealed[$0] }!
        XCTAssertNil(g.describe(cellX: hidden % b.size, cellY: hidden / b.size), "nothing about the dark")
    }

    func testLongPressShowsDetailsWithoutBuying() {
        var p = Progress(); p.money = 1000
        let (g, _) = play(p)
        let coins = g.ui.hits.first { $0.info.first == "COINS" }!
        g.handle(.longPress(centre(coins.rect)))
        XCTAssertNotNil(g.ui.tooltip)
        XCTAssertEqual(g.progress.money, 1000)
    }

    func testTheTreeSelectsThenBuys() {
        var p = Progress(); p.shards = 5
        let (g, r) = play(p)
        g.handle(.tap(centre(hitRect(g, .openSkills)!)))
        XCTAssertTrue(g.ui.skillsOpen)
        r.render(g)
        let node = hitRect(g, .selectSkill("core"))!
        g.handle(.tap(centre(node)))
        XCTAssertEqual(g.ui.selectedSkill, "core")
        XCTAssertEqual(g.progress.skillRanks["core"] ?? 0, 0, "selecting never buys")
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .buySkill("core"))!)))
        XCTAssertEqual(g.progress.skillRanks["core"], 1)
        XCTAssertEqual(g.progress.shards, 4)
        r.render(g)
        XCTAssertNil(hitRect(g, .selectSkill("u-ghost")), "locked nodes are hidden")
        XCTAssertNotNil(hitRect(g, .selectSkill("sharp")), "the next ones appear")
    }

    func testTreeZoomRestsAtHalfOneOrTwo() {
        let (g, r) = play()
        g.handle(.tap(centre(hitRect(g, .openSkills)!)))
        r.render(g)
        for (f, z) in [(0.6, 0.5), (1.7, 2.0), (1.1, 1.0)] {
            g.ui.treeCamera = UIState().treeCamera
            g.handle(.pinch(center: Point(200, 150), factor: f, dx: 0, dy: 0))
            g.handle(.pinchEnded)
            for _ in 0..<120 { g.update(1.0 / 60) }
            XCTAssertEqual(g.ui.treeCamera.zoom, z, accuracy: 1e-9)
        }
        XCTAssertEqual(g.ui.camera.zoom, 1, "pinching the tree leaves the board alone")
    }
}
