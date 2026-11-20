import XCTest
@testable import GoldenPixelCore

/// Durability is lightness alone: a block is one blue hue that walks up from deep (tough) to
/// pale (one hit left), one step per hit unit, and the hit after that breaks it.
final class DurabilityTests: XCTestCase {
    /// One shade is one hit: an unupgraded basic ball takes a block down exactly one shade per
    /// hit on every level, and the palest shade breaks on the next hit.
    func testOneShadeIsOneBasicHit() {
        XCTAssertEqual(BallKind.basic.type.damage, 1)
        for level in [1, 3, 7, 12] {
            XCTAssertEqual(Economy.hitUnit(level: level), 1)
            let b = LevelGen.make(level: level)
            let g = Game(progress: { var p = GoldenPixelCore.Progress(); p.level = level; return p }())
            XCTAssertEqual(g.damage(.basic), 1, "no stars, no skills")
            for i in b.kind.indices where b.kind[i] == .block {
                let shades = Economy.ladderStep(hp: b.hp[i], level: level) + 1
                XCTAssertEqual(b.hp[i], Double(shades), "level \(level): a block's HP is its shade count")
            }
        }
    }

    /// Shard pixels break in one hit; the golden pixel is the level's boss, far tougher than
    /// any block and tougher every level.
    func testShardsBreakInOneHitAndTheGoldIsTough() {
        for level in 1...7 {
            let b = LevelGen.make(level: level)
            for i in b.kind.indices where b.kind[i] == .shard { XCTAssertEqual(b.hp[i], 1) }
            let gold = b.hp[b.index(b.gold.x, b.gold.y)]
            XCTAssertGreaterThanOrEqual(gold, 50 * Tuning.tierHP.max()!, "level \(level)")
            if level > 1 { XCTAssertGreaterThan(gold, LevelGen.make(level: level - 1).hp[{ let p = LevelGen.make(level: level - 1); return p.index(p.gold.x, p.gold.y) }()]) }
        }
    }

    func testFreshBlocksShowTheirTierColour() {
        for level in [1, 4, 9] {
            for tier in 0..<5 {
                let step = Economy.ladderStep(hp: Economy.tierHP(tier, level: level), level: level)
                XCTAssertEqual(step, tier + 1)
                XCTAssertEqual(Palette.ladder[step], Palette.tier(tier))
            }
        }
    }

    func testEachHitStepsDownToGreyThenBreaks() {
        let g = Game(seed: 6)
        g.ui.started = true
        let b = g.board
        let i = b.kind.indices.first { b.kind[$0] == .block && b.tier[$0] == 4 }!
        let unit = Economy.hitUnit(level: b.level)
        var steps: [Int] = [Economy.ladderStep(hp: b.hp[i], level: b.level)]
        while b.kind[i] == .block {
            _ = g.damageCell(i, unit)
            if b.kind[i] == .block { steps.append(Economy.ladderStep(hp: b.hp[i], level: b.level)) }
        }
        XCTAssertEqual(steps, [5, 4, 3, 2, 1, 0], "bright to faint")
        XCTAssertEqual(b.kind[i], .empty, "the hit after the faintest step breaks it")
    }

    func testStrongerHitsSkipSteps() {
        let g = Game(seed: 6)
        let b = g.board
        let i = b.kind.indices.first { b.kind[$0] == .block && b.tier[$0] == 4 }!
        _ = g.damageCell(i, Economy.hitUnit(level: b.level) * 3)
        XCTAssertEqual(Economy.ladderStep(hp: b.hp[i], level: b.level), 2)
        _ = g.damageCell(i, Economy.hitUnit(level: b.level) * 0.5)
        XCTAssertEqual(Economy.ladderStep(hp: b.hp[i], level: b.level), 2, "half a unit isn't a step yet")
    }

    func testAHitFlashesWhiteForOneFrameAndNoCrackMarks() {
        let g = Game(seed: 6)
        g.ui.started = true
        let b = g.board
        for k in b.revealed.indices { b.revealed[k] = true; b.revealedAt[k] = -10 }
        g.balls.removeAll()
        let i = b.kind.indices.first { k in
            let x = k % b.size, y = k / b.size
            return b.kind[k] == .block && b.tier[k] == 4 && !b.rich[k] &&
                [(0, 1), (1, 0), (0, -1), (-1, 0)].allSatisfy { b.kindAt(x + $0.0, y + $0.1) != .empty }
        }!
        let r = Renderer()
        let cp = Tuning.cellPixels
        g.ui.camera.look(at: Double((i % b.size) * cp), Double((i / b.size) * cp))
        func cellColours() -> Set<Pixel> {
            var s = Set<Pixel>()
            let L = g.ui.layout, o = g.ui.camera.origin
            for y in 0..<cp { for x in 0..<cp {
                s.insert(r.canvas.get(L.board.x + Int(o.x) + (i % b.size) * cp + x, L.board.y + Int(o.y) + (i / b.size) * cp + y).rgbOnly)
            } }
            return s
        }
        _ = g.damageCell(i, Economy.hitUnit(level: b.level) * 2)
        r.render(g)
        XCTAssertEqual(cellColours(), [Palette.white & 0x00ff_ffff], "hit frame: solid white")
        g.time += 1.0 / 30
        r.render(g)
        XCTAssertEqual(cellColours(), [Palette.ladder[3] & 0x00ff_ffff], "then one flat colour: no cracks")
    }

    /// Blocks are one hue (blue, lighter as they wear down, so lighter = weaker); walls are a
    /// neutral dark grey that never outshines a block, so nothing pale sits out in the dark.
    func testBlocksAreOneBlueRampAndWallsAreDarkGrey() {
        func luma(_ p: Pixel) -> Double { 0.2126 * Double(p.red) + 0.7152 * Double(p.green) + 0.0722 * Double(p.blue) }
        for (a, b) in zip(Palette.ladder, Palette.ladder.dropFirst()) { XCTAssertGreaterThan(luma(a), luma(b), "pale = one hit left") }
        for p in Palette.ladder { XCTAssertGreaterThan(p.blue, p.red); XCTAssertGreaterThan(p.blue, p.green) }
        let w = Palette.wall
        XCTAssertEqual(Int(w.red), Int(w.green), accuracy: 4); XCTAssertEqual(Int(w.green), Int(w.blue), accuracy: 4)
        XCTAssertLessThan(luma(w), luma(Palette.ladder.last!))
    }
}
