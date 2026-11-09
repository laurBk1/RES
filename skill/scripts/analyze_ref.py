"""Measure a reference reel: cuts, audio hits, speech, and frame sheets for visual review.
usage: analyze_ref.py VIDEO OUT_DIR
writes OUT_DIR/<id>/: cuts.txt, hits.txt, transcript.txt, sheet_NN.jpg (1 frame / 0.5s, 4x4 grid with timestamps), cut_NN.jpg."""
import json, os, subprocess, sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from transcribe import recognize_whisper


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stderr


def cuts(video):
    out = sh(["ffmpeg", "-i", video, "-vf", "scdet=threshold=12", "-an", "-f", "null", "-"])
    return [float(l.split("lavfi.scd.time:")[1].split()[0]) for l in out.splitlines() if "lavfi.scd.time:" in l]


def hits(video, hop=0.01):
    """Sharp loudness jumps, which in edited reels are mostly whooshes, pops, and impacts."""
    pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-vn", "-ac", "1", "-ar", "16000", "-f", "f32le", "-"],
                         capture_output=True).stdout
    x = np.frombuffer(pcm, np.float32)
    n = int(16000 * hop)
    e = 10 * np.log10(np.array([np.mean(x[i:i + n] ** 2) + 1e-10 for i in range(0, len(x) - n, n)]))
    rise = e[5:] - e[:-5]
    out, last = [], -1
    for i in np.where(rise > 14)[0]:
        t = (i + 5) * hop
        if t - last > 0.25:
            out.append((round(t, 2), round(float(e[i + 5]), 1)))
            last = t
    return out


def main():
    video, root = sys.argv[1], sys.argv[2]
    vid = os.path.splitext(os.path.basename(video))[0]
    d = os.path.join(root, vid)
    os.makedirs(d, exist_ok=True)
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", video],
                               capture_output=True, text=True).stdout)
    c = cuts(video)
    open(os.path.join(d, "cuts.txt"), "w").write("\n".join(f"{t:.2f}" for t in c) + "\n")
    h = hits(video)
    open(os.path.join(d, "hits.txt"), "w").write("\n".join(f"{t:.2f} {db}" for t, db in h) + "\n")
    os.environ.setdefault("VIDEO_SHORT_LANGUAGE", "en")
    words, _ = recognize_whisper(video, language=os.environ["VIDEO_SHORT_LANGUAGE"])
    open(os.path.join(d, "transcript.txt"), "w").write(" ".join(f"[{w['start']:.1f}]{w['text']}" for w in words) + "\n")
    # Frame sheets: 2 fps, 16 per sheet, timestamp burned in.
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", video, "-vf",
                    "fps=2,scale=270:-2,drawtext=text='%{pts\\:hms}':x=6:y=6:fontsize=22:fontcolor=yellow:box=1:boxcolor=black@0.7,tile=4x4",
                    os.path.join(d, "sheet_%02d.jpg")], check=True)
    # Strips around each cut: 3 frames before, 3 after.
    for k, t in enumerate(c[:40]):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{max(0, t - 0.1):.2f}", "-i", video, "-frames:v", "6",
                        "-vf", "scale=180:-2,tile=6x1", os.path.join(d, f"cut_{k:02d}.jpg")])
    rate = len(c) / dur if dur else 0
    summary = {"id": vid, "duration": round(dur, 2), "cuts": len(c), "avg_shot_s": round(dur / (len(c) + 1), 2),
               "cuts_per_s": round(rate, 2), "audio_hits": len(h), "words": len(words)}
    json.dump(summary, open(os.path.join(d, "summary.json"), "w"))
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
