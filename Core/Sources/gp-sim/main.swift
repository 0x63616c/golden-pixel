// gp-sim: plays levels headlessly with a simple bot and reports how long each one takes.
//   swift run -c release gp-sim [--levels 1-7] [--seeds 3] [--check 0.5] [--cap 180]
//                               [-v [--log 60] [--snap]] [--skip bomb,ghost] [--noskill u-sniper|all]
//   swift run -c release gp-sim --map 3        (prints level 3 as text and exits)
// Each level starts as if the previous ones were cleared (stars = level - 1). The bot uses
// only the public Game API, the way a player checking in every `--check` seconds would:
// it buys any affordable tree node (ball unlocks and damage first) and then the best
// damage-per-coin ball it can afford, aimed in a random direction. Deterministic per seed.
import Foundation
import GoldenPixelCore

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
}
func range(_ s: String) -> ClosedRange<Int> {
    let p = s.split(separator: "-").compactMap { Int($0) }
    return p.count == 2 ? p[0]...p[1] : p[0]...p[0]
}
let levels = range(option("--levels") ?? "1-7")
let seeds = max(1, Int(option("--seeds") ?? "3") ?? 3)
let checkEvery = Double(option("--check") ?? "0.5") ?? 0.5
let capMinutes = Double(option("--cap") ?? "180") ?? 180
let logEvery = Double(option("--log") ?? "60") ?? 60
let verbose = args.contains("-v")
let snap = args.contains("--snap")
/// Ball kinds the bot never buys (unlocks still bring their free ball).
let skip = Set((option("--skip") ?? "").split(separator: ",").compactMap { BallKind(rawValue: String($0)) })
/// Tree nodes the bot never buys ("all" for none at all).
let noSkill = Set((option("--noskill") ?? "").split(separator: ",").map(String.init))

func text(_ b: Board) -> [String] {
    (0..<b.size).map { y in
        String((0..<b.size).map { x -> Character in
            if x == b.spawn.x && y == b.spawn.y && b.kind[b.index(x, y)] == .empty { return "S" }
            switch b.kind[b.index(x, y)] {
            case .empty: return " "
            case .wall: return "#"
            case .block: return "."
            case .shard: return "*"
            case .gold: return "G"
            }
        })
    }
}

if let l = option("--map").flatMap({ Int($0) }) {
    text(LevelGen.make(level: l)).forEach { print($0) }
    exit(0)
}

/// The bot's rough guess at how much a ball of this kind is worth: hits per second times
/// damage, times what its special adds. Only used to rank purchases.
func ballValue(_ g: Game, _ k: BallKind) -> Double {
    let base = g.damage(k) * g.speed(k)
    switch k {
    case .basic: return base * (1 + g.special(.basic) * (g.mods.critDamage - 1))
    case .fast: return base * (1 + g.special(.fast))
    case .heavy: return base * (1 + 0.5 * g.special(.heavy))
    case .lightning: return base * (1 + 0.5 * g.special(.lightning))
    case .bomb:
        let r = g.special(.bomb)
        return base * (1 + 0.6 * Double.pi * r * r)
    case .sniper: return base * 1.5
    case .ghost: return base * (1 + g.special(.ghost))
    }
}

/// Lower buys first: unlocks, then damage, then the other stats, specialisations, and the
/// fog and idle nodes last.
func priority(_ s: SkillNode) -> Int {
    switch s.effect {
    case .unlock: return 0
    case .damage, .ballStat(_, .damage): return 1
    case .money, .ballStat(_, .special), .ballStat(_, .speed), .speed, .crit, .critDamage, .cash: return 2
    case .ballSpec: return 3
    default: return 4
    }
}

