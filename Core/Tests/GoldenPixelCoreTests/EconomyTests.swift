import XCTest
@testable import GoldenPixelCore

final class EconomyTests: XCTestCase {
    func testFirstBasicBallIsFreeAndPricesRise() {
        XCTAssertEqual(Economy.ballCost(.basic, owned: 1), 25)
        XCTAssertEqual(Economy.ballCost(.basic, owned: 0), 25)
        XCTAssertGreaterThan(Economy.ballCost(.basic, owned: 2), 25)
        for k in BallKind.allCases {
            var last = 0.0
            for n in 0..<30 {
                let c = Economy.ballCost(k, owned: n + (k == .basic ? 1 : 0))
                XCTAssertGreaterThan(c, last, "\(k) at \(n)")
                last = c
            }
        }
    }

    func testSwarmDiscount() {
        XCTAssertEqual(Economy.ballCost(.basic, owned: 5, swarm: true), (Economy.ballCost(.basic, owned: 5) * 0.6).rounded(), accuracy: 1)
    }

    func testComboCapsAtThreeTimes() {
        XCTAssertEqual(Economy.comboMultiplier(1), 1)
        XCTAssertEqual(Economy.comboMultiplier(1000), Tuning.comboMax)
    }

    func testOfflineEarningsAreCapped() {
        let m = Mods()
        XCTAssertEqual(Economy.offlineEarnings(incomePerSecond: 10, elapsed: 30, mods: m), 0)
        let day = Economy.offlineEarnings(incomePerSecond: 10, elapsed: 86_400, mods: m)
        XCTAssertEqual(day, 10 * Tuning.offlineCapSeconds * m.offline, accuracy: 1e-6)
    }

    func testShardValuesSplitTheTreeEvenly() {
        let v = Economy.shardValues(count: 7, total: 100)
        XCTAssertEqual(v.reduce(0, +), 100)
        XCTAssertLessThanOrEqual(v.max()! - v.min()!, 1)
        XCTAssertEqual(Economy.shardValues(count: 0), [])
    }

    func testCoinsBuyBallsOnly() {
        var p = Progress(); p.money = 100
        let g = Game(progress: p)
        let n = g.balls.count
        XCTAssertTrue(g.buyBall(.basic))
        XCTAssertEqual(g.balls.count, n + 1)
        XCTAssertEqual(g.progress.money, 75)
        XCTAssertFalse(g.buyBall(.fast), "locked until the tree unlocks it")
        XCTAssertEqual(g.events.last, .denied)
        XCTAssertFalse(g.buySkill("core"), "skills cost shards, not coins")
        XCTAssertEqual(g.progress.money, 75)
    }

    func testSkillsNeedPrerequisitesAndShards() {
        XCTAssertEqual(Skills.check("sharp", ranks: [:], shards: 5), .locked)
        XCTAssertEqual(Skills.check("core", ranks: [:], shards: 0), .poor)
        XCTAssertEqual(Skills.check("core", ranks: [:], shards: 1), .ok)
        XCTAssertEqual(Skills.check("core", ranks: ["core": 1], shards: 9), .maxed)
        XCTAssertEqual(Skills.check("u-lightning", ranks: ["core": 1, "sharp": 1], shards: 9), .locked)
        XCTAssertFalse(Skills.visible("u-ghost", ranks: SkillNode.startingRanks))
        XCTAssertTrue(Skills.visible("core", ranks: SkillNode.startingRanks))
        XCTAssertTrue(Skills.visible("basic-dmg", ranks: SkillNode.startingRanks), "the starting ball's upgrades show")
    }

    func testUnlockSkillGivesTheBallType() {
        var p = Progress(); p.shards = 5; p.skillRanks = ["u-basic": 1, "core": 1, "momentum": 1]
        let g = Game(progress: p)
        XCTAssertTrue(g.buySkill("u-fast"))
        XCTAssertTrue(g.mods.unlocked.contains(.fast))
        XCTAssertEqual(g.progress.ball(.fast).owned, 1)
        XCTAssertTrue(g.balls.contains { $0.kind == .fast })
        XCTAssertEqual(g.progress.shards, 5 - SkillNode.byID["u-fast"]!.cost)
    }

    /// Ball upgrades live in the tree: each rank of a ball's damage node adds 50%.
    func testBallUpgradesComeFromTheTree() {
        var p = Progress(); p.shards = 10
        let g = Game(progress: p)
        let before = g.damage(.basic)
        XCTAssertTrue(g.buySkill("basic-dmg"))
        XCTAssertEqual(g.damage(.basic), before * 1.5, accuracy: 1e-9)
        XCTAssertTrue(g.buySkill("basic-spd"))
        XCTAssertEqual(g.rank(.basic, .speed), 1)
    }

    /// Every node is reachable from the start, so a level's shards can buy the whole tree.
    func testTheWholeTreeIsReachable() {
        var ranks = SkillNode.startingRanks
        var progress = true
        while progress {
            progress = false
            for s in SkillNode.all where Skills.check(s.id, ranks: ranks, shards: .max) == .ok {
                ranks[s.id, default: 0] += 1
                progress = true
            }
        }
        for s in SkillNode.all { XCTAssertEqual(ranks[s.id] ?? 0, s.ranks, s.id) }
        XCTAssertNil(SkillNode.byID["tap"], "there is no tap damage")
    }

    func testCompactNumbers() {
        XCTAssertEqual(compact(0), "0")
        XCTAssertEqual(compact(999), "999")
        XCTAssertEqual(compact(1234), "1.2K")
        XCTAssertEqual(compact(12_345), "12K")
        XCTAssertEqual(compact(1_000_000), "1M")
        XCTAssertEqual(compact(7_400_000), "7.4M")
    }
}
