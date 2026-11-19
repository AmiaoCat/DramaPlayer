"""Build the attributed demo excerpts and matching posters from local source films."""

import argparse
from pathlib import Path
import subprocess

# Start and duration in seconds, horizontal focus fraction, and poster offset in seconds.
CUTS = {
    "steel-01": (143, 12, 0.30, 1.0),
    "steel-02": (263, 14, 0.38, 1.8),
    "steel-03": (498, 13, 0.60, 6),
    "steel-04": (550, 14, 0.57, 3.5),
    "coffee-01": (13, 12, 0.54, 3.5),
    "coffee-02": (46, 15, 0.54, 4),
    "coffee-03": (116, 12, 0.62, 4),
    "coffee-04": (134, 13, 0.52, 4),
    "charge-01": (9, 13, 0.55, 5),
    "charge-02": (45, 13, 0.45, 5),
    "charge-03": (77, 14, 0.57, 4),
    "charge-04": (153, 13, 0.40, 4),
    "charge-landscape": (45, 18, None, 5),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", type=Path, help="Directory containing steel.webm, coffee.webm and charge.webm")
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "Media" / "Series")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--clip", choices=CUTS, help="Regenerate one clip and its poster")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    ffmpeg = [args.ffmpeg, "-hide_banner", "-loglevel", "error", "-y"]

    for clip, (start, duration, focus, poster_time) in CUTS.items():
        if args.clip and args.clip != clip:
            continue
        series = clip.split("-")[0]
        source = args.sources / f"{series}.webm"
        video = args.output / f"{clip}.mp4"
        cover = args.output / f"{clip}.jpg"
        if focus is None:
            framing = "scale=960:-2:flags=lanczos"
        else:
            framing = f"crop=trunc(ih*9/32)*2:ih:clip(iw*{focus}-ow/2\\,0\\,iw-ow):0,scale=360:640:flags=lanczos"
        audio = ["-an"] if series == "steel" else [
            "-map", "0:a:0", "-ac", "2", "-c:a", "aac", "-b:a", "96k",
            "-af", f"afade=t=in:d=0.12,afade=t=out:st={duration - 0.18}:d=0.18",
        ]
        subprocess.run(ffmpeg + [
            "-ss", str(start), "-i", str(source), "-t", str(duration), "-map", "0:v:0",
            "-vf", f"{framing},setsar=1,fps=24",
            "-c:v", "libx264", "-preset", "fast", "-crf", "23", "-pix_fmt", "yuv420p",
            "-map_metadata", "-1", *audio, "-movflags", "+faststart", str(video),
        ], check=True)
        subprocess.run(ffmpeg + [
            "-ss", str(poster_time), "-i", str(video), "-frames:v", "1", "-q:v", "3", str(cover),
        ], check=True)


if __name__ == "__main__":
    main()
