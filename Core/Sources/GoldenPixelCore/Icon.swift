/// The app icon, drawn with the game's own rules on a 64x64 art canvas scaled 16x to 1024 px:
/// a crop of the board with the game's 10x10 cells, per-cell random durability, a tunnel dug toward the golden
/// pixel, top-left light only on faces open to the tunnel, a ball on its way in, and fog
/// (pure black) beyond.
public enum Icon {
    public static let size = 64
    public static let scale = 16

    public static func draw() -> Canvas {
        let c = Canvas(width: size, height: size)
        let cp = Tuning.cellPixels, n = 8
        // The crop puts the golden pixel's cell just above the middle.
        let offX = -13, offY = -8
        // Map: "." dug, "#" block, "G" gold, " " fog.
        let rows = [
            "  ####  ",
            " ###### ",
            "########",
            "####G###",
            "####.###",
            " ##..## ",
            " ##.##  ",
            "   .    ",
        ]
        let grid = rows.map { Array($0) }
        func at(_ x: Int, _ y: Int) -> Character { x >= 0 && y >= 0 && x < n && y < n ? grid[y][x] : " " }
        var rng = RNG(seed: 11)
        // Bright (tough) blues crowd the gold, faint ones the edge. Flat cells, no shading.
        let near: [Int] = [3, 4, 3, 4, 2], far: [Int] = [0, 1, 0, 2, 1]
        for y in 0..<n {
            for x in 0..<n {
                let k = at(x, y)
                guard k != " " else { continue }
                var base = Palette.floor
                if k == "#" {
                    let close = abs(x - 4) <= 1 && abs(y - 3) <= 1
                    base = Palette.tier((close ? near : far)[rng.int(5)])
                } else if k == "G" {
                    base = Palette.gold
                }
                c.fill(offX + x * cp, offY + y * cp, cp, cp, base)
            }
        }
        // A ball climbing the tunnel, with a two-pixel trail.
        let bx = offX + 4 * cp + 5, by = offY + 4 * cp + 5
        c.sprite(Sprites.ball(.basic), bx - 2, by - 2)
        c.set(bx, by + 4, BallKind.basic.shade)
        c.set(bx, by + 7, Palette.border)
        // Strip glow bits: the icon has no bloom.
        for i in c.pixels.indices { c.pixels[i] &= 0x00ff_ffff }
        return c
    }
}
