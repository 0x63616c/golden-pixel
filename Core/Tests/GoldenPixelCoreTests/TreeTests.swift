import XCTest
@testable import GoldenPixelCore

/// The skill tree is one tree on a grid: a single root, right-angled links that miss the other
/// nodes and each other, and every node on screen hangs off a node on screen.
final class TreeTests: XCTestCase {
    typealias Segment = (a: Point, b: Point)

    func segments(_ from: SkillNode, _ to: SkillNode) -> [Segment] {
        let path = SkillTree.route(from: from, to: to)
        return zip(path, path.dropFirst()).map { ($0, $1) }
    }

    var links: [(from: SkillNode, to: SkillNode)] {
        SkillNode.all.flatMap { s in s.requires.compactMap { SkillNode.byID[$0] }.map { (from: $0, to: s) } }
    }

    /// Shards stay small: every rank is 1 shard, a specialisation 2, and only the unlocks of
    /// stronger types cost more. The whole tree is 182, which is also what a level holds.
    func testTheTreeIsCheap() {
        for n in SkillNode.all {
            switch n.effect {
            case .unlock: XCTAssertLessThanOrEqual(n.cost, 6, n.id)
            case .ballSpec: XCTAssertEqual(n.cost, 2, n.id)
            default: XCTAssertEqual(n.cost, 1, n.id)
            }
        }
        XCTAssertEqual(SkillNode.totalCost, 182)
    }

    func testThereIsOneRootAndEverythingGrowsFromIt() {
        let roots = SkillNode.all.filter { $0.requires.isEmpty }.map(\.id)
        XCTAssertEqual(roots, [SkillTree.root])
        for s in SkillNode.all { for rq in s.requires { XCTAssertNotNil(SkillNode.byID[rq], "\(s.id) needs \(rq)") } }
        // Walking down from the root reaches every node.
        var reached: Set<String> = [SkillTree.root], grew = true
        while grew {
            grew = false
            for s in SkillNode.all where !reached.contains(s.id) && s.requires.contains(where: reached.contains) {
                reached.insert(s.id); grew = true
            }
        }
        XCTAssertEqual(reached.count, SkillNode.all.count)
    }

    func testNodesSitOnTheGridApart() {
        for (i, a) in SkillNode.all.enumerated() {
            for b in SkillNode.all[(i + 1)...] {
                XCTAssertTrue(abs(a.x - b.x) >= 2 || abs(a.y - b.y) >= 2, "\(a.id) and \(b.id) overlap")
            }
            let p = SkillTree.point(a)
            XCTAssertEqual(p.x % 8, 0, a.id); XCTAssertEqual(p.y % 8, 0, a.id)
        }
    }

    /// Links are horizontal and vertical runs only: no diagonals.
    func testEveryLinkIsRightAngled() {
        for l in links {
            let path = SkillTree.route(from: l.from, to: l.to)
            XCTAssertEqual(path.first, SkillTree.point(l.from))
            XCTAssertEqual(path.last, SkillTree.point(l.to))
            for s in segments(l.from, l.to) {
                XCTAssertTrue(s.a.x == s.b.x || s.a.y == s.b.y, "\(l.from.id) -> \(l.to.id) has a diagonal")
                XCTAssertTrue(s.a.x % 8 == 0 && s.a.y % 8 == 0, "\(l.from.id) -> \(l.to.id) bends off the grid")
            }
        }
    }

    /// No link runs through a node it does not join (nodes at their 1x size, 21 px).
    func testLinksMissOtherNodes() {
        let half = Renderer.nodeSize(1) / 2
        for l in links {
            for s in segments(l.from, l.to) {
                let x0 = min(s.a.x, s.b.x), x1 = max(s.a.x, s.b.x), y0 = min(s.a.y, s.b.y), y1 = max(s.a.y, s.b.y)
                for n in SkillNode.all where n.id != l.from.id && n.id != l.to.id {
                    let p = SkillTree.point(n)
                    let hits = x0 <= p.x + half && x1 >= p.x - half && y0 <= p.y + half && y1 >= p.y - half
                    XCTAssertFalse(hits, "\(l.from.id) -> \(l.to.id) runs through \(n.id)")
                }
            }
        }
    }

