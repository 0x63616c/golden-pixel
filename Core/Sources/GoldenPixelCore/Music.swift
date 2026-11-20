/// Background music, as far as the rules go: what should be playing and in what order. The
/// app owns the audio itself (`App/Music.swift`).

public enum MusicCue: Equatable, Sendable {
    case off
    /// The menu, how to play and settings: one calm loop.
    case menu
    /// In a level: the shuffled playlist.
    case game
}

extension Game {
    public var musicCue: MusicCue {
        guard progress.settings.music else { return .off }
        return ui.screen == .game ? .game : .menu
    }
}

/// The order the in-game tracks play in: every track once in a random order, then a fresh
/// shuffle, and never the same track twice in a row.
public struct Playlist: Sendable {
    public let count: Int
    private var rng: RNG
    /// The rest of this round, played from the end.
    private var queue: [Int] = []
    private var last: Int?

    public init(count: Int, seed: UInt64) {
        self.count = max(0, count)
        rng = RNG(seed: seed)
    }

    /// The index of the track to play next.
    public mutating func next() -> Int {
        guard count > 1 else { return 0 }
        if queue.isEmpty {
            queue = Array(0..<count)
            for i in stride(from: count - 1, to: 0, by: -1) { queue.swapAt(i, rng.int(i + 1)) }
            // A new round must not open with the track that closed the last one.
            if queue[count - 1] == last { queue.swapAt(count - 1, rng.int(count - 1)) }
        }
        let track = queue.removeLast()
        last = track
        return track
    }
}
