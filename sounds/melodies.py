"""melodies.py renders Tug's holiday tunes from his own woof. Run through `make melodies`.

Each note is tug-woof.caf resampled to the note's pitch, so a higher note is also a shorter bark,
the way a smaller dog would sound. Notes are laid out at the tune's rhythm, the file ends with a
pause so the alarm loop breathes, and the result is matched in loudness to tug-barking.caf so the
volume boost means the same thing for a tune as for the bark.

Every melody here was published before 1930 or is traditional. The note lists are our own
arrangements, written for barking: first phrase only, held notes shortened where a long rest
would only be silence. Needs ffmpeg and afconvert (macOS).
"""

import os
import re
import subprocess
import sys
import tempfile

RATE = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
WOOF = os.path.join(HERE, "tug-woof.caf")
BARKING = os.path.join(HERE, "tug-barking.caf")
WOOF_SECONDS = 0.54
LOWEST = -5
HIGHEST = 9
PAUSE = 0.8
FADE = 0.015
MIN_SECONDS = 8.0
MAX_SECONDS = 12.0
REST = None

# TUNES maps each outfit asset to its tune. A note is (semitones from the tonic, beats), or
# (REST, beats). Shift moves the whole tune so every note lands within LOWEST and HIGHEST
# semitones of the woof's natural pitch. Beat is the length of one beat in seconds.
TUNES = {
    # Auld Lang Syne. Traditional Scots air, set to Robert Burns's words in 1799. Key of F.
    "party": {
        "shift": 0,
        "beat": 0.32,
        "notes": [
            (-5, 1),
            (0, 1.5), (0, 0.5), (0, 1), (4, 1),
            (2, 1.5), (0, 0.5), (2, 1), (4, 1),
            (0, 1.5), (0, 0.5), (4, 1), (7, 1),
            (9, 3), (9, 1),
            (7, 1.5), (4, 0.5), (4, 1), (0, 1),
            (2, 1.5), (0, 0.5), (2, 1), (4, 1),
            (0, 1.5), (-3, 0.5), (-3, 1), (-5, 1),
            (0, 3),
        ],
    },
    # Let Me Call You Sweetheart. Leo Friedman, 1910. Key of G, waltz.
    "heart": {
        "shift": -9,
        "beat": 0.24,
        "notes": [
            (4, 2), (7, 1),
            (12, 2), (14, 1),
            (16, 1), (7, 2),
            (6, 2), (7, 1),
            (9, 3),
            (9, 3),
            (9, 3),
            (11, 2), (10, 1),
            (11, 2), (12, 1),
            (14, 1), (11, 2),
            (9, 2), (11, 1),
            (7, 3),
            (7, 3),
            (7, 3),
        ],
    },
    # The Irish Washerwoman. Traditional jig, in print by 1790. Key of G, one beat per eighth.
    # Pickup and bars 1 to 4, then the closing bars 7 and 8, taken slower than a dance tempo.
    "shamrock": {
        "shift": 0,
        "beat": 0.25,
        "notes": [
            (7, 1), (5, 1),
            (4, 1), (0, 1), (0, 1), (-5, 1), (0, 1), (0, 1),
            (4, 1), (0, 1), (4, 1), (7, 1), (5, 1), (4, 1),
            (5, 1), (2, 1), (2, 1), (-3, 1), (2, 1), (2, 1),
            (5, 1), (2, 1), (5, 1), (9, 1), (7, 1), (5, 1),
            (5, 1), (4, 1), (5, 1), (2, 1), (7, 1), (5, 1),
            (4, 1), (0, 1), (0, 1), (0, 3),
        ],
    },
    # In the Hall of the Mountain King. Edvard Grieg, 1875. Key of B minor, one beat per eighth.
    "halloween": {
        "shift": -3,
        "beat": 0.27,
        "notes": [
            (0, 1), (2, 1), (3, 1), (5, 1), (7, 1), (3, 1), (7, 2),
            (6, 1), (2, 1), (6, 2), (5, 1), (1, 1), (5, 2),
            (0, 1), (2, 1), (3, 1), (5, 1), (7, 1), (3, 1), (7, 1), (12, 1),
            (10, 1), (7, 1), (3, 1), (7, 1), (10, 4),
        ],
    },
    # Over the River and Through the Wood. Traditional tune to Lydia Maria Child's 1844 poem.
    # Key of A, one beat per eighth.
    "thanksgiving": {
        "shift": 5,
        "beat": 0.23,
        "notes": [
            (-5, 1), (-5, 1), (-5, 1), (-5, 1), (-8, 1), (-7, 1),
            (-5, 2), (-5, 1), (-5, 2), (-5, 1),
            (0, 1), (0, 1), (0, 1), (-1, 2), (-3, 1),
            (-5, 3), (REST, 2), (-5, 1),
            (-7, 1), (-7, 1), (-7, 1), (-7, 2), (-7, 1),
            (-8, 1), (-8, 1), (-8, 1), (-8, 2), (-8, 1),
            (-10, 2), (-10, 1), (-10, 2), (-8, 1),
            (-10, 3), (-5, 3),
        ],
    },
    # Jingle Bells. James Lord Pierpont, 1857. Key of C, the chorus's closing half.
    "santa": {
        "shift": 0,
        "beat": 0.27,
        "notes": [
            (4, 1), (4, 1), (4, 2),
            (4, 1), (4, 1), (4, 2),
            (4, 1), (7, 1), (0, 1.5), (2, 0.5),
            (4, 4),
            (5, 1), (5, 1), (5, 1.5), (5, 0.5),
            (5, 1), (4, 1), (4, 1), (4, 0.5), (4, 0.5),
            (7, 1), (7, 1), (5, 1), (2, 1),
            (0, 4),
        ],
    },
}


