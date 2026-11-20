#!/usr/bin/env python3
"""Bake the background music into App/Music.

    python3 tools/bake-music.py <folder holding the downloaded source files>

Each source (see docs/music.md for where it comes from and its licence) is trimmed of the
silence at both ends, brought to one loudness so no track jumps out of the shuffle, and
encoded as 96 kbps AAC. Needs ffmpeg and macOS's afconvert.
"""
import pathlib
import re
import subprocess
import sys
import tempfile
import wave

# Integrated loudness every track is brought to; the app plays them at Music.volume on top.
TARGET_LUFS = -19.0
# Highest sample peak after the gain (dBFS); a track that would pass it goes through a limiter.
CEILING_DB = -1.0
BITRATE = 96_000

# (name in the bundle, source file, seconds to keep or None for all of it)
TRACKS = [
    ("menu-chill-fever", "chillfever.mp3", None),
    ("game-plains-of-luminescence", "plains_loop.mp3", None),
    ("game-one-cool-minute", "lfm_02_-_One_Cool_Minute.mp3", None),
    ("game-waiting-tttt", "lfm_05_-_Waiting_TTTT.mp3", None),
    ("game-once-more-with-you", "lfm_01_-_Once_more_with_you.mp3", None),
    ("game-static-shoes", "lfm_04_-_Static_Shoes.mp3", None),
    ("game-napping-on-a-cloud", "napping.ogg", None),
    ("game-optimistic-day", "optimistic.mp3", None),
    ("game-synthwave-house", "synthhouse.ogg", None),
    # Nearly eight minutes of pads: the first four and a half are plenty in a rotation.
    ("game-calm-relax", "calmrelax.mp3", 270),
    ("game-observing-the-star", "obs/ObservingTheStar.ogg", None),
]

# Cuts digital silence (encoder padding, dead air) from the start, then from the end.
TRIM = "silenceremove=start_periods=1:start_threshold=-60dB:detection=peak"
TRIM_BOTH = f"{TRIM},areverse,{TRIM},areverse"
FADE = 6


def run(*args):
    return subprocess.run([str(a) for a in args], check=True, capture_output=True, text=True)


def ffmpeg(src, filters, dst):
    run("ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", src, "-af", filters, "-ac", "2", "-ar", "44100", "-c:a", "pcm_s16le", dst)


def loudness(path):
    """(integrated LUFS, sample peak dBFS) of a wav."""
    err = run("ffmpeg", "-nostdin", "-hide_banner", "-i", path, "-af", "ebur128=peak=sample", "-f", "null", "-").stderr
    summary = err[err.rindex("Summary:"):]
    lufs = float(re.search(r"I:\s+(-?[\d.]+) LUFS", summary).group(1))
    peak = float(re.search(r"Peak:\s+(-?[\d.]+) dBFS", summary).group(1))
    return lufs, peak


def frames(path):
    with wave.open(str(path)) as w:
        return w.getnframes(), w.getframerate()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sources = pathlib.Path(sys.argv[1])
    out = pathlib.Path(__file__).resolve().parent.parent / "App" / "Music"
    out.mkdir(parents=True, exist_ok=True)
    total = 0
    with tempfile.TemporaryDirectory() as tmp:
        tmp = pathlib.Path(tmp)
        for name, source, keep in TRACKS:
            trimmed, level, back = tmp / "trimmed.wav", tmp / "level.wav", tmp / "back.wav"
            cut = f"atrim=end={keep},afade=t=out:st={keep - FADE}:d={FADE}," if keep else ""
            ffmpeg(sources / source, cut + TRIM_BOTH, trimmed)
            lufs, peak = loudness(trimmed)
            gain = TARGET_LUFS - lufs
            limit = peak + gain > CEILING_DB
            # The limiter delays the audio a few ms, so it is only used where it is needed
            # (never on a track that has to loop on the sample).
            limiter = f",alimiter=limit={10 ** (CEILING_DB / 20):.3f}:level=disabled" if limit else ""
            ffmpeg(trimmed, f"volume={gain:.2f}dB{limiter}", level)
            dst = out / f"{name}.m4a"
            run("afconvert", "-f", "m4af", "-d", "aac", "-s", "2", "-b", BITRATE, "-q", "127", level, dst)
            # Decoded again it must be exactly as long as what went in, or a loop would gap.
            run("afconvert", "-f", "WAVE", "-d", "LEI16", dst, back)
            n, rate = frames(level)
            assert frames(back)[0] == n, f"{name}: {frames(back)[0]} frames decoded, {n} encoded"
            size = dst.stat().st_size
            total += size
            print(f"{name:30s} {n / rate / 60:5.2f} min  {lufs:6.1f} LUFS {gain:+5.1f} dB{' limited' if limit else '        '}  {size / 1e6:5.2f} MB")
    print(f"{len(TRACKS)} tracks, {total / 1e6:.1f} MB in {out}")


if __name__ == "__main__":
    main()
