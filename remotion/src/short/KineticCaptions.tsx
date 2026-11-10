import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { BODY_FONT, KEY_FONT } from "./fonts";
import type { CaptionPos, Scene, Word } from "./types";
import { clamp, darkShadow, easeOut, f, glow, norm } from "./util";

type Group = { words: (Word & { key: boolean })[]; start: number; end: number };

const isKey = (w: string, keys: Set<string>) => keys.has(norm(w)) || /\d/.test(w);

/** Split words into 1-3 word lines at punctuation, pauses, and length; long keywords get a line of their own. */
export function groupWords(words: Word[], keywords: string[]): Group[] {
  const keys = new Set(keywords.flatMap((k) => k.split(/\s+/)).map(norm));
  const out: Group[] = [];
  let cur: Group["words"] = [];
  words.forEach((w, i) => {
    const key = isKey(w.text, keys);
    if (key && cur.length && cur.some((c) => !c.key) && w.text.length > 7) {
      out.push({ words: cur, start: cur[0].start, end: cur[cur.length - 1].end });
      cur = [];
    }
    cur.push({ ...w, key });
    const next = words[i + 1];
    const chars = cur.reduce((n, c) => n + c.text.length + 1, 0);
    const brk = !next || cur.length >= 3 || /[.,!?;:]$/.test(w.text) || next.start - w.end > 0.35 || chars + next.text.length > 20;
    if (brk) {
      out.push({ words: cur, start: cur[0].start, end: cur[cur.length - 1].end });
      cur = [];
    }
  });
  return out;
}

/** Stack lines into blocks of up to 3, cleared at pauses and at scene changes. */
function blocks(groups: Group[], scenes: Scene[]) {
  const cuts = scenes.map((s) => s.start);
  const out: Group[][] = [];
  let cur: Group[] = [];
  groups.forEach((g, i) => {
    const prev = groups[i - 1];
    const crossesScene = prev && cuts.some((c) => c > prev.start + 0.01 && c <= g.start + 0.01);
    if (cur.length && (cur.length >= 3 || g.start - cur[cur.length - 1].end > 0.6 || crossesScene)) {
      out.push(cur);
      cur = [];
    }
    cur.push(g);
  });
  if (cur.length) out.push(cur);
  return out;
}

const sceneAt = (scenes: Scene[], t: number) => scenes.find((s) => t >= s.start && t < s.end) ?? scenes[scenes.length - 1];
const posOf = (s: Scene): CaptionPos => s.captions ?? (s.type === "speaker" ? "right" : s.type === "title" || s.type === "text3d" || s.type === "number" ? "none" : "lower");

const AnimatedWord: React.FC<{ w: Group["words"][number]; frame: number; accent: string; size: number; stacked: boolean }> = ({ w, frame, accent, size, stacked }) => {
  const at = f(w.start) - 2;
  const p = interpolate(frame, [at, at + 6], [0, 1], { ...clamp, easing: easeOut });
  if (frame < at) return null;
  const key = w.key;
  const text = w.text.replace(/[.,;:]$/, "");
  return (
    <span
      style={{
        display: "inline-block",
        fontFamily: key ? KEY_FONT : BODY_FONT,
        fontWeight: key ? 400 : 800,
        fontSize: key ? size * (stacked ? 1.75 : 1.3) : size,
        lineHeight: key ? 0.95 : 1.05,
        textTransform: key ? "uppercase" : "none",
        letterSpacing: key ? 1 : -1,
        color: key ? accent : "#fff",
        textShadow: key ? glow(accent) : darkShadow,
        opacity: Math.min(1, p * 2),
        filter: `blur(${(1 - p) * 12}px)`,
        transform: `translateY(${(1 - p) * 26}px) scale(${0.78 + 0.22 * p})`,
        margin: `0 ${size * 0.13}px`,
      }}
    >
      {text}
    </span>
  );
};

/** Kinetic captions: words pop in blurred-to-sharp as they are spoken, lines stack beside the speaker, keywords glow. */
export const KineticCaptions: React.FC<{ words: Word[]; scenes: Scene[]; keywords: string[]; accent: string }> = ({ words, scenes, keywords, accent }) => {
  const frame = useCurrentFrame();
  const t = frame / 30;
  const all = React.useMemo(() => blocks(groupWords(words, keywords), scenes), [words, scenes, keywords]);
  const idx = all.findIndex((b, i) => {
    const next = all[i + 1];
    return t >= b[0].start - 0.1 && (!next || t < next[0].start - 0.1);
  });
  if (idx < 0) return null;
  const block = all[idx];
  const scene = sceneAt(scenes, block[0].start);
  const pos = posOf(scene);
  if (pos === "none") return null;
  const lastEnd = block[block.length - 1].end;
  const next = all[idx + 1];
  const outAt = Math.min(f(lastEnd + 1.2), next ? f(next[0].start) - 3 : Infinity, f(scene.end) - 1);
  const out = interpolate(frame, [outAt, outAt + 4], [0, 1], clamp);
  if (out >= 1) return null;

  const stacked = pos !== "lower" && pos !== "upper";
  // Lower captions show only the current line, like subtitles; stacked ones keep the block.
  const lines = stacked ? block : [block.filter((g) => t >= g.start - 0.1).pop() ?? block[0]];
  const size = stacked ? 84 : pos === "upper" ? 86 : 70;
  const box: React.CSSProperties =
    pos === "left" ? { left: 56, right: 360, top: 900, alignItems: "flex-start", textAlign: "left" }
    : pos === "right" ? { left: 360, right: 56, top: 900, alignItems: "flex-end", textAlign: "right" }
    : pos === "center" ? { left: 70, right: 70, top: 1080, alignItems: "center", textAlign: "center" }
    : pos === "upper" ? { left: 70, right: 70, top: 130, alignItems: "center", textAlign: "center" }
    : { left: 60, right: 60, top: 1500, alignItems: "center", textAlign: "center" };

  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      <div
        style={{
          position: "absolute", ...box, display: "flex", flexDirection: "column", gap: 4,
          opacity: 1 - out, filter: `blur(${out * 10}px)`, transform: `scale(${1 - out * 0.08})`,
        }}
      >
        {lines.map((g, i) => (
          <div key={g.start} style={{ display: "flex", flexWrap: "wrap", alignItems: "baseline", justifyContent: box.alignItems as string,
            transform: stacked ? `translateX(${(i % 2 ? 1 : -1) * 18}px)` : undefined }}>
            {g.words.map((w) => <AnimatedWord key={w.start} w={w} frame={frame} accent={accent} size={size} stacked={stacked} />)}
          </div>
        ))}
      </div>
    </AbsoluteFill>
  );
};