struct Result {
    var level = 0, seed = 0
    var time = 0.0
    var cleared = false
    var balls: [BallKind: Int] = [:]
    var nodes = 0
    var shards = 0, shardsTotal = 0
    var coins = 0.0
    /// `firstBall` is the first ball bought with earned coins (the start coins pay for one).
    var firstBall: Double?, firstShard: Double?, goldSpotted: Double?, treeDone: Double?
    /// The longest stretch with nothing bought (after the first purchase): the "slog" check.
    var lastBuy = 0.0, maxGap = 0.0
    var log: [String] = []

    mutating func bought(at t: Double) { maxGap = max(maxGap, t - lastBuy); lastBuy = t }
}

func play(level: Int, seed: Int) -> Result {
    var p = Progress()
    p.level = level
    p.maxLevel = level
    p.stars = level - 1
    let g = Game(progress: p, seed: UInt64(seed))
    g.ui.screen = .game
    var rng = RNG(seed: UInt64(seed) &* 7919 &+ UInt64(level))
    var r = Result()
    r.level = level; r.seed = seed
    r.shardsTotal = g.board.shardValue.reduce(0, +)
    let dt = 1.0 / 20
    let stepsPerCheck = max(1, Int((checkEvery / dt).rounded()))
    let cap = capMinutes * 60
    var shardsSpent = 0
    var nextLog = logEvery

    while g.progress.levelTime < cap {
        for _ in 0..<stepsPerCheck {
            g.update(dt)
            if g.clearTimer != nil { break }
        }
        let t = g.progress.levelTime
        if r.goldSpotted == nil, g.events.contains(.goldSpotted) { r.goldSpotted = t }
        g.events.removeAll(keepingCapacity: true)
        if g.clearTimer != nil {
            r.cleared = true
            if snap { r.log += text(g.board) }
            break
        }
        if r.firstShard == nil, g.progress.shards + shardsSpent > 0 { r.firstShard = t }

        // Tree: buy the best affordable node, again and again. Save up for a visible unlock.
        var boughtNode = true
        while boughtNode {
            boughtNode = false
            let open = SkillNode.all.filter { !noSkill.contains($0.id) && !noSkill.contains("all") }.filter {
                let c = Skills.check($0.id, ranks: g.progress.skillRanks, shards: g.progress.shards)
                return c == .ok || c == .poor
            }.sorted { (priority($0), $0.cost) < (priority($1), $1.cost) }
            for s in open {
                if Skills.check(s.id, ranks: g.progress.skillRanks, shards: g.progress.shards) == .ok, g.buySkill(s.id) {
                    shardsSpent += s.cost
                    r.bought(at: t)
                    boughtNode = true
                    break
                }
                if case .unlock = s.effect { break }
            }
        }

        // Balls: the best value per coin among what is affordable, aimed anywhere.
        while true {
            let options = BallKind.allCases.filter { g.mods.unlocked.contains($0) && !skip.contains($0) && g.ballCost($0) <= g.progress.money }
            guard let k = options.max(by: { ballValue(g, $0) / g.ballCost($0) < ballValue(g, $1) / g.ballCost($1) }) else { break }
            let a = rng.range(0, 2 * Double.pi)
            guard g.buyBall(k, direction: (cos(a), sin(a))) else { break }
            // The level's start coins pay for the first ball; the next one is the first earned.
            if r.firstBall == nil, g.balls.count >= 2 { r.firstBall = t }
            r.bought(at: t)
        }

        if r.treeDone == nil, SkillNode.all.allSatisfy({ (g.progress.skillRanks[$0.id] ?? 0) >= $0.ranks }) { r.treeDone = t }
        if verbose, t >= nextLog {
            nextLog += logEvery
            let owned = BallKind.allCases.map { "\(g.progress.ball($0).owned)" }.joined(separator: "/")
            r.log.append(String(format: "  L%d s%d %5.1fm coins %.3g earned %.3g shards %d/%d blocks %d balls ",
                                level, seed, t / 60, g.progress.money, g.progress.runEarnings,
                                shardsSpent + g.progress.shards, r.shardsTotal, g.board.blocksLeft) + owned)
        }
    }
    r.time = g.progress.levelTime
    for k in BallKind.allCases { r.balls[k] = g.progress.ball(k).owned }
    r.nodes = SkillNode.all.filter { (g.progress.skillRanks[$0.id] ?? 0) > 0 }.count - SkillNode.startingRanks.count
    r.shards = shardsSpent + g.progress.shards
    r.coins = g.progress.runEarnings
    return r
}

