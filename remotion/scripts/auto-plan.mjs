// Write a first-pass short.json automatically from the clean transcript, so a raw talking head becomes an edit
// with no hand planning. The agent (or you) then tweaks short.json and renders.
// usage: node scripts/auto-plan.mjs PROJECT [--force]
// Optional PROJECT/auto.json: { "accent": "#FFD60A", "focus": [0.5, 0.3], "fade": 0.54, "cta": "visionedit.ro",
//   "captionStyle": "3d", "tight": 1.9, "energy": "high" }
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const project = path.resolve(process.argv[2] ?? ".");
const force = process.argv.includes("--force");
const out = path.join(project, "short.json");
if (fs.existsSync(out) && !force) { console.error(`${out} exists; pass --force to overwrite`); process.exit(1); }

const opt = fs.existsSync(path.join(project, "auto.json")) ? JSON.parse(fs.readFileSync(path.join(project, "auto.json"), "utf8")) : {};
const words = JSON.parse(fs.readFileSync(path.join(project, "work", "transcript_clean.json"), "utf8"));
// Apply caption fixes first so keywords and the CTA come from the corrected words (render-short applies them again, harmlessly).
const strip = (t) => t.toLowerCase().replace(/[.,!?;:"„”]+$/g, "");
for (const [wrong, right] of opt.fixes ?? []) {
  const target = wrong.split(/\s+/).map(strip);
  for (let i = 0; i + target.length <= words.length; i++) {
    const seg = words.slice(i, i + target.length);
    if (seg.every((w, k) => strip(w.text) === target[k])) {
      const tail = seg.at(-1).text.match(/[.,!?;:]*$/)[0];
      words.splice(i, target.length, { text: right + tail, start: seg[0].start, end: seg.at(-1).end });
    }
  }
}
const source = "work/clean.mp4";
const probe = (args) => execFileSync("ffprobe", ["-v", "error", ...args, path.join(project, source)]).toString().trim();
const duration = parseFloat(probe(["-show_entries", "format=duration", "-of", "csv=p=0"]));
const [vw, vh] = probe(["-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0"]).split(",").map(Number);

// Framing from edit.md (face center) unless auto.json says otherwise.
const editMd = fs.existsSync(path.join(project, "edit.md")) ? fs.readFileSync(path.join(project, "edit.md"), "utf8") : "";
const fm = editMd.match(/^Framing:\s*([\d.]+)\s*,\s*([\d.]+)/m);
const focus = opt.focus ?? (fm ? [parseFloat(fm[1]), parseFloat(fm[2])] : [0.5, 0.35]);

// A tighter close-up of the same take, so wide and tight alternate like a two-camera shoot.
const zoom = opt.tight ?? 1.8;
const tight = "work/tight.mp4";
if (!fs.existsSync(path.join(project, tight)) || force) {
  const cw = Math.round(vw / zoom / 2) * 2, ch = Math.round((cw * 16) / 9 / 2) * 2;
  const maxY = opt.fade ? Math.max(0, opt.fade * vh - ch) : vh - ch; // keep the crop above burned-in text
  const cx = Math.min(vw - cw, Math.max(0, Math.round(focus[0] * vw - cw / 2)));
  const cy = Math.min(maxY, Math.max(0, Math.round(focus[1] * vh - ch * 0.4)));
  execFileSync("ffmpeg", ["-v", "error", "-y", "-i", path.join(project, source), "-vf", `crop=${cw}:${ch}:${cx}:${cy},scale=1080:1920:flags=lanczos,unsharp=5:5:0.6`,
    "-an", "-c:v", "libx264", "-crf", "15", "-preset", "medium", "-pix_fmt", "yuv420p", path.join(project, tight)]);
}

const STOP = new Set("și sau dar că ca la în pe cu de din pentru este sunt era erau fi am ai a au un o unui unei care ce cum mai foarte doar tot toate acest această asta ăsta lor lui ei el ea noi voi eu tu se nu da să vă ne te mă îți îmi îl le li fac face făcut fost avea are acum când unde dacă decât dintre spre după până the and to of a".split(" "));
const clean = (t) => t.toLowerCase().normalize("NFC").replace(/[^\p{L}\p{N}%$.]+/gu, "").replace(/\.$/, "");

// Sentences: end punctuation or a pause > 0.45 s.
const sentences = [];
let cur = [];
words.forEach((w, i) => {
  cur.push(w);
  const nx = words[i + 1];
  if (!nx || /[.?!]$/.test(w.text) || nx.start - w.end > 0.45) { sentences.push(cur); cur = []; }
});

const pickKey = (ws) => {
  const num = ws.find((w) => /\d/.test(w.text));
  if (num) return num;
  return [...ws].filter((w) => !STOP.has(clean(w.text)) && clean(w.text).length >= 5).sort((a, b) => clean(b.text).length - clean(a.text).length)[0];
};
const keyWords = sentences.map(pickKey);
const keywords = [...new Set(keyWords.filter(Boolean).map((w) => w.text.replace(/[.,!?;:]+$/, "")))];

const ctaRe = /(intră|intra|comentează|comenteaza|urmărește|abonează|link|scrie|\.ro\b|\.com\b|bio)/i;
const ctaIdx = sentences.length > 2 && ctaRe.test(sentences.at(-1).map((w) => w.text).join(" ")) ? sentences.length - 1 : -1;

// One primary transition for most cuts plus accents (herk/transitions.md: 60-70 % primary).
const primary = opt.energy === "calm" ? ["blur", "zoom"] : ["zoom", "whip", "zoom", "whip-up"];
const accents = ["flash", "glitch", "lightleak", "cube", "swipe", "spin"];
let pi = 0, ai = 0;
const nextT = (accent) => (accent ? accents[ai++ % accents.length] : primary[pi++ % primary.length]);

const scenes = [];
const overlays = [];
let wide = true;
const speaker = (start, end, inT, extra = {}) => {
  const s = wide
    ? { type: "speaker", start, end, in: inT, focus, zoom: 1.0, ...(opt.fade !== undefined ? { fade: opt.fade } : {}), captions: "lower", ...extra }
    : { type: "speaker", start, end, in: inT, src: tight, focus: [0.5, 0.42], zoom: 1.04, captions: opt.fade !== undefined ? "upper" : "lower", ...extra };
  wide = !wide;
  scenes.push(s);
};

const r2 = (x) => Math.round(x * 100) / 100;
let t = 0;
sentences.forEach((ws, si) => {
  const sEnd = si === sentences.length - 1 ? duration : r2((ws.at(-1).end + sentences[si + 1][0].start) / 2);
  const key = keyWords[si];
  const isCta = si === ctaIdx;
  const section = si > 0 && si % 3 === 0 && !isCta;
  // Graphic beat: a 0.7 s chrome title on the keyword at section starts (not on the hook or CTA).
  if (section && key && sEnd - t > 2.2) {
    const gEnd = r2(Math.min(sEnd - 1, t + 0.75));
    scenes.push({ type: "grid", start: r2(t), end: gEnd, in: "flash", text: key.text.replace(/[.,!?;:]+$/, "") });
    t = gEnd;
    speaker(t, 0, nextT(false));
  } else {
    speaker(r2(t), 0, si === 0 ? "cut" : nextT(si % 4 === 2 || isCta));
  }
  // Long sentences get a second angle at a word boundary near the middle.
  const lastStart = scenes.at(-1).start;
  if (sEnd - lastStart > 2.8 && ws.length > 4) {
    const mid = ws.reduce((b, w) => (Math.abs(w.start - (lastStart + sEnd) / 2) < Math.abs(b.start - (lastStart + sEnd) / 2) ? w : b), ws[1]);
    if (mid.start - lastStart > 1 && sEnd - mid.start > 1) {
      scenes.at(-1).end = r2(mid.start - 0.04);
      speaker(r2(mid.start - 0.04), 0, nextT(false));
    }
  }
  scenes.at(-1).end = r2(sEnd);
  t = sEnd;
  // A giant 3D word on every other sentence's keyword (not the first, not the CTA, not where a grid title just played).
  // No giant word right before a grid title (the next sentence opens a section) or on top of one.
  const nearGrid = (si + 1) % 3 === 0;
  if (key && si % 2 === 1 && !section && !isCta && !nearGrid && key.end - key.start < 1.2) overlays.push({ type: "bigword", at: r2(key.start - 0.05), dur: 0.9, text: key.text.replace(/[.,!?;:]+$/, "") });
  if (si === 1) overlays.push({ type: "lightleak", at: r2(ws[0].start), dur: 0.8 });
  if (isCta) {
    const dom = ws.map((w) => w.text).join("").match(/[a-z0-9-]+\.(ro|com|net|io)/i)?.[0];
    const at = r2(ws[0].start + 0.05);
    overlays.push({ type: "cta", at, dur: r2(duration - at), text: dom ? "Intră pe" : "Comentează", keyword: opt.cta ?? dom ?? key?.text ?? "INFO", quote: !dom && !opt.cta });
    scenes.at(-1).captions = "none";
  }
});
// Fix any zero-length scene from merging and make sure scenes tile 0..duration.
const tiled = scenes.filter((s) => s.end - s.start > 0.2);
tiled.forEach((s, i) => { if (i) s.start = tiled[i - 1].end; });
tiled[0].start = 0;
tiled.at(-1).end = r2(duration);

const plan = { source, accent: opt.accent ?? "#FFD60A", captionStyle: opt.captionStyle ?? "3d", ...(opt.fixes ? { fixes: opt.fixes } : {}), keywords, scenes: tiled, overlays,
  sfxVolume: 0.9, grade: { contrast: 1.1, saturation: 1.08, vignette: 0.5, grain: 0.07, tint: "#0f5f6b", tintAmount: 0.4 } };
fs.writeFileSync(out, JSON.stringify(plan, null, 2) + "\n");
console.log(`short.json: ${tiled.length} scenes, ${overlays.length} overlays, ${keywords.length} keywords (${sentences.length} sentences, ${duration.toFixed(2)}s)`);
