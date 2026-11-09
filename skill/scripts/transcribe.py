"""Transcribe a video with Parakeet (local, through HyperFrames) into word timestamps and a readable transcript.
usage: transcribe.py VIDEO OUT_PREFIX
writes OUT_PREFIX.json [{text,start,end}] and OUT_PREFIX.md (phrases with times and pauses).
Parakeet keeps um, uh, stutters, and restarts, which the retake cut needs."""
import json, os, subprocess, sys, tempfile

from common import HF, die, energy_db, probe, read_wav_mono, run, silence_threshold


# Romanian ș and ț take a comma below; the cedilla forms (ş ţ) are a common legacy mix-up.
RO_COMMA = str.maketrans("şţŞŢ", "șțȘȚ")


def trim_ends(words, video, hop=0.01):
    """Parakeet's word ends can run through the pause after a word. End each word where its sound stops,
    so pauses show up in the transcript and cuts don't keep dead air."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "voice.wav")
        run(["ffmpeg", "-v", "error", "-y", "-i", video, "-vn", "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", wav])
        db = energy_db(*read_wav_mono(wav))
    thr = silence_threshold(db)
    for w in words:
        k, floor = min(len(db) - 1, int(w["end"] / hop)), int((w["start"] + 0.08) / hop)
        while k > floor and db[k] < thr:
            k -= 1
        w["end"] = round(min(w["end"], max(w["start"] + 0.08, k * hop + 0.05)), 3)
    return words


def recognize_whisper(video, model_name=None, language=None):
    """Whisper large-v3-turbo through faster-whisper: better than Parakeet on Romanian words and diacritics."""
    import numpy as np
    from faster_whisper import WhisperModel
    model = WhisperModel(model_name or os.environ.get("VIDEO_SHORT_WHISPER_MODEL", "large-v3-turbo"), device="cpu", compute_type="int8")
    # Decode with ffmpeg: faster-whisper's own PyAV decoding breaks on newer PyAV releases.
    pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", video, "-vn", "-ac", "1", "-ar", "16000", "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    segments, _ = model.transcribe(np.frombuffer(pcm, np.float32), language=language or os.environ.get("VIDEO_SHORT_LANGUAGE", "ro"),
                                   word_timestamps=True, condition_on_previous_text=False)
    words = [{"text": w.word.strip().translate(RO_COMMA), "start": round(w.start, 3), "end": round(w.end, 3)}
             for s in segments for w in (s.words or []) if w.word.strip()]
    return trim_ends(words, video), probe(video)[2]


def recognize(video):
    if os.environ.get("VIDEO_SHORT_ENGINE", "whisper") == "whisper":
        return recognize_whisper(video)
    with tempfile.TemporaryDirectory() as tmp:
        p = subprocess.run(["npx", "-y", HF, "transcribe", os.path.abspath(video), "--engine", "parakeet", "--json", "-d", tmp],
                           capture_output=True, text=True)
        if p.returncode:
            die("transcription failed. Run setup.sh, which installs the Parakeet model.\n" + (p.stdout + p.stderr)[-800:])
        words = json.load(open(json.loads(p.stdout)["transcriptPath"]))
    words = [{"text": w["text"].translate(RO_COMMA), "start": w["start"], "end": w["end"]} for w in words if w["text"].strip()]
    return trim_ends(words, video), probe(video)[2]


def phrases(words, gap=0.3):
    out, cur = [], []
    for i, w in enumerate(words):
        cur.append(w)
        nxt = words[i + 1] if i + 1 < len(words) else None
        if nxt is None or nxt["start"] - w["end"] >= gap or w["text"][-1] in ".?!":
            out.append({"start": cur[0]["start"], "end": cur[-1]["end"], "text": " ".join(x["text"] for x in cur),
                        "pause_after": round(nxt["start"] - w["end"], 2) if nxt else None})
            cur = []
    return out


def write_markdown(words, total, path, title):
    lines = [f"# {title}", "", f"Duration: {total:.2f}s. Times are seconds. Word-level times are in the matching .json file.", ""]
    if words and words[0]["start"] > 0.5:
        lines.append(f"(silence 0.00-{words[0]['start']:.2f})")
    for p in phrases(words):
        lines.append(f"[{p['start']:.2f}-{p['end']:.2f}] {p['text']}")
        if p["pause_after"] and p["pause_after"] >= 0.5:
            lines.append(f"(pause {p['pause_after']:.2f}s)")
    open(path, "w").write("\n".join(lines) + "\n")


def transcribe(video, out_prefix):
    os.makedirs(os.path.dirname(os.path.abspath(out_prefix)), exist_ok=True)
    words, total = recognize(video)
    if not words:
        sys.exit("error: no speech found")
    json.dump(words, open(out_prefix + ".json", "w"), indent=1)
    write_markdown(words, total, out_prefix + ".md", os.path.basename(out_prefix))
    return words, total


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    words, total = transcribe(sys.argv[1], sys.argv[2])
    print(f"{len(words)} words, {total:.2f}s -> {sys.argv[2]}.md and .json")


if __name__ == "__main__":
    main()
