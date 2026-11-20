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
        XCTAssertEqual(g.balls.count, 0, "a fresh level starts with no balls")
        XCTAssertEqual(g.progress.money, Tuning.startCoins)
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
        XCTAssertTrue(g.buyBall(.basic))
        XCTAssertEqual(g.progress.money, 0)
        for _ in 0..<(60 * 60) { g.update(1.0 / 60) }
        XCTAssertGreaterThan(g.progress.money, 0)
        XCTAssertEqual(g.progress.money, g.progress.runEarnings, accuracy: 1e-6)
        XCTAssertEqual(g.progress.levelTime, 60, accuracy: 0.1)
    }

    func testTheGameWaitsOnTheMenu() {
        let g = Game(seed: 1)
        XCTAssertEqual(g.ui.screen, .menu)
        g.buyBall(.basic)
        for _ in 0..<120 { g.update(1.0 / 60) }
        XCTAssertEqual(g.progress.money, 0, "nothing earns behind the menu")
        let r = Renderer()
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .play)!)))
        XCTAssertEqual(g.ui.screen, .game)
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .pause)!)))
        XCTAssertTrue(g.ui.paused, "MENU pauses the game")
        let t = g.time, lt = g.progress.levelTime
        for _ in 0..<60 { g.update(1.0 / 60) }
        XCTAssertEqual(g.progress.levelTime, lt, "nothing runs while paused")
        XCTAssertGreaterThan(g.time, t)
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .openMenu)!)))
        XCTAssertEqual(g.ui.screen, .menu, "MAIN MENU goes back to the menu")
        XCTAssertFalse(g.ui.paused)
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
        let data = SaveCodec.encode(g.saveFile())
        let s = SaveCodec.decode(data)!
        XCTAssertEqual(s.version, SaveFile.currentVersion)
        let g2 = Game()
        g2.load(s)
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

    func testClosedGameIsPausedNotPaid() {
        // A save written hours ago (with the old offline fields) loads with the same money
        // and no banner: nothing happens while the game is closed.
        let json = #"{"version": 2, "savedAt": 0, "progress": {"money": 250, "level": 1, "maxLevel": 1, "stars": 0, "shards": 0, "skillRanks": {"u-basic": 1, "offline": 2}, "balls": {}, "runEarnings": 0, "totalEarnings": 0, "incomeRate": 50, "levelTime": 0, "lastClearTime": 0, "settings": {}}}"#
        guard let s = SaveCodec.decode(Data(json.utf8)) else { return XCTFail("old save should still load") }
        let g = Game()
        g.load(s)
        XCTAssertEqual(g.progress.money, 250)
        XCTAssertTrue(g.banners.isEmpty)
        XCTAssertEqual(g.progress.shards, 2, "shards spent on the removed Idle node come back")
        XCTAssertNil(g.progress.skillRanks["offline"])
    }

    func testGestures() {
        var t = PointerTracker()
        XCTAssertEqual(t.began(Point(10, 10), at: 0), [.down(Point(10, 10))])
        XCTAssertEqual(t.ended(Point(11, 10), at: 0.1), [.tap(Point(11, 10), time: 0.1)])

        _ = t.began(Point(10, 10), at: 0)
        XCTAssertEqual(t.tick(at: 0.1), [])
        XCTAssertEqual(t.tick(at: 0.25), [.hold(Point(10, 10))], "a short hold comes first")
        XCTAssertEqual(t.tick(at: 0.3), [])
        XCTAssertEqual(t.tick(at: 0.5), [.longPress(Point(10, 10))])
        XCTAssertEqual(t.ended(Point(10, 10), at: 0.6), [.release(Point(10, 10))])

        _ = t.began(Point(10, 10), at: 0)
        XCTAssertEqual(t.moved(Point(20, 10), at: 0.05), [.drag(from: Point(10, 10), to: Point(20, 10))])
        XCTAssertEqual(t.tick(at: 1), [], "a drag never turns into a long-press")
        XCTAssertEqual(t.ended(Point(20, 10), at: 1), [.release(Point(20, 10))])
    }

    /// Tapping a ball row selects that type; tapping it again (or holding it) opens its sheet,
    /// whose BUY button buys one.
    func testTappingABallRowSelectsItThenOpensItsSheet() {
        var p = Progress(); p.money = 1000; p.skillRanks["u-fast"] = 1
        let (g, r) = play(p)
        XCTAssertEqual(g.ui.selected, .basic)
        g.handle(.tap(centre(hitRect(g, .ballRow(.fast))!)))
        XCTAssertEqual(g.ui.selected, .fast)
        XCTAssertNil(g.ui.sheet)
        XCTAssertTrue(g.balls.isEmpty, "a tap on the row never buys")
        g.handle(.tap(centre(hitRect(g, .ballRow(.fast))!)))
        XCTAssertEqual(g.ui.sheet, .fast)
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .buyBall(.fast))!)))
        XCTAssertEqual(g.balls.count, 1)
        XCTAssertEqual(g.balls[0].kind, .fast)
        g.ui.sheet = nil
        r.render(g)
        g.handle(.longPress(centre(hitRect(g, .ballRow(.basic))!)))
        XCTAssertEqual(g.ui.sheet, .basic, "holding a row opens its sheet")
        XCTAssertEqual(g.ui.selected, .basic)
    }

    /// Locked types don't get a row at all.
    func testOnlyUnlockedBallsHaveRows() {
        let (g, _) = play()
        XCTAssertNotNil(hitRect(g, .ballRow(.basic)))
        for k in BallKind.allCases where k != .basic { XCTAssertNil(hitRect(g, .ballRow(k))) }
    }

    /// The canvas point at the centre of board cell (x, y).
    func canvasPoint(_ g: Game, _ x: Int, _ y: Int) -> Point {
        let cp = Tuning.cellPixels
        let v = g.ui.camera.toView(Double(x * cp + cp / 2), Double(y * cp + cp / 2))
        return Point(g.ui.layout.board.x + Int(v.x), g.ui.layout.board.y + Int(v.y))
    }

    /// Hold an open spot on the board briefly, then pull: a ball of the selected type appears
    /// right where you held and flies the opposite way, like a slingshot.
    func testHoldAndDragPlacesABallWhereYouHeldAndAimsIt() {
        var p = Progress(); p.money = 1000
        let (g, _) = play(p)
        let sp = g.board.spawn
        let from = canvasPoint(g, sp.x, sp.y)
        let to = Point(from.x + 30, from.y - 40)
        g.handle(.down(from))
        XCTAssertNil(g.ui.launch, "nothing until the hold")
        g.handle(.hold(from))
        XCTAssertEqual(g.ui.launch, LaunchDrag(from: from, to: from))
        g.handle(.drag(from: from, to: Point(from.x + 3, from.y - 4)))
        g.handle(.drag(from: Point(from.x + 3, from.y - 4), to: to))
        XCTAssertEqual(g.ui.launch?.to, to, "the preview follows the finger")
        XCTAssertEqual(g.ui.launch?.pulledAt, g.time, "the hold ring starts fading with the pull")
        XCTAssertTrue(g.balls.isEmpty, "nothing is bought until you let go")
        let camera = g.ui.camera
        g.handle(.release(to))
        XCTAssertEqual(g.ui.camera, camera, "aiming never pans")
        XCTAssertNil(g.ui.launch)
        XCTAssertEqual(g.balls.count, 1)
        let b = g.balls[0]
        XCTAssertEqual(Int(b.x), sp.x); XCTAssertEqual(Int(b.y), sp.y)
        // Slingshot: pulled up and to the right, it flies down and to the left.
        XCTAssertEqual(b.vx, -0.6, accuracy: 1e-9)
        XCTAssertEqual(b.vy, 0.8, accuracy: 1e-9)
        XCTAssertEqual(g.progress.money, 1000 - Tuning.startCoins)
        // A plain tap on an open spot launches along the last direction.
        g.handle(.down(from)); g.handle(.tap(from, time: 5))
        XCTAssertEqual(g.balls.count, 2)
        XCTAssertEqual(g.balls[1].vx, -0.6, accuracy: 1e-9)
    }

    /// A quick drag pans, even from an open spot: only a hold places a ball.
    func testAQuickDragFromAnOpenSpotPans() {
        var p = Progress(); p.money = 1000
        let (g, _) = play(p)
        let from = canvasPoint(g, g.board.spawn.x, g.board.spawn.y)
        let before = g.ui.camera.origin
        g.handle(.down(from))
        g.handle(.drag(from: from, to: Point(from.x + 8, from.y)))
        g.handle(.hold(from))
        g.handle(.release(Point(from.x + 8, from.y)))
        XCTAssertNotEqual(g.ui.camera.origin.x, before.x)
        XCTAssertNil(g.ui.launch)
        XCTAssertTrue(g.balls.isEmpty)
    }

    /// A drag that starts on a block (or the dark) pans; it never places a ball.
    func testDraggingFromABlockPans() {
        var p = Progress(); p.money = 1000
        let (g, _) = play(p)
        let b = g.board
        let i = b.kind.indices.first { b.kind[$0] == .block && b.revealed[$0] }!
        let from = canvasPoint(g, i % b.size, i / b.size)
        let before = g.ui.camera.origin
        g.handle(.down(from))
        XCTAssertNil(g.ui.launch)
        g.handle(.drag(from: from, to: Point(from.x + 8, from.y)))
        g.handle(.release(Point(from.x + 8, from.y)))
        XCTAssertNotEqual(g.ui.camera.origin.x, before.x)
        XCTAssertTrue(g.balls.isEmpty)
    }

    func testPlacingWithoutCoinsSaysSoAndBuysNothing() {
        var p = Progress(); p.money = 3
        let (g, _) = play(p)
        let from = canvasPoint(g, g.board.spawn.x, g.board.spawn.y)
        g.handle(.down(from))
        g.handle(.tap(from, time: 1))
        XCTAssertTrue(g.balls.isEmpty)
        XCTAssertEqual(g.progress.money, 3)
        XCTAssertEqual(g.ui.tooltip?.lines.first, "NEED " + coins(g.ballCost(.basic)) + " COINS")
    }

    /// Restart lives in the pause card and asks first: CANCEL keeps the run, RESTART starts the
    /// level over.
    func testRestartLevelFromThePauseCardAsksFirst() {
        var p = Progress(); p.level = 2; p.maxLevel = 2; p.money = 900; p.levelTime = 40; p.totalEarnings = 900
        p.balls[BallKind.basic.rawValue] = BallProgress(owned: 5)
        let (g, r) = play(p)
        g.handle(.tap(centre(hitRect(g, .pause)!)))
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .restartLevel)!)))
        XCTAssertTrue(g.ui.confirmingRestart)
        XCTAssertEqual(g.progress.money, 900, "asking changes nothing")
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .cancelRestart)!)))
        XCTAssertFalse(g.ui.confirmingRestart)
        XCTAssertEqual(g.progress.money, 900)
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .restartLevel)!)))
        r.render(g)
        g.handle(.tap(centre(hitRect(g, .confirmRestart)!)))
        XCTAssertFalse(g.ui.paused)
        XCTAssertEqual(g.ui.screen, .game)
        XCTAssertEqual(g.progress.level, 2)
        XCTAssertEqual(g.progress.money, Tuning.startCoins)
        XCTAssertTrue(g.balls.isEmpty)
        XCTAssertEqual(g.progress.levelTime, 0)
    }

    /// A sniper re-aims after a bounce, but only at pixels ahead of it: never straight back
    /// into the pixel it just hit (that hit it every physics step).
    func testSniperNeverTurnsBackIntoThePixelItHit() {
        var p = Progress(); p.skillRanks["u-sniper"] = 1
        let (g, _) = play(p)
        let b = g.board
        for i in b.kind.indices where b.kind[i] == .block {
            let x = i % b.size, y = i / b.size
            guard b.inside(x - 1, y), b.kind[b.index(x - 1, y)] == .empty else { continue }
            // Just bounced off the block on its right: now heading left.
            var ball = Ball(kind: .sniper, x: Double(x) - 0.3, y: Double(y) + 0.5, vx: -1, vy: 0)
            g.aim(&ball, fromX: ball.x, fromY: ball.y)
            XCTAssertLessThan(ball.vx, 0, "still heading away from the block at \(x),\(y)")
        }
    }

    /// Hidden shards: only the couple nearest the light show through the dark.
    func testOnlyACoupleOfSensedShardsShowAtOnce() {
        for level in 1...5 {
            let b = LevelGen.make(level: level)
            let shown = Fog.shownShards(b)
            XCTAssertLessThanOrEqual(shown.count, Tuning.maxSensedShards)
            for i in shown { XCTAssertTrue(Fog.shardSensed(b, i)) }
        }
    }

    /// Only balls break pixels: taps, long-presses and drags on the board never damage
    /// anything (with no coins, a tap can't even buy a ball).
    func testTouchingTheBoardNeverDamagesPixels() {
        var p = Progress(); p.money = 0
        let (g, r) = play(p, seed: 4)
        g.balls.removeAll()
        let b = g.board
        let hp = b.hp
        let L = g.ui.layout
        var t = 1.0
        for y in stride(from: L.board.y + 5, to: L.board.maxY, by: 23) {
            for x in stride(from: L.board.x + 5, to: L.board.maxX, by: 23) {
                g.handle(.down(Point(x, y)))
                g.handle(.tap(Point(x, y), time: t)); t += 1
                g.handle(.down(Point(x, y)))
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
