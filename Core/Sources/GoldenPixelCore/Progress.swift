/// Everything that persists between sessions. Saved as versioned JSON (`SaveCodec`).
public struct Settings: Codable, Equatable, Sendable {
    public var sound = true
    public var haptics = true
    public var glow = false
    public init() {}
}

public struct Progress: Codable, Equatable, Sendable {
    public var money: Double = 0
    public var level: Int = 1
    public var maxLevel: Int = 1
    public var stars: Int = 0
    public var skillPoints: Int = 0
    public var skillRanks: [String: Int] = [:]
    public var balls: [String: BallProgress] = [BallKind.basic.rawValue: BallProgress(owned: 1)]
    public var runEarnings: Double = 0
    public var totalEarnings: Double = 0
    /// Smoothed money per second, for offline earnings.
    public var incomeRate: Double = 0
    public var settings = Settings()

    public init() {}

    public func ball(_ k: BallKind) -> BallProgress { balls[k.rawValue] ?? BallProgress() }
    public mutating func update(_ k: BallKind, _ f: (inout BallProgress) -> Void) {
        var p = ball(k)
        f(&p)
        balls[k.rawValue] = p
    }
}

/// The board as it stands, so a level resumes where you left it.
public struct BoardSave: Codable, Equatable, Sendable {
    public var level: Int
    /// Cells that were blocks and are now gone.
    public var broken: [Int]
    /// Damaged blocks: index and remaining hit points.
    public var damaged: [Int: Double]
    public var revealed: [Int]
}

public struct SaveFile: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var progress: Progress
    public var board: BoardSave?
    /// Seconds since 1970, for offline earnings.
    public var savedAt: Double

    public init(progress: Progress, board: BoardSave?, savedAt: Double) {
        version = SaveFile.currentVersion
        self.progress = progress
        self.board = board
        self.savedAt = savedAt
    }
}

public enum SaveCodec {
    struct VersionProbe: Codable { var version: Int }

    /// Decodes any known version, migrating forward. A save from a newer build than this one
    /// returns nil, so the caller keeps the file instead of overwriting it.
    public static func decode(_ data: Data) -> SaveFile? {
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else { return nil }
        switch probe.version {
        case 1: return try? JSONDecoder().decode(SaveFile.self, from: data)
        default: return nil
        }
    }

    public static func encode(_ s: SaveFile) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(s)) ?? Data()
    }

    public static func snapshot(_ b: Board, fresh: Board) -> BoardSave {
        var broken: [Int] = [], damaged: [Int: Double] = [:], revealed: [Int] = []
        for i in 0..<b.kind.count {
            if (fresh.kind[i] == .block || fresh.kind[i] == .gold) && b.kind[i] == .empty { broken.append(i) }
            else if b.kind[i] == .block || b.kind[i] == .gold, b.hp[i] < b.maxHP[i] { damaged[i] = b.hp[i] }
            if b.revealed[i] { revealed.append(i) }
        }
        return BoardSave(level: b.level, broken: broken, damaged: damaged, revealed: revealed)
    }

    public static func restore(_ s: BoardSave, into b: Board) {
        guard s.level == b.level else { return }
        for i in s.broken where i >= 0 && i < b.kind.count { b.kind[i] = .empty; b.hp[i] = 0 }
        for (i, h) in s.damaged where i >= 0 && i < b.kind.count { b.hp[i] = min(b.maxHP[i], max(0.01, h)) }
        for i in s.revealed where i >= 0 && i < b.kind.count { b.revealed[i] = true; b.revealedAt[i] = -1 }
    }
}

import Foundation
