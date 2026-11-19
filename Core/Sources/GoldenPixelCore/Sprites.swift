/// Small pixel-art sprites, written as text so they are easy to review and diff.
public struct Sprite: Sendable {
    public let width: Int
    public let height: Int
    public let pixels: [Pixel?]

    public init(_ rows: [String], _ map: [Character: Pixel]) {
        height = rows.count
        width = rows.map(\.count).max() ?? 0
        var px: [Pixel?] = []
        for r in rows {
            let chars = Array(r)
            for x in 0..<width { px.append(x < chars.count ? map[chars[x]] : nil) }
        }
        pixels = px
    }
}

/// Every sprite follows one light: from the top-left. Highlights ("h"/"l") sit on the upper
/// left, shade ("d") on the lower right. Icons that are tinted are flat silhouettes.
public enum Sprites {
    /// The in-play ball: 5x5 art pixels on an 8x8 block, lit from the top-left.
    public static func ball(_ k: BallKind) -> Sprite { ballCache[k.index] }

    /// The ball at HUD size (7x7, matching the font's cap height) with a mark per type.
    public static func ballIcon(_ k: BallKind) -> Sprite { ballIconCache[k.index] }

    private static let ballCache: [Sprite] = BallKind.allCases.map { k in
        Sprite([".ccc.", "chccd", "ccccd", "cccdd", ".ddd."],
               ["c": k.color.glowing(255), "d": k.shade.glowing(220), "h": Palette.white.glowing(255)])
    }

    private static let ballIconCache: [Sprite] = BallKind.allCases.map { k in
        var rows = ["..ccc..", ".chhcc.", "chhcccd", "cccccdd", "ccccddd", ".cdddd.", "..ddd.."]
        let marks: [(Int, Int)]
        switch k {
        case .basic: marks = []
        case .fast: marks = [(2, 2), (3, 3), (2, 4)]
        case .heavy: marks = [(3, 3), (4, 3), (3, 4), (4, 4)]
        case .lightning: marks = [(4, 1), (3, 2), (2, 3), (3, 3), (4, 3), (3, 4), (2, 5)]
        case .bomb: marks = [(3, 3)]
        case .sniper: marks = [(3, 2), (2, 3), (4, 3), (3, 4)]
        case .ghost: marks = [(2, 3), (4, 3)]
        }
        for (x, y) in marks {
            var r = Array(rows[y]); r[x] = "m"; rows[y] = String(r)
        }
        if k == .bomb { var r = Array(rows[0]); r[5] = "f"; rows[0] = String(r) }
        return Sprite(rows, ["c": k.color.glowing(200), "d": k.shade.glowing(120), "h": Palette.white.glowing(255),
                             "m": Palette.black, "f": Palette.gold.glowing(255)])
    }

    // HUD icons, 7x7 to match the font's 7-pixel caps.
    public static let coin = Sprite(["..lll..", ".llggg.", "llgdggd", "lggdggd", "lggdggd", ".gggdd.", "..ddd.."],
                                    ["l": Palette.goldLight.glowing(200), "g": Palette.gold.glowing(160), "d": Palette.goldDim.glowing(80)])
    public static let star = Sprite(["...l...", "..llg..", "lllgggd", ".lgggd.", "..ggg..", ".gg.dd.", ".g...d."],
                                    ["l": Palette.goldLight.glowing(200), "g": Palette.gold.glowing(180), "d": Palette.goldDim.glowing(80)])
    public static let skillPoint = Sprite(["...l...", "..llg..", ".llggd.", "lggggdd", ".ggggd.", "..gdd..", "...d..."],
                                          ["l": Palette.white.glowing(200), "g": Palette.cyan.glowing(160), "d": rgb(0x1f8f87).glowing(60)])
    public static let lock = Sprite(["..###..", ".#...#.", ".#...#.", "#######", "###.###", "###.###", "#######"], ["#": Palette.muted])
    public static let depth = Sprite(["..###..", "..###..", "..###..", "#######", ".#####.", "..###..", "...#..."], ["#": Palette.text2])

