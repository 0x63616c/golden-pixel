import XCTest
@testable import GoldenPixelCore

final class FogTests: XCTestCase {
    /// The fog rule: a cell is visible exactly when it is within 3 cells (Chebyshev) of an
    /// open cell. At level start the only open cells are the spawn pocket.
    func testLevelStartsAsSpawnPocketPlusAThreeCellBorder() {
        XCTAssertEqual(Tuning.revealRadius, 3)
        for level in 1...10 {
            let b = LevelGen.make(level: level)
            for i in b.revealed.indices {
                let near = Fog.distanceToOpen(b, i, limit: Tuning.revealRadius) != nil
                XCTAssertEqual(b.revealed[i], near, "level \(level) cell \(i % b.size),\(i / b.size)")
            }
            XCTAssertFalse(b.revealed[b.index(b.gold.x, b.gold.y)], "the gold starts hidden")
            XCTAssertLessThan(Fog.revealedFraction(b), 0.15, "level \(level) starts mostly dark")
        }
    }

    func testRevealIsASquareOfRadiusThree() {
        let b = Board(size: 21, level: 1, name: "T")
        let first = Fog.reveal(b, 10, 10, radius: 3, at: 0)
        XCTAssertEqual(first.count, 49)
        XCTAssertEqual(first.first, b.index(10, 10), "nearest first")
        XCTAssertTrue(b.revealed[b.index(13, 13)], "corners too: Chebyshev distance 3")
        XCTAssertFalse(b.revealed[b.index(14, 10)])
        XCTAssertFalse(b.revealed[b.index(10, 6)])
        XCTAssertTrue(Fog.reveal(b, 10, 10, radius: 3, at: 1).isEmpty, "only new cells are returned")
        XCTAssertEqual(Fog.reveal(b, 10, 10, radius: 4, at: 1).count, 81 - 49)
    }

    func testRevealRipplesOutward() {
        let b = Board(size: 21, level: 1, name: "T")
        Fog.reveal(b, 10, 10, radius: 3, at: 5)
        XCTAssertEqual(Fog.coverage(b, b.index(10, 10), at: 5), 0)
        XCTAssertEqual(Fog.coverage(b, b.index(10, 10), at: 5 + Fog.fadeTime), 1, accuracy: 1e-9)
        XCTAssertLessThan(Fog.coverage(b, b.index(13, 10), at: 5 + Fog.fadeTime), 1, "farther rings start later")
        XCTAssertEqual(Fog.coverage(b, b.index(0, 0), at: 100), 0)
    }

    func testBreakingABlockRevealsThreeCellsAroundIt() {
        let g = Game(seed: 3)
        g.ui.started = true
        let b = g.board
        let target = b.kind.indices.first { b.kind[$0] == .block && b.revealed[$0] && Fog.distanceToOpen(b, $0, limit: 3) == 3 }!
        let tx = target % b.size, ty = target / b.size
        b.hp[target] = 0.001
        g.tap(cellX: tx, cellY: ty)
        XCTAssertEqual(b.kind[target], .empty)
        for dy in -3...3 { for dx in -3...3 where b.inside(tx + dx, ty + dy) {
            XCTAssertTrue(b.revealed[b.index(tx + dx, ty + dy)])
        } }
    }

    /// After a minute of play the rule still holds: everything within 3 of open space is
    /// visible, and anything visible farther out is a wall a ball bumped into.
    func testFogInvariantHoldsDuringPlay() {
        let g = Game(seed: 5)
        g.ui.started = true
        for _ in 0..<(60 * 60) { g.update(1.0 / 60) }
        let b = g.board
        guard b.kind[b.index(b.gold.x, b.gold.y)] == .gold else { return }
        for i in b.revealed.indices {
            let near = Fog.distanceToOpen(b, i, limit: Tuning.revealRadius) != nil
            if near { XCTAssertTrue(b.revealed[i]) }
            else if b.revealed[i] { XCTAssertEqual(b.kind[i], .wall, "cell \(i % b.size),\(i / b.size)") }
        }
    }

    func testLanternWidensReveals() {
        XCTAssertEqual(Mods.from(ranks: [:], stars: 0).revealRadius, 3)
        XCTAssertEqual(Mods.from(ranks: ["lantern": 2], stars: 0).revealRadius, 5)
    }

    func testHiddenBlocksStillCollideAndBreak() {
        let g = Game(seed: 9)
        g.ui.started = true
        let b = g.board
        let hiddenBefore = b.kind.indices.filter { b.kind[$0] == .block && !b.revealed[$0] }.count
        for _ in 0..<(60 * 40) { g.update(1.0 / 60) }
        let hiddenAfter = b.kind.indices.filter { b.kind[$0] == .block && !b.revealed[$0] }.count
        XCTAssertLessThan(hiddenAfter, hiddenBefore, "balls break blocks in the dark, which reveals them")
        for i in b.kind.indices where b.kind[i] == .empty { XCTAssertTrue(b.revealed[i], "open cells are always visible") }
    }

    func testBallsRevealHiddenWallsTheyTouch() {
        let g = Game(seed: 2)
        g.ui.started = true
        for _ in 0..<(60 * 60) { g.update(1.0 / 60) }
        let b = g.board
        XCTAssertFalse(b.kind.indices.filter { b.kind[$0] == .wall && b.revealed[$0] }.isEmpty)
    }

    func testGoldGlowsOnlyNearTheGold() {
        let b = LevelGen.make(level: 2)
        XCTAssertGreaterThan(Fog.goldGlow(b, b.gold.x + 1, b.gold.y, at: 0.6), 0)
        XCTAssertEqual(Fog.goldGlow(b, b.gold.x + 6, b.gold.y, at: 0.6), 0)
    }

    func testRadarHintAlwaysContainsTheGoldAndNarrows() {
        for level in 1...8 {
            let b = LevelGen.make(level: level)
            XCTAssertNil(Fog.radarHint(b, rank: 0))
            var last = Int.max
            for rank in 1...3 {
                let h = Fog.radarHint(b, rank: rank)!
                XCTAssertLessThanOrEqual(abs(h.center.x - b.gold.x), h.radius)
                XCTAssertLessThanOrEqual(abs(h.center.y - b.gold.y), h.radius)
                XCTAssertLessThan(h.radius, last); last = h.radius
            }
        }
    }
}
