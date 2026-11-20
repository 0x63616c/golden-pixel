# Music

The menus play one loop; a level plays a shuffled playlist of ten tracks, each fading into
the next. Every track is CC0 (public domain), so none needs a credit line and all may ship in
the app and in trailers.

| File in `App/Music` | Track | Artist | Licence | Source |
| --- | --- | --- | --- | --- |
| `menu-chill-fever` | A Chill Fever (Loopable) | Pro Sensory | CC0 | https://opengameart.org/content/a-chill-fever-loopable |
| `game-plains-of-luminescence` | Plains of Luminescence (loop) | vitalezzz | CC0 | https://opengameart.org/content/plains-of-luminescence |
| `game-one-cool-minute` | One Cool Minute | Loyalty Freak Music | CC0 1.0 | https://freemusicarchive.org/music/Loyalty_Freak_Music/MINIMAL_AMBIENT_BOUNCE/Loyalty_Freak_Music_-_MINIMAL_AMBIENT_BOUNCE_-_02_One_Cool_Minute/ |
| `game-waiting-tttt` | Waiting TTTT | Loyalty Freak Music | CC0 1.0 | https://freemusicarchive.org/music/Loyalty_Freak_Music/MINIMAL_AMBIENT_BOUNCE/ |
| `game-once-more-with-you` | Once more with you | Loyalty Freak Music | CC0 1.0 | https://freemusicarchive.org/music/Loyalty_Freak_Music/MINIMAL_AMBIENT_BOUNCE/ |
| `game-static-shoes` | Static Shoes | Loyalty Freak Music | CC0 1.0 | https://freemusicarchive.org/music/Loyalty_Freak_Music/MINIMAL_AMBIENT_BOUNCE/Loyalty_Freak_Music_-_MINIMAL_AMBIENT_BOUNCE_-_04_Static_Shoes/ |
| `game-napping-on-a-cloud` | Napping on a Cloud | congusbongus | CC0 | https://opengameart.org/content/napping-on-a-cloud |
| `game-optimistic-day` | Optomistic Day Mastered (Loopable) | Pro Sensory | CC0 | https://opengameart.org/content/optomistic-day-mastered-loopable |
| `game-synthwave-house` | Synthwave House Loop | Fupi | CC0 | https://opengameart.org/content/synthwave-house-loop |
| `game-calm-relax` | Calm Relax 1 (Synthwave 421k), first 4:30 | cynicmusic | CC0 | https://opengameart.org/content/calm-relax-1-synthwave-421k |
| `game-observing-the-star` | Observing the Star ("Another space background track") | yd | CC0 | https://opengameart.org/content/another-space-background-track |

Licences were read on each track's page on 2026-11-20. CC0 on OpenGameArt is the uploader's
own declaration.

## How it plays

- The core decides, the app plays. `Game.musicCue` says menu, game or off (the MUSIC switch
  in Settings); `Playlist` gives the order: every track once, shuffled, then a new shuffle,
  never the same track twice in a row (`MusicTests`).
- `App/Music.swift` fades between the menu loop and the level (1.2 s) and from one level
  track into the next (3 s). Going to the menu and back picks the level track up where it
  stopped.
- It stays silent while another app is playing audio, in staged scenes (`-GPScene`), and
  with `-GPMute YES`, which `ios/ios.sh` passes on every simulator launch so simulators don't
  play through the Mac's speakers (sound effects too). `SOUND=1 just ios-sim` turns it back on.

## Adding or changing a track

1. Check the licence on the track's own page. No NC or ND. A track that needs credit (CC BY)
   also needs a visible credit line in the app, which does not exist yet.
2. Download it, add a row to `TRACKS` in `tools/bake-music.py`, and run
   `python3 tools/bake-music.py <folder with the downloads>`. It trims the silence at both
   ends, brings every track to the same loudness (-19 LUFS) and writes 96 kbps AAC.
3. Add the name to `Music.gameTracks` (or `menuTrack`) in `App/Music.swift` and a row above.

The menu track repeats on the sample, so it has to be a real loop; level tracks only need to
be full length, because the crossfade covers their ends.