    /// Links only meet where they share a node: a fork's stub or a merge's last leg. Two
    /// unrelated links never cross or run along each other.
    func testLinksDoNotCross() {
        let all = links
        for (i, l) in all.enumerated() {
            for m in all[(i + 1)...] {
                let related = l.from.id == m.from.id || l.to.id == m.to.id || l.to.id == m.from.id || l.from.id == m.to.id
                if related { continue }
                for s in segments(l.from, l.to) {
                    for t in segments(m.from, m.to) {
                        let sx0 = min(s.a.x, s.b.x), sx1 = max(s.a.x, s.b.x), sy0 = min(s.a.y, s.b.y), sy1 = max(s.a.y, s.b.y)
                        let tx0 = min(t.a.x, t.b.x), tx1 = max(t.a.x, t.b.x), ty0 = min(t.a.y, t.b.y), ty1 = max(t.a.y, t.b.y)
                        let touch = sx0 <= tx1 && tx0 <= sx1 && sy0 <= ty1 && ty0 <= sy1
                        XCTAssertFalse(touch, "\(l.from.id) -> \(l.to.id) meets \(m.from.id) -> \(m.to.id)")
                    }
                }
            }
        }
    }

    /// Whatever has been bought, every node on screen (bar the root) has every node it needs
    /// on screen too, so its links are drawn and nothing floats.
    func testEveryShownNodeHangsOffAShownParent() {
        var rng = RNG(seed: 3)
        for run in 0..<40 {
            var ranks = SkillNode.startingRanks
            for _ in 0..<(run * 3) {
                let next = SkillNode.all.filter { Skills.check($0.id, ranks: ranks, shards: .max) == .ok }
                guard !next.isEmpty else { break }
                ranks[next[rng.int(next.count)].id, default: 0] += 1
            }
            let shown = Set(SkillNode.all.filter { Skills.visible($0.id, ranks: ranks) }.map(\.id))
            XCTAssertTrue(shown.contains(SkillTree.root))
            for id in shown where id != SkillTree.root {
                let s = SkillNode.byID[id]!
                XCTAssertFalse(s.requires.isEmpty, id)
                for rq in s.requires { XCTAssertTrue(shown.contains(rq), "\(id) is shown without \(rq)") }
            }
        }
    }

    /// The tree opens on what you can see: the root and the basic ball at the start.
    func testTheTreeOpensOnWhatIsShowing() {
        let g = Game(progress: Progress(), seed: 1)
        g.ui.screen = .game
        Renderer().render(g)
        g.perform(.openSkills)
        let r = Renderer()
        r.render(g)
        for id in ["core", "u-basic"] {
            let rect = g.ui.hits.first { $0.action == .selectSkill(id) }?.rect
            XCTAssertNotNil(rect, id)
            if let rect { XCTAssertTrue(Rect(60, 40, 355, 200).contains(Point(rect.x + rect.w / 2, rect.y + rect.h / 2)), "\(id) at \(rect)") }
        }
    }

    /// No card (and no BUY) until a node is picked; the card's button is big enough, out of the
    /// corners, and the card never covers the node it describes.
    func testTheCardFollowsTheSelection() {
        var p = Progress(); p.shards = 3
        p.skillRanks = ["u-basic": 1, "core": 1, "greed": 1, "lantern": 1, "radar": 1]
        let g = Game(progress: p, seed: 1)
        g.ui.screen = .game
        g.ui.skillsOpen = true
        let r = Renderer()
        r.render(g)
        XCTAssertFalse(g.ui.hits.contains { if case .buySkill = $0.action { return true } else { return false } })
        for id in ["core", "basic-dmg", "radar", "sonar", "sharp"] {
            g.ui.selectedSkill = id
            r.render(g)
            let node = g.ui.hits.first { $0.action == .selectSkill(id) }!.rect
            let card = g.ui.hits.last { $0.action == .none && $0.rect.w > 300 }!.rect
            let centre = Point(node.x + node.w / 2, node.y + node.h / 2)
            XCTAssertFalse(card.contains(centre), "\(id): the card covers its node")
            if let buy = g.ui.hits.first(where: { $0.action == .buySkill(id) })?.rect {
                XCTAssertGreaterThanOrEqual(min(buy.w, buy.h), Tuning.minTouch)
                XCTAssertTrue(g.ui.layout.safe(buy), "\(id): BUY in a corner")
            } else {
                XCTAssertEqual(Skills.check(id, ranks: p.skillRanks, shards: p.shards), .maxed, id)
            }
        }
    }

    /// Every node's name and text fit the card on the Duo without spilling.
    func testCardTextFits() {
        let r = Renderer()
        for s in SkillNode.all {
            var p = Progress(); p.skillRanks = [:]
            for n in SkillNode.all { p.skillRanks[n.id] = n.ranks }
            p.skillRanks[s.id] = 0
            let g = Game(progress: p, seed: 1)
            g.ui.screen = .game; g.ui.skillsOpen = true; g.ui.selectedSkill = s.id
            r.render(g)
            let card = g.ui.hits.last { $0.action == .none && $0.rect.w > 300 }!.rect
            XCTAssertLessThanOrEqual(card.h, 62, "\(s.id): the card grew past one line of text")
        }
    }
}
