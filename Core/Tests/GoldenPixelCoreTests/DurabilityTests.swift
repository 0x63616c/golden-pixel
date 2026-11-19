import XCTest
@testable import GoldenPixelCore

/// Durability is colour alone: a block walks down crimson > pink > amber > lime > green >
/// grey, one step per hit unit, and the hit after grey breaks it.
final class DurabilityTests: XCTestCase {
    func testFreshBlocksShowTheirTierColour() {
        for level in [1, 4, 9] {
            for tier in 0..<5 {
                let step = Economy.ladderStep(hp: Economy.tierHP(tier, level: level), level: level)
                XCTAssertEqual(step, tier + 1)
                XCTAssertEqual(Palette.ladder[step], Palette.tiers[tier])
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
        XCTAssertEqual(steps, [5, 4, 3, 2, 1, 0], "crimson, pink, amber, lime, green, grey")
        XCTAssertEqual(b.kind[i], .empty, "the hit after grey breaks it")
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
        let L = { g.ui.layout }
        let cp = Tuning.cellPixels
        func cellColours() -> Set<Pixel> {
            var s = Set<Pixel>()
            for y in 0..<cp { for x in 0..<cp { s.insert(r.canvas.get(L().board.x + (i % b.size) * cp + x, L().board.y + (i / b.size) * cp + y) & 0x00ff_ffff) } }
            return s
        }
        _ = g.damageCell(i, Economy.hitUnit(level: b.level) * 2)
        r.render(g)
        XCTAssertEqual(cellColours(), [Palette.white & 0x00ff_ffff], "hit frame: solid white")
        g.time += 1.0 / 30
        r.render(g)
        XCTAssertEqual(cellColours(), [Palette.ladder[3] & 0x00ff_ffff], "then one flat colour: no cracks")
    }

    func testWallsAreClearlyBrighterThanGreyBlocks() {
        func luma(_ p: Pixel) -> Double { 0.2126 * Double(p.red) + 0.7152 * Double(p.green) + 0.0722 * Double(p.blue) }
        XCTAssertGreaterThan(luma(Palette.wall) - luma(Palette.ladder[0]), 120)
        XCTAssertGreaterThan(luma(Palette.wallShade) - luma(Palette.ladderLight[0]), 25, "even a wall's shadow beats a grey block's highlight")
    }
}
