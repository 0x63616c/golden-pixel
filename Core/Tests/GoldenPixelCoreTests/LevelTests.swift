import XCTest
@testable import GoldenPixelCore

final class LevelTests: XCTestCase {
    func testGenerationIsDeterministic() {
        for level in 1...10 {
            let a = LevelGen.make(level: level), b = LevelGen.make(level: level)
            XCTAssertEqual(a.kind, b.kind, "level \(level)")
            XCTAssertEqual(a.tier, b.tier, "level \(level)")
            XCTAssertEqual(a.gold, b.gold)
        }
    }

    func testEveryLevelHasOneGoldSpawnPocketAndBlocks() {
        for level in 1...14 {
            let b = LevelGen.make(level: level)
            XCTAssertEqual(b.kind.filter { $0 == .gold }.count, 1, "level \(level)")
            XCTAssertEqual(b.kindAt(b.spawn.x, b.spawn.y), .empty, "level \(level) spawn")
            XCTAssertGreaterThan(b.blocksLeft, 150, "level \(level)")
            XCTAssertEqual(b.kind[b.index(b.gold.x, b.gold.y)], .gold)
        }
    }

    func testLevelsGrow() {
        let radii = LevelSpec.campaign.map(\.radius)
        XCTAssertEqual(radii, radii.sorted())
        XCTAssertEqual(Set(radii).count, radii.count)
        for spec in LevelSpec.campaign { XCTAssertLessThan(spec.radius, spec.boardSize / 2, "every arena fits its board with a wall rim") }
        XCTAssertGreaterThanOrEqual(LevelSpec.campaign[0].boardSize, 45, "levels are far bigger than one screen")
        XCTAssertGreaterThan(LevelGen.make(level: 7).blocksLeft, LevelGen.make(level: 1).blocksLeft)
    }

    func testGoldStartsFarFromTheLight() {
        for level in 1...10 {
            let b = LevelGen.make(level: level)
            let d = max(abs(b.gold.x - b.spawn.x), abs(b.gold.y - b.spawn.y))
            XCTAssertGreaterThan(d, Tuning.revealRadius + 4, "level \(level)")
        }
    }

    /// Durability is per cell: tiers are rolled independently, so a block matches its
    /// neighbour's tier about as often as chance says (sum of p squared) and never forms a
    /// big uniform patch.
    func testDurabilityIsAPerCellSpeckle() {
        for level in 1...12 {
            let b = LevelGen.make(level: level)
            let tiers = b.kind.indices.filter { b.kind[$0] == .block }.map { Int(b.tier[$0]) }
            let chance = (0..<5).reduce(0.0) { acc, t in
                let f = Double(tiers.filter { $0 == t }.count) / Double(tiers.count)
                return acc + f * f
            }
            var same = 0, pairs = 0
            for y in 0..<b.size { for x in 0..<b.size where b.kind[b.index(x, y)] == .block {
                for (dx, dy) in [(1, 0), (0, 1)] where b.kindAt(x + dx, y + dy) == .block {
                    pairs += 1
                    if b.tier[b.index(x + dx, y + dy)] == b.tier[b.index(x, y)] { same += 1 }
                }
            } }
            XCTAssertLessThan(Double(same) / Double(pairs), chance + 0.05, "level \(level) looks zoned")
            // No 4x4 square of blocks shares one tier.
            for y in 0..<(b.size - 3) { for x in 0..<(b.size - 3) {
                var tiers = Set<UInt8>(), allBlocks = true
                for dy in 0..<4 { for dx in 0..<4 {
                    let i = b.index(x + dx, y + dy)
                    if b.kind[i] != .block { allBlocks = false } else { tiers.insert(b.tier[i]) }
                } }
                if allBlocks { XCTAssertGreaterThan(tiers.count, 1, "level \(level) uniform patch at \(x),\(y)") }
            } }
        }
    }

    func testTierDistributionMatchesWeightsAndGetsTougher() {
        func freq(_ level: Int) -> [Double] {
            let b = LevelGen.make(level: level)
            let tiers = b.kind.indices.filter { b.kind[$0] == .block }.map { Int(b.tier[$0]) }
            return (0..<5).map { t in Double(tiers.filter { $0 == t }.count) / Double(tiers.count) }
        }
        let f1 = freq(1), w1 = LevelGen.tierWeights(level: 1), t1 = w1.reduce(0, +)
        for t in 0..<5 { XCTAssertEqual(f1[t], w1[t] / t1, accuracy: 0.06, "tier \(t)") }
        func mean(_ f: [Double]) -> Double { f.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element } }
        XCTAssertLessThan(mean(f1), mean(freq(7)))
        XCTAssertLessThan(mean(freq(7)), mean(freq(14)))
        XCTAssertEqual(LevelGen.tierWeights(level: 13), LevelGen.tierWeights(level: 40), "the curve tops out")
    }

    func testOnlyWallsAreUnbreakableAndGoldIsSpecial() {
        for level in 1...8 {
            let b = LevelGen.make(level: level)
            for i in b.kind.indices {
                switch b.kind[i] {
                case .block: XCTAssertGreaterThan(b.hp[i], 0)
                case .gold: XCTAssertEqual(i, b.index(b.gold.x, b.gold.y)); XCTAssertFalse(b.rich[i])
                case .shard: XCTAssertGreaterThan(b.hp[i], 0); XCTAssertGreaterThan(b.shardValue[i], 0)
                case .wall, .empty: XCTAssertEqual(b.hp[i], 0)
                }
            }
        }
    }

    func testHitPointsMatchTierAndLevel() {
        let b = LevelGen.make(level: 4)
        for i in 0..<b.kind.count where b.kind[i] == .block {
            let expected = Economy.tierHP(Int(b.tier[i]), level: 4)
            XCTAssertEqual(b.hp[i], expected, accuracy: 1e-9)
        }
        let g = b.index(b.gold.x, b.gold.y)
        XCTAssertEqual(b.hp[g], Economy.tierHP(4, level: 4) * Tuning.goldHPMultiplier, accuracy: 1e-9)
    }

    /// One level holds exactly the whole tree's price in shards, spread over its shard pixels.
    func testShardsAddUpToTheWholeTree() {
        for level in 1...10 {
            let b = LevelGen.make(level: level)
            let shards = b.kind.indices.filter { b.kind[$0] == .shard }
            XCTAssertGreaterThanOrEqual(shards.count, Tuning.shardsPerLevel / 2, "level \(level)")
            XCTAssertEqual(shards.reduce(0) { $0 + b.shardValue[$1] }, SkillNode.totalCost, "level \(level)")
            for i in shards {
                let p = Point(i % b.size, i / b.size)
                XCTAssertGreaterThan(max(abs(p.x - b.gold.x), abs(p.y - b.gold.y)), 3)
            }
        }
    }

    func testFirstLevelIsGentle() {
        let b = LevelGen.make(level: 1)
        let tiers = b.kind.indices.filter { b.kind[$0] == .block }.map { Int(b.tier[$0]) }
        let easy = tiers.filter { $0 <= 1 }.count
        XCTAssertGreaterThan(Double(easy) / Double(tiers.count), 0.6)
    }
}
