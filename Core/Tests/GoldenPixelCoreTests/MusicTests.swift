import XCTest
@testable import GoldenPixelCore

final class MusicTests: XCTestCase {
    /// The menus get the menu loop, a level gets the playlist, and the switch silences both.
    func testCueFollowsTheScreenAndTheMusicSetting() {
        let g = Game(seed: 1)
        XCTAssertEqual(g.musicCue, .menu)
        for screen in [Screen.howTo, .settings, .levels] {
            g.ui.screen = screen
            XCTAssertEqual(g.musicCue, .menu, "\(screen)")
        }
        g.perform(.play)
        XCTAssertEqual(g.musicCue, .game)
        g.perform(.pause)
        XCTAssertEqual(g.musicCue, .game, "the pause card keeps the level's music")
        g.progress.settings.music = false
        XCTAssertEqual(g.musicCue, .off)
        g.ui.screen = .menu
        XCTAssertEqual(g.musicCue, .off)
    }

    /// The MUSIC row on the settings card is the switch.
    func testSettingsCardTogglesMusic() {
        let r = Renderer()
        let g = Scenes.make("settings")
        r.render(g)
        XCTAssertTrue(g.progress.settings.music, "music is on until the player turns it off")
        let rows = (0..<4).map { j in g.ui.hits.last { $0.action == .setting(j) } }
        XCTAssertFalse(rows.contains { $0 == nil }, "sound, music, haptics and glow each have a row")
        let before = g.progress.settings
        g.perform(.setting(1))
        var expected = before
        expected.music = false
        XCTAssertEqual(g.progress.settings, expected, "the second row turns music off and nothing else")
    }

    /// A save written before the music setting existed still loads, with music on.
    func testSaveWithoutAMusicSettingStillLoads() throws {
        let data = SaveCodec.encode(Scenes.make("mid").saveFile())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var progress = try XCTUnwrap(json["progress"] as? [String: Any])
        var settings = try XCTUnwrap(progress["settings"] as? [String: Any])
        XCTAssertNotNil(settings.removeValue(forKey: "music"))
        settings["sound"] = false
        progress["settings"] = settings
        json["progress"] = progress
        let old = try JSONSerialization.data(withJSONObject: json)
        let s = try XCTUnwrap(SaveCodec.decode(old), "an older save must not be thrown away")
        XCTAssertTrue(s.progress.settings.music)
        XCTAssertFalse(s.progress.settings.sound, "the settings it does have are kept")
    }

    /// Every track plays once before any repeats, and none plays twice in a row.
    func testPlaylistPlaysEveryTrackEachRoundAndNeverRepeatsBackToBack() {
        for seed in UInt64(0)..<50 {
            for count in 2...11 {
                var p = Playlist(count: count, seed: seed)
                var last: Int?
                for round in 0..<20 {
                    var seen = Set<Int>()
                    for _ in 0..<count {
                        let t = p.next()
                        XCTAssertTrue((0..<count).contains(t))
                        XCTAssertNotEqual(t, last, "seed \(seed), \(count) tracks, round \(round)")
                        seen.insert(t)
                        last = t
                    }
                    XCTAssertEqual(seen.count, count, "seed \(seed), \(count) tracks, round \(round)")
                }
            }
        }
    }

    /// The order is shuffled: it differs between seeds and between rounds.
    func testPlaylistIsShuffled() {
        func round(_ p: inout Playlist) -> [Int] { (0..<10).map { _ in p.next() } }
        var a = Playlist(count: 10, seed: 1), b = Playlist(count: 10, seed: 2)
        let first = round(&a)
        XCTAssertNotEqual(first, round(&b))
        XCTAssertNotEqual(first, round(&a))
        XCTAssertNotEqual(first, Array(0..<10))
    }

    func testPlaylistOfOneOrNoneIsSafe() {
        var one = Playlist(count: 1, seed: 3), none = Playlist(count: 0, seed: 3)
        XCTAssertEqual([one.next(), one.next()], [0, 0])
        XCTAssertEqual(none.next(), 0)
    }
}