def run(args):
    """run executes a command and returns its stderr, failing the script on a nonzero exit."""
    done = subprocess.run(args, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit(f"melodies: {args[0]} failed: {done.stderr.strip()[-600:]}")
    return done.stderr


def loudness(path):
    """loudness returns the integrated loudness in LUFS and the true peak in dBTP of a file."""
    out = run(["ffmpeg", "-hide_banner", "-nostats", "-i", path,
               "-af", "ebur128=peak=true", "-f", "null", "-"])
    summary = out[out.rfind("Summary:"):]
    integrated = re.search(r"I:\s+(-?[\d.]+) LUFS", summary)
    peak = re.search(r"Peak:\s+(-?[\d.]+|-inf) dBFS", summary)
    if not integrated or not peak:
        sys.exit(f"melodies: no loudness summary for {path}")
    return float(integrated.group(1)), float(peak.group(1))


def plan(asset, tune):
    """plan checks a tune's range and returns (ratio, start sample, length in samples) per bark."""
    barks, at = [], 0.0
    notes = tune["notes"]
    for index, (semitone, beats) in enumerate(notes):
        seconds = beats * tune["beat"]
        if semitone is not REST:
            pitch = semitone + tune["shift"]
            if not LOWEST <= pitch <= HIGHEST:
                sys.exit(f"melodies: {asset} note {index} is {pitch} semitones from the woof, "
                         f"outside {LOWEST} to {HIGHEST}")
            ratio = 2 ** (pitch / 12)
            end = at + seconds
            if index == len(notes) - 1:
                end = at + max(seconds, WOOF_SECONDS / ratio + PAUSE)
            start = round(at * RATE)
            barks.append((ratio, start, round(end * RATE) - start))
        at += seconds
    return barks


def render(asset, tune, scratch):
    """render writes one tune to a caf in this folder, loudness matched to the bark loop."""
    barks = plan(asset, tune)
    total = barks[-1][1] + barks[-1][2]
    seconds = total / RATE
    if not MIN_SECONDS <= seconds <= MAX_SECONDS:
        sys.exit(f"melodies: {asset} runs {seconds:.2f} s, outside {MIN_SECONDS} to {MAX_SECONDS}")

    # Each bark is cut or padded to its slot so the notes join end to end with no drift.
    chains, labels, cursor = [], [], 0
    splits = "".join(f"[w{i}]" for i in range(len(barks)))
    chains.append(f"[0:a]asplit={len(barks)}{splits}")
    for i, (ratio, start, length) in enumerate(barks):
        if start > cursor:
            chains.append(
                f"anullsrc=r={RATE}:cl=mono,atrim=end_sample={start - cursor}[r{i}]")
            labels.append(f"[r{i}]")
        fade_start = max(0.0, length / RATE - FADE)
        chains.append(
            f"[w{i}]asetrate={RATE * ratio},aresample={RATE},"
            f"atrim=end_sample={length},apad=whole_len={length},"
            f"afade=t=out:st={fade_start}:d={FADE}[n{i}]")
        labels.append(f"[n{i}]")
        cursor = start + length
    chains.append(f"{''.join(labels)}concat=n={len(labels)}:v=0:a=1[out]")

    raw = os.path.join(scratch, f"{asset}-raw.wav")
    run(["ffmpeg", "-hide_banner", "-y", "-i", WOOF, "-filter_complex", ";".join(chains),
         "-map", "[out]", "-ac", "1", "-ar", str(RATE), "-c:a", "pcm_s16le",
         "-fflags", "+bitexact", "-flags:a", "+bitexact", raw])

    target, _ = loudness(BARKING)
    level, _ = loudness(raw)
    gain = round(target - level, 2)
    matched = os.path.join(scratch, f"{asset}.wav")
    run(["ffmpeg", "-hide_banner", "-y", "-i", raw, "-af", f"volume={gain}dB",
         "-c:a", "pcm_s16le", "-fflags", "+bitexact", "-flags:a", "+bitexact", matched])
    level, peak = loudness(matched)
    if peak > -0.5:
        sys.exit(f"melodies: {asset} peaks at {peak} dBFS after a {gain} dB gain")

    out = os.path.join(HERE, f"melody-{asset}.caf")
    run(["afconvert", "-f", "caff", "-d", f"LEI16@{RATE}", "-c", "1", matched, out])
    print(f"melody-{asset}.caf  {seconds:5.2f} s  {level:6.1f} LUFS  peak {peak:5.1f} dBFS")


def main():
    """main renders every tune, or only the assets named on the command line."""
    names = sys.argv[1:] or list(TUNES)
    unknown = [name for name in names if name not in TUNES]
    if unknown:
        sys.exit(f"melodies: unknown tune {', '.join(unknown)}")
    with tempfile.TemporaryDirectory() as scratch:
        for name in names:
            render(name, TUNES[name], scratch)


if __name__ == "__main__":
    main()
