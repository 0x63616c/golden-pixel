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

    /// Durability is laid out: rock near the spawn is softer than rock far from it, and blocks
    /// clump into patches (a block matches its neighbour's tier well above chance) instead of a
    /// per-cell speckle.
    func testDurabilityIsDeeperTougherWithPatches() {
        for level in 1...12 {
            let b = LevelGen.make(level: level)
            let blocks = b.kind.indices.filter { b.kind[$0] == .block }
            let tiers = blocks.map { Int(b.tier[$0]) }
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
            XCTAssertGreaterThan(Double(same) / Double(pairs), chance + 0.1, "level \(level) looks like a speckle")

            func d(_ i: Int) -> Double { LevelGen.dist(Point(i % b.size, i / b.size), b.spawn) }
            let byDepth = blocks.sorted { d($0) < d($1) }
            func mean(_ s: ArraySlice<Int>) -> Double { Double(s.reduce(0) { $0 + Int(b.tier[$1]) }) / Double(s.count) }
            let third = byDepth.count / 3
            XCTAssertLessThan(mean(byDepth.prefix(third)) + 0.5, mean(byDepth.suffix(third)), "level \(level): the far third should be tougher")
        }
    }

    func testTierDistributionMatchesWeightsAndGetsTougher() {
        func freq(_ level: Int) -> [Double] {
            let b = LevelGen.make(level: level)
            let tiers = b.kind.indices.filter { b.kind[$0] == .block }.map { Int(b.tier[$0]) }
            return (0..<5).map { t in Double(tiers.filter { $0 == t }.count) / Double(tiers.count) }
        }
        let f1 = freq(1), w1 = LevelGen.tierWeights(level: 1), t1 = w1.reduce(0, +)
        for t in 0..<5 { XCTAssertEqual(f1[t], w1[t] / t1, accuracy: 0.02, "tier \(t)") }
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
        XCTAssertEqual(b.hp[g], Economy.goldHP(level: 4), accuracy: 1e-9)
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

    /// Walls never seal anything off: every block, shard and the gold can be dug to from the
    /// spawn, and deeper shards pay more than the starters.
    func testEverythingIsReachableAndDeepShardsPayMore() {
        for level in 1...14 {
            let b = LevelGen.make(level: level)
            var seen = Array(repeating: false, count: b.kind.count)
            var stack = [b.index(b.spawn.x, b.spawn.y)]
            seen[stack[0]] = true
            while let i = stack.popLast() {
                let x = i % b.size, y = i / b.size
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where b.inside(x + dx, y + dy) {
                    let j = b.index(x + dx, y + dy)
                    if !seen[j], b.kind[j] != .wall { seen[j] = true; stack.append(j) }
                }
            }
            for i in b.kind.indices where b.kind[i].breakable { XCTAssertTrue(seen[i], "level \(level): cell \(i) is walled off") }
            let shards = b.kind.indices.filter { b.kind[$0] == .shard }
            func depth(_ i: Int) -> Int { max(abs(i % b.size - b.spawn.x), abs(i / b.size - b.spawn.y)) }
            let nearest = shards.min { depth($0) < depth($1) }!, deepest = shards.max { depth($0) < depth($1) }!
            XCTAssertLessThan(b.shardValue[nearest], b.shardValue[deepest], "level \(level)")
        }
        XCTAssertEqual(Economy.shardValues(weights: [1, 8, 27, 64], total: 100).reduce(0, +), 100)
        XCTAssertEqual(Economy.shardValues(weights: [1, 1000], total: 10).min(), 1, "every shard pays at least one")
    }

    func testFirstLevelIsGentle() {
        let b = LevelGen.make(level: 1)
        let tiers = b.kind.indices.filter { b.kind[$0] == .block }.map { Int(b.tier[$0]) }
        let easy = tiers.filter { $0 <= 1 }.count
        XCTAssertGreaterThan(Double(easy) / Double(tiers.count), 0.6)
    }
}