    // Tab, stat and setting icons: 7x7 silhouettes in whatever colour the caller tints them.
    public static let tabBalls = Sprite(["..###..", ".#.####", "#.#####", "#######", "#######", ".#####.", "..###.."], ["#": Palette.text])
    public static let tabUpgrade = Sprite(["...#...", "..###..", ".#####.", "#######", "..###..", "..###..", "..###.."], ["#": Palette.text])
    public static let tabSkills = Sprite(["...#...", "..###..", "...#...", ".#.#.#.", ".#####.", ".#...#.", "###.###"], ["#": Palette.text])
    public static let tabStar = Sprite(["...#...", "...#...", "#######", ".#####.", "..###..", ".##.##.", ".#...#."], ["#": Palette.text])
    public static let chevronRight = Sprite([".#.....", "..#....", "...#...", "....#..", "...#...", "..#....", ".#....."], ["#": Palette.text2])
    public static let chevronLeft = Sprite([".....#.", "....#..", "...#...", "..#....", "...#...", "....#..", ".....#."], ["#": Palette.text2])
    public static let close = Sprite(["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"], ["#": Palette.text])

    public static let statSpeed = Sprite(["#..#...", ".#..#..", "..#..#.", "...#..#", "..#..#.", ".#..#..", "#..#..."], ["#": Palette.text])
    public static let statDamage = Sprite(["......#", ".....#.", "....#..", "#..#...", ".##....", ".##....", "#..#..."], ["#": Palette.text])
    public static let statSpecial = Sprite(["...#...", "...#...", "..###..", "#######", "..###..", "...#...", "...#..."], ["#": Palette.text])

    public static let sound = Sprite(["...#...", "..##.#.", "####..#", "####..#", "####..#", "..##.#.", "...#..."], ["#": Palette.text])
    public static let haptic = Sprite(["#.###.#", "#.#.#.#", "..#.#..", "..#.#..", "..#.#..", "#.#.#.#", "#.###.#"], ["#": Palette.text])
    public static let glowIcon = Sprite(["#..#..#", ".#...#.", "..###..", "#.###.#", "..###..", ".#...#.", "#..#..#"], ["#": Palette.text])

    /// 7x7 skill icons, one per effect kind.
    public static func skillIcon(_ e: SkillEffect) -> Sprite {
        switch e {
        case .damage: return statDamage
        case .speed: return statSpeed
        case .money: return Sprite(["..###..", ".#.#.#.", ".#.#...", "..###..", "...#.#.", ".#.#.#.", "..###.."], ["#": Palette.text])
        case .crit: return Sprite(["...#...", ".#####.", ".#...#.", "##.#.##", ".#...#.", ".#####.", "...#..."], ["#": Palette.text])
        case .critDamage: return Sprite(["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"], ["#": Palette.text])
        case .radar: return Sprite(["..###..", ".#...#.", "#..#..#", "#.###.#", "#..#..#", ".#...#.", "..###.."], ["#": Palette.text])
        case .offline: return Sprite(["####...", "..#....", ".#.....", "####...", "....###", ".....#.", "....###"], ["#": Palette.text])
        case .startCash: return Sprite(["...#...", "..###..", ".#.#.#.", "...#...", "...#...", ".#####.", "......."], ["#": Palette.text])
        case .combo: return Sprite(["#.....#", "##...##", "#.#.#.#", "#..#..#", "#.....#", "#.....#", "#.....#"], ["#": Palette.text])
        case .tap: return Sprite(["..#....", "..#....", "..####.", "..#####", "#.#####", "#######", ".#####."], ["#": Palette.text])
        case .lantern: return Sprite(["..###..", ".#...#.", ".#####.", "#.###.#", "#.###.#", ".#####.", "..###.."], ["#": Palette.text])
        case .sonar: return Sprite(["#.....#", ".......", "..###..", "..#.#..", "..###..", ".......", "#.....#"], ["#": Palette.text])
        case .unlock(let k): return ballIcon(k)
        }
    }
}
