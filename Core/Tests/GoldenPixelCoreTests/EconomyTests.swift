import XCTest
@testable import GoldenPixelCore

final class EconomyTests: XCTestCase {
    func testFirstBasicBallIsFreeAndPricesRise() {
        XCTAssertEqual(Economy.ballCost(.basic, owned: 1, spec: nil), 25)
        XCTAssertEqual(Economy.ballCost(.basic, owned: 0, spec: nil), 25)
        XCTAssertGreaterThan(Economy.ballCost(.basic, owned: 2, spec: nil), 25)
        for k in BallKind.allCases {
            var last = 0.0
            for n in 0..<30 {
                let c = Economy.ballCost(k, owned: n + (k == .basic ? 1 : 0), spec: nil)
                XCTAssertGreaterThan(c, last, "\(k) at \(n)")
                last = c
            }
        }
    }

    func testSwarmDiscount() {
        XCTAssertEqual(Economy.ballCost(.basic, owned: 5, spec: "swarm"), (Economy.ballCost(.basic, owned: 5, spec: nil) * 0.6).rounded(), accuracy: 1)
    }

    func testUpgradesCapAtTheirMax() {
        for s in Stat.allCases {
            XCTAssertNotNil(Economy.upgradeCost(.fast, s, level: s.max - 1))
            XCTAssertNil(Economy.upgradeCost(.fast, s, level: s.max))
        }
    }

    func testSpecialisationNeedsTenUpgrades() {
        var p = BallProgress(owned: 1)
        p.speed = 5; p.damage = 4
        XCTAssertFalse(Economy.canSpecialize(p))
        p.special = 1
        XCTAssertTrue(Economy.canSpecialize(p))
        p.spec = "blur"
        XCTAssertFalse(Economy.canSpecialize(p))
    }

    func testPrestigeNeedsLevelThree() {
        XCTAssertEqual(Economy.starsForPrestige(runEarnings: 1e9, maxLevel: 2), 0)
        XCTAssertEqual(Economy.starsForPrestige(runEarnings: 160_000, maxLevel: 3), 2)
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

    func testBuyingSpendsMoneyAndAddsABall() {
        var p = Progress(); p.money = 100
        let g = Game(progress: p)
        let n = g.balls.count
        XCTAssertTrue(g.buyBall(.basic))
        XCTAssertEqual(g.balls.count, n + 1)
        XCTAssertEqual(g.progress.money, 75)
        XCTAssertFalse(g.buyBall(.fast), "locked until the skill")
        XCTAssertEqual(g.events.last, .denied)
    }

    func testSkillsNeedPrerequisitesAndPoints() {
        XCTAssertEqual(Skills.check("sharp", ranks: [:], points: 5), .locked)
        XCTAssertEqual(Skills.check("core", ranks: [:], points: 0), .poor)
        XCTAssertEqual(Skills.check("core", ranks: [:], points: 1), .ok)
        XCTAssertEqual(Skills.check("core", ranks: ["core": 1], points: 9), .maxed)
        XCTAssertEqual(Skills.check("u-lightning", ranks: ["core": 1, "sharp": 1], points: 9), .locked)
    }

    func testUnlockSkillGivesTheBallType() {
        var p = Progress(); p.skillPoints = 5; p.skillRanks = ["core": 1, "momentum": 1]
        let g = Game(progress: p)
        XCTAssertTrue(g.buySkill("u-fast"))
        XCTAssertTrue(g.mods.unlocked.contains(.fast))
        XCTAssertEqual(g.progress.ball(.fast).owned, 1)
        XCTAssertTrue(g.balls.contains { $0.kind == .fast })
    }

    func testPrestigeKeepsSkillsAndAddsStars() {
        var p = Progress(); p.maxLevel = 4; p.level = 4; p.runEarnings = 400_000; p.skillRanks = ["core": 1]; p.money = 9999
        let g = Game(progress: p)
        XCTAssertTrue(g.prestige())
        XCTAssertEqual(g.progress.stars, 3)
        XCTAssertEqual(g.progress.level, 1)
        XCTAssertEqual(g.progress.money, 0)
        XCTAssertEqual(g.progress.skillRanks["core"], 1)
        XCTAssertGreaterThan(g.mods.money, 1.29)
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
