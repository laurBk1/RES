// Render a project's short.json with the Remotion "Short" composition.
// usage: node scripts/render-short.mjs PROJECT_DIR [--draft] [--frames=0-90] [--still=SECONDS]
// Reads PROJECT/short.json; words default to PROJECT/work/transcript_clean.json and duration to the source length.
// Writes PROJECT/renders/<slug>-vN.mp4 leveled to -14 LUFS, plus a 720p copy in renders/share/.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const here = path.dirname(new URL(import.meta.url).pathname);
const root = path.resolve(here, "..");
const args = process.argv.slice(2);
const project = path.resolve(args.find((a) => !a.startsWith("--")) ?? ".");
const flag = (name) => args.find((a) => a.startsWith(`--${name}`))?.split("=")[1] ?? (args.includes(`--${name}`) ? true : undefined);
const die = (m) => { console.error(`error: ${m}`); process.exit(1); };

const specPath = path.join(project, "short.json");
if (!fs.existsSync(specPath)) die(`${specPath} not found`);
const spec = JSON.parse(fs.readFileSync(specPath, "utf8"));
spec.source ??= "work/clean.mp4";
if (!fs.existsSync(path.join(project, spec.source))) die(`source ${spec.source} not found in ${project}; run cut.py first`);

if (!spec.words) {
  const wp = path.join(project, "work", "transcript_clean.json");
  if (!fs.existsSync(wp)) die("no words in short.json and no work/transcript_clean.json");
  spec.words = JSON.parse(fs.readFileSync(wp, "utf8"));
}
// "fixes": [["Astă", "Astăzi vă"], ...] replaces words, matching whole words without case or trailing punctuation.
const clean = (t) => t.toLowerCase().replace(/[.,!?;:"„”]+$/g, "");
for (const [wrong, right] of spec.fixes ?? []) {
  const target = wrong.split(/\s+/).map(clean);
  for (let i = 0; i + target.length <= spec.words.length; i++) {
    const seg = spec.words.slice(i, i + target.length);
    if (seg.every((w, k) => clean(w.text) === target[k])) {
      const tail = seg[seg.length - 1].text.match(/[.,!?;:]*$/)[0];
      spec.words.splice(i, target.length, { text: right + tail, start: seg[0].start, end: seg[seg.length - 1].end });
    }
  }
}
delete spec.fixes;
const probe = (file) => parseFloat(execFileSync("ffprobe", ["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", file]).toString());
spec.duration ??= probe(path.join(project, spec.source));

// Validate scene coverage so mistakes fail here with a clear message, not as a blank frame.
const sc = spec.scenes ?? die("short.json needs scenes");
if (Math.abs(sc[0].start) > 0.01) die("first scene must start at 0");
sc.forEach((s, i) => {
  if (!(s.end > s.start)) die(`scene ${i} (${s.type}) ends before it starts`);
  if (i && Math.abs(sc[i - 1].end - s.start) > 0.05) die(`scene ${i} starts at ${s.start} but scene ${i - 1} ends at ${sc[i - 1].end}`);
  for (const src of [s.src, s.bg, ...(s.items ?? []).map((it) => it.src)]) {
    if (src && /[./]/.test(src) && !/^https?:/.test(src) && !fs.existsSync(path.join(project, src))) die(`scene ${i}: ${src} not found in project`);
  }
});
if (Math.abs(sc[sc.length - 1].end - spec.duration) > 0.1) console.warn(`warning: scenes end at ${sc[sc.length - 1].end}s but the source is ${spec.duration.toFixed(2)}s`);

// A per-project public dir: shared sfx and fonts, plus the project itself under p/.
const pub = fs.mkdtempSync(path.join(os.tmpdir(), "short-public-"));
fs.symlinkSync(path.join(root, "public", "sfx"), path.join(pub, "sfx"));
fs.symlinkSync(path.join(root, "public", "fonts"), path.join(pub, "fonts"));
fs.symlinkSync(project, path.join(pub, "p"));
const propsFile = path.join(pub, "..", `${path.basename(pub)}.json`);
fs.writeFileSync(propsFile, JSON.stringify(spec));

const slug = path.basename(project);
const renders = path.join(project, "renders");
fs.mkdirSync(path.join(renders, "share"), { recursive: true });
const npx = (a) => execFileSync("npx", ["remotion", ...a], { cwd: root, stdio: ["ignore", "inherit", "inherit"] });
const common = ["--props", propsFile, "--public-dir", pub, "--log=error", ...(sc.some((s) => s.type === "text3d") ? ["--gl=swangle"] : [])];

const still = flag("still");
if (still) {
  const out = path.join(project, "work", `still-${still}.png`);
  npx(["still", "src/index.ts", "Short", out, `--frame=${Math.round(parseFloat(still) * 30)}`, ...common]);
  console.log(`Still -> ${out}`);
  process.exit(0);
}

const n = 1 + Math.max(0, ...fs.readdirSync(renders).map((f) => +(f.match(new RegExp(`^${slug}-v(\\d+)\\.mp4$`))?.[1] ?? 0)));
const raw = path.join(pub, "..", `${path.basename(pub)}.mp4`);
const frames = flag("frames");
npx(["render", "src/index.ts", "Short", raw, ...common, ...(flag("draft") ? ["--crf=26", "--x264-preset=veryfast"] : ["--crf=17"]), ...(frames ? [`--frames=${frames}`] : [])]);

const out = path.join(renders, `${slug}-v${n}.mp4`);
// loudnorm pads the tail; trim audio to the video so players don't show a frozen last frame.
const vdur = execFileSync("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=duration", "-of", "csv=p=0", raw]).toString().trim();
execFileSync("ffmpeg", ["-v", "error", "-y", "-i", raw, "-t", vdur, "-c:v", "copy", "-af", "loudnorm=I=-14:TP=-1.5:LRA=11", "-ar", "48000", "-c:a", "aac", "-b:a", "256k", "-movflags", "+faststart", out]);
execFileSync("ffmpeg", ["-v", "error", "-y", "-i", out, "-vf", "scale=720:-2", "-c:v", "libx264", "-crf", "26", "-preset", "veryfast", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", path.join(renders, "share", `${slug}-v${n}.mp4`)]);
fs.rmSync(raw, { force: true });
fs.rmSync(propsFile, { force: true });
fs.rmSync(pub, { recursive: true, force: true });
console.log(`Rendered ${out} (${probe(out).toFixed(2)}s), share copy in renders/share/`);
