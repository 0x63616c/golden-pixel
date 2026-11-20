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

/// Flat sprites: one colour per shape, plus a second flat colour for marks. No highlights or
/// shading. Icons that get tinted are plain silhouettes.
public enum Sprites {
    /// The in-play ball: a flat 5x5 circle on a 10x10 block, centred on its middle pixel.
    public static func ball(_ k: BallKind) -> Sprite { ballCache[k.index] }

    /// The ball at HUD size (7x7, matching the font's cap height) with a mark per type.
    public static func ballIcon(_ k: BallKind) -> Sprite { ballIconCache[k.index] }

    private static let ballCache: [Sprite] = BallKind.allCases.map { k in
        Sprite([".ccc.", "ccccc", "ccccc", "ccccc", ".ccc."], ["c": k.color.glowing(255)])
    }

    private static let ballIconCache: [Sprite] = BallKind.allCases.map { k in
        var rows = ["..ccc..", ".ccccc.", "ccccccc", "ccccccc", "ccccccc", ".ccccc.", "..ccc.."]
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
        return Sprite(rows, ["c": k.color.glowing(200), "m": Palette.black])
    }

    // HUD icons, 7x7 to match the font's 7-pixel caps.
    public static let coin = Sprite(["..ggg..", ".ggggg.", "gggdggg", "ggdddgg", "gggdggg", ".ggggg.", "..ggg.."],
                                    ["g": Palette.gold.glowing(160), "d": Palette.goldDim])
    public static let star = Sprite(["...g...", "...g...", "ggggggg", ".ggggg.", "..ggg..", ".gg.gg.", ".g...g."],
                                    ["g": Palette.gold.glowing(180)])
    /// A shard: a mint diamond.
    public static let shard = Sprite(["...m...", "..mmm..", ".mmmmm.", "mmmmmmm", ".mmmmm.", "..mmm..", "...m..."],
                                     ["m": Palette.mint.glowing(170)])
    public static let lock = Sprite(["..###..", ".#...#.", ".#...#.", "#######", "###.###", "###.###", "#######"], ["#": Palette.muted])
    public static let depth = Sprite(["..###..", "..###..", "..###..", "#######", ".#####.", "..###..", "...#..."], ["#": Palette.text2])

    // Button, stat and setting icons: 7x7 silhouettes in whatever colour the caller tints them.
    public static let tree = Sprite(["...#...", "..###..", "...#...", ".#.#.#.", ".#####.", ".#...#.", "###.###"], ["#": Palette.text])
    public static let menu = Sprite([".......", "#######", ".......", "#######", ".......", "#######", "......."], ["#": Palette.text])
    public static let close = Sprite(["#.....#", ".#...#.", "..#.#..", "...#...", "..#.#..", ".#...#.", "#.....#"], ["#": Palette.text])
    public static let play = Sprite(["#......", "###....", "#####..", "#######", "#####..", "###....", "#......"], ["#": Palette.text])
    public static let info = Sprite(["...#...", ".......", "..##...", "...#...", "...#...", "...#...", "..###.."], ["#": Palette.text])
    public static let gear = Sprite(["..#.#..", ".#####.", "##...##", ".#...#.", "##...##", ".#####.", "..#.#.."], ["#": Palette.text])
    public static let aim = Sprite(["...#...", "...#...", ".......", "##.#.##", ".......", "...#...", "...#..."], ["#": Palette.text])

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
        case .cash: return Sprite(["...#...", "..###..", ".#.#.#.", "...#...", "...#...", ".#####.", "......."], ["#": Palette.text])
        case .combo: return Sprite(["#.....#", "##...##", "#.#.#.#", "#..#..#", "#.....#", "#.....#", "#.....#"], ["#": Palette.text])
        case .lantern: return Sprite(["..###..", ".#...#.", ".#####.", "#.###.#", "#.###.#", ".#####.", "..###.."], ["#": Palette.text])
        case .sonar: return Sprite(["#.....#", ".......", "..###..", "..#.#..", "..###..", ".......", "#.....#"], ["#": Palette.text])
        case .unlock(let k): return ballIcon(k)
        case .ballStat(_, let s):
            switch s {
            case .damage: return statDamage
            case .speed: return statSpeed
            case .special: return statSpecial
            }
        case .ballSpec: return star
        }
    }
}
