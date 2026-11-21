import XCTest
@testable import GoldenPixelCore

/// How balls bounce: at the exact point of contact, the same at any frame rate, mirrored in
/// the surface they touch, and turned only to break a loop that touches nothing but walls.
final class PhysicsTests: XCTestCase {
    /// An empty square room of `w` cells, walled all round, with one ball in the middle.
    func room(_ w: Int = 12, kind: BallKind = .basic, vx: Double = 1, vy: Double = 0, seed: UInt64 = 1) -> (Game, Int) {
        let g = Game(seed: seed)
        g.ui.screen = .game
        let b = g.board
        for i in b.kind.indices { b.kind[i] = .wall; b.hp[i] = 0 }
        let c = b.size / 2
        for y in (c - w / 2)..<(c + w / 2) { for x in (c - w / 2)..<(c + w / 2) { b.kind[b.index(x, y)] = .empty } }
        b.spawn = Point(c, c)
        g.balls = [Ball(kind: kind, x: Double(c) + 0.5, y: Double(c) + 0.5, vx: vx, vy: vy)]
        return (g, c)
    }

    /// Puts a pixel that never breaks at (x, y) and returns its index.
    @discardableResult
    func rock(_ g: Game, _ x: Int, _ y: Int) -> Int {
        let i = g.board.index(x, y)
        g.board.kind[i] = .block; g.board.hp[i] = 1e9; g.board.maxHP[i] = 1e9
        return i
    }

    /// Steps the game until the ball's direction changes, and returns the new direction.
    func nextBounce(_ g: Game, hz: Double = 120, limit: Double = 20) -> (vx: Double, vy: Double)? {
        let was = (g.balls[0].vx, g.balls[0].vy)
        for _ in 0..<Int(limit * hz) {
            g.update(1 / hz)
            let b = g.balls[0]
            if b.vx != was.0 || b.vy != was.1 { return (b.vx, b.vy) }
        }
        return nil
    }

    /// A level shot at a flat wall comes back exactly level, along the line it went out on.
    func testALevelShotComesStraightBack() {
        let (g, c) = room()
        let out = nextBounce(g)
        XCTAssertEqual(out?.vx, -1)
        XCTAssertEqual(out?.vy, 0)
        XCTAssertEqual(g.balls[0].y, Double(c) + 0.5)
        let back = nextBounce(g)
        XCTAssertEqual(back?.vx, 1)
        XCTAssertEqual(back?.vy, 0)
    }

    /// The same shot bounces the same way whatever the frame rate and wherever its steps
    /// happen to land, and the way the geometry says: a ball clipping a corner turns by
    /// 180 degrees less twice the angle its center makes with the corner.
    func testABounceDoesNotDependOnFrameRateOrStepPhase() {
        // The ball's center flies 2 art pixels (0.2 cells) above the block's top edge: it
        // catches the corner at sin = 0.8, cos = 0.6, and leaves along (0.28, -0.96).
        for hz in [20.0, 60, 120, 240] {
            for k in 0..<12 {
                let (g, c) = room()
                let i = rock(g, c + 3, c)
                g.balls[0] = Ball(kind: .basic, x: Double(c) - 2 + Double(k) * 0.013, y: Double(c) - 0.2, vx: 1, vy: 0)
                let out = nextBounce(g, hz: hz)
                XCTAssertEqual(out?.vx ?? 0, 0.28, accuracy: 1e-9, "\(hz) fps, start \(k)")
                XCTAssertEqual(out?.vy ?? 0, -0.96, accuracy: 1e-9, "\(hz) fps, start \(k)")
                XCTAssertLessThan(g.board.hp[i], 1e9, "the corner it clipped took the hit")
            }
        }
    }

    /// A ball only damages what it touches, and what it touches turns it.
    func testANearMissTouchesNothing() {
        let (g, c) = room()
        let i = rock(g, c + 3, c)
        // Its edge passes a hair (0.1 art pixels) over the block.
        g.balls[0] = Ball(kind: .basic, x: Double(c) - 2, y: Double(c) - 0.26, vx: 1, vy: 0)
        for _ in 0..<60 { g.update(1.0 / 60) }
        XCTAssertGreaterThan(g.balls[0].x, Double(c) + 4, "it flew on past the block")
        XCTAssertEqual(g.balls[0].vy, 0)
        XCTAssertEqual(g.board.hp[i], 1e9)
    }

    /// Cells packed side by side are one flat surface: a ball landing on the seam between two
    /// of them is mirrored like anywhere else, never thrown off by a corner inside the wall.
    func testAWallOfCellsIsOneFlatSurface() {
        let s = 0.5.squareRoot()
        for k in 0..<40 {
            let (g, c) = room()
            // Down and to the right at the floor, landing all along two cells (seams included).
            g.balls[0] = Ball(kind: .basic, x: Double(c) - 3 + Double(k) * 0.05, y: Double(c) + 3, vx: s, vy: s)
            let out = nextBounce(g)
            XCTAssertEqual(out?.vx ?? 0, s, accuracy: 1e-12, "start \(k)")
            XCTAssertEqual(out?.vy ?? 0, -s, accuracy: 1e-12, "start \(k)")
        }
    }