/// True when the gold can be reached from the spawn without passing through rock.
func goldReachable(_ b: Board) -> Bool {
    var seen = Array(repeating: false, count: b.kind.count)
    var stack = [b.index(b.spawn.x, b.spawn.y)]
    seen[stack[0]] = true
    let goal = b.index(b.gold.x, b.gold.y)
    while let i = stack.popLast() {
        if i == goal { return true }
        let x = i % b.size, y = i / b.size
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where b.inside(x + dx, y + dy) {
            let j = b.index(x + dx, y + dy)
            if !seen[j], b.kind[j] != .wall { seen[j] = true; stack.append(j) }
        }
    }
    return false
}

for l in levels {
    let b = LevelGen.make(level: l)
    if !goldReachable(b) { print("WARNING: level \(l): the gold is walled off from the spawn") }
    let dx = Double(b.gold.x - b.spawn.x), dy = Double(b.gold.y - b.spawn.y)
    print("level \(l) \(b.name): radius \(LevelSpec.forLevel(l).radius), \(b.blocksLeft) blocks, \(b.shardsLeft) shard pixels, "
          + "gold \(Int((dx * dx + dy * dy).squareRoot())) cells from spawn, gold HP \(compact(b.maxHP[b.index(b.gold.x, b.gold.y)])), shard values \(b.shardValue.filter { $0 > 0 }.sorted())")
}

let jobs = levels.flatMap { l in (1...seeds).map { (l, $0) } }
var results = Array(repeating: Result(), count: jobs.count)
let lock = NSLock()
DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
    let res = play(level: jobs[i].0, seed: jobs[i].1)
    lock.lock(); results[i] = res; lock.unlock()
}

func m(_ t: Double?) -> String { t.map { String(format: "%.1f", $0 / 60) } ?? "-" }
func sec(_ t: Double?) -> String { t.map { String(format: "%.0fs", $0) } ?? "-" }
func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : String(repeating: " ", count: n - s.count) + s }
print("lvl seed clear(min) 2nd ball 1st shard gold seen(min) max gap   shards nodes   coins  balls b/f/h/v/B/s/g")
for r in results {
    let balls = BallKind.allCases.map { "\(r.balls[$0] ?? 0)" }.joined(separator: "/")
    let row = [pad("\(r.level)", 3), pad("\(r.seed)", 4), pad(m(r.time) + (r.cleared ? " " : "+"), 10), pad(sec(r.firstBall), 8),
               pad(sec(r.firstShard), 9), pad(m(r.goldSpotted), 14), pad(sec(r.maxGap), 7),
               pad("\(r.shards)/\(r.shardsTotal)", 9), pad("\(r.nodes)", 5), pad(compact(r.coins), 7), "  " + balls]
    print(row.joined(separator: " "))
    if verbose || snap { r.log.forEach { print($0) } }
}
print("\nper level (mean over seeds; '+' = hit the cap):")
for l in levels {
    let rs = results.filter { $0.level == l }
    func avg(_ f: (Result) -> Double?) -> Double { let v = rs.compactMap(f); return v.isEmpty ? .nan : v.reduce(0, +) / Double(v.count) }
    let ts = rs.map(\.time)
    print(String(format: "  L%d  clear %.1f min (min %.1f, max %.1f)", l, avg { $0.time } / 60, ts.min()! / 60, ts.max()! / 60)
          + (rs.allSatisfy(\.cleared) ? "" : " +")
          + String(format: "  2nd ball %.0fs  first shard %.0fs  longest gap %.0fs", avg { $0.firstBall }, avg { $0.firstShard }, avg { $0.maxGap }))
}