    /// A ball going round a loop that touches only walls would never earn again: the first
    /// time it repeats a bounce it is turned, so no such loop lasts. The last shot goes round
    /// a square room in 14 bounces, which is why a ball remembers more than a handful.
    func testALoopThatTouchesOnlyWallsIsBroken() {
        let s = 0.5.squareRoot()
        for (vx, vy) in [(1.0, 0.0), (0.0, -1.0), (s, s), (0.6, 0.8)] {
            let (g, _) = room(vx: vx, vy: vy)
            var seen: [String: Int] = [:]
            while g.time < 90, nextBounce(g) != nil {
                let b = g.balls[0]
                seen[String(format: "%.4f %.4f %.4f %.4f", b.x, b.y, b.vx, b.vy), default: 0] += 1
            }
            XCTAssertGreaterThan(seen.count, 40, "from \(vx), \(vy)")
            XCTAssertLessThanOrEqual(seen.values.max() ?? 0, 2, "from \(vx), \(vy): the same bounce again and again")
        }
    }

    /// A loop that hits a pixel is doing its job, and is left exactly as it is.
    func testALoopThatHitsAPixelIsLeftAlone() {
        let (g, c) = room()
        let i = rock(g, c + 3, c)
        for _ in 0..<(30 * 120) {
            g.update(1.0 / 120)
            XCTAssertEqual(g.balls[0].vy, 0)
            XCTAssertEqual(g.balls[0].y, Double(c) + 0.5)
        }
        // About one hit on the block every 16 cells flown, for 30 seconds at 9 cells a second.
        XCTAssertLessThan(g.board.hp[i], 1e9 - 10)
    }

    /// A heavy ball flies straight on through a pixel it breaks, and bounces off the one that stops it.
    func testAHeavyBallCarriesOnThroughWhatItBreaks() {
        var p = Progress(); p.skillRanks["u-heavy"] = 1
        let g = Game(progress: p, seed: 1)
        g.ui.screen = .game
        let b = g.board
        for i in b.kind.indices { b.kind[i] = .wall; b.hp[i] = 0 }
        let c = b.size / 2
        for y in (c - 6)..<(c + 6) { for x in (c - 6)..<(c + 6) { b.kind[b.index(x, y)] = .empty } }
        b.spawn = Point(c, c)
        let pierce = g.basePierce(.heavy)
        XCTAssertGreaterThan(pierce, 0)
        // A row of one-hit pixels with a rock behind them.
        for n in 0..<pierce { let i = b.index(c + 2 + n, c); b.kind[i] = .block; b.hp[i] = 1; b.maxHP[i] = 1 }
        let last = rock(g, c + 2 + pierce, c)
        var ball = Ball(kind: .heavy, x: Double(c) + 0.5, y: Double(c) + 0.5, vx: 1, vy: 0)
        ball.pierce = pierce
        g.balls = [ball]
        let out = nextBounce(g)
        XCTAssertEqual(out?.vx, -1)
        for n in 0..<pierce { XCTAssertEqual(b.kind[b.index(c + 2 + n, c)], .empty) }
        XCTAssertLessThan(b.hp[last], 1e9)
    }

    /// A sniper re-aims after every bounce, but never through the surface it is touching:
    /// with its target behind the ledge it just hit, it keeps the plain bounce and flies on
    /// (aiming into the ledge would pin it there, bouncing on the spot).
    func testASniperDoesNotAimThroughWhatItTouches() {
        let (g, c) = room(kind: .sniper, vx: -0.6, vy: -0.8)
        // A ledge of wall above the ball, and the only pixel in range up behind it.
        for x in (c - 4)...(c + 1) { g.board.kind[g.board.index(x, c - 2)] = .wall }
        rock(g, c - 4, c - 3)
        let out = nextBounce(g)
        XCTAssertEqual(out?.vx ?? 0, -0.6, accuracy: 1e-9)
        XCTAssertEqual(out?.vy ?? 0, 0.8, accuracy: 1e-9)
        let from = (g.balls[0].x, g.balls[0].y)
        for _ in 0..<12 { g.update(1.0 / 120) }
        XCTAssertGreaterThan(abs(g.balls[0].y - from.1), 0.5, "it left the ledge")
    }

    /// A ball's direction is a unit vector and stays one: every bounce is worked out as if it
    /// were, so an error left to grow from bounce to bounce ends with balls at any speed.
    func testABallsDirectionStaysAUnitVector() {
        let g = Scenes.make("late")
        for _ in 0..<(60 * 60) { g.update(1.0 / 60) }
        XCTAssertFalse(g.balls.isEmpty)
        for b in g.balls { XCTAssertEqual(b.vx * b.vx + b.vy * b.vy, 1, accuracy: 1e-12, "a \(b.kind) ball") }
    }

    /// However a level is dug, balls stay in open space: never inside a pixel or a wall.
    func testBallsNeverEndAStepInsideASolidCell() {
        for scene in ["mid", "late"] {
            let g = Scenes.make(scene)
            let r = Tuning.ballRadius
            for _ in 0..<(20 * 60) {
                g.update(1.0 / 60)
                for b in g.balls where b.phaseLeft <= 0 {
                    for cy in Int((b.y - r).rounded(.down))...Int((b.y + r).rounded(.down)) {
                        for cx in Int((b.x - r).rounded(.down))...Int((b.x + r).rounded(.down)) where g.board.kindAt(cx, cy) != .empty {
                            let px = min(max(b.x, Double(cx)), Double(cx + 1)), py = min(max(b.y, Double(cy)), Double(cy + 1))
                            let d = ((b.x - px) * (b.x - px) + (b.y - py) * (b.y - py)).squareRoot()
                            XCTAssertGreaterThan(d, r - 1e-6, "\(scene): a \(b.kind) ball overlaps the cell at \(cx),\(cy)")
                        }
                    }
                }
            }
        }
    }
}
