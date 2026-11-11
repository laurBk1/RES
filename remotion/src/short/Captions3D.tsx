import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame } from "remotion";
import { CAP_FONT } from "./fonts";
import { groupWords } from "./KineticCaptions";
import type { CaptionPos, Scene, Word } from "./types";
import { clamp, f, FPS, glow, norm } from "./util";

/** Layered offsets read as a solid extruded slab; the last soft shadow lifts it off the footage. */
const extrude = (shade: string, depth: number) =>
  [...Array(depth)].map((_, k) => `0 ${k + 1}px 0 ${shade}`).concat([`0 ${depth + 6}px 22px rgba(0,0,0,.6)`]).join(", ");

const darken = (hex: string, k: number) => {
  const n = parseInt(hex.replace("#", "").slice(0, 6), 16);
  const c = (s: number) => Math.max(0, Math.round(((n >> s) & 255) * k)).toString(16).padStart(2, "0");
  return `#${c(16)}${c(8)}${c(0)}`;
};

const sceneAt = (scenes: Scene[], t: number) => scenes.find((s) => t >= s.start && t < s.end) ?? scenes[scenes.length - 1];
const defaultPos = (s: Scene): CaptionPos =>
  s.captions ?? (["title", "text3d", "number", "grid", "glass"].includes(s.type) ? "none" : s.type === "split" ? "center" : "lower");

const Y: Record<string, number> = { upper: 300, center: 960, left: 1240, right: 1240, lower: 1300, bottom: 1735 };

/**
 * One line of 1-3 words at a time. "3d": each word flips up out of depth as it is spoken (rotateX -80° -> 0,
 * z -260 -> 0, blur 10 -> 0) on a spring, with an extruded body; the spoken word turns accent, lifts and glows,
 * and the whole line drifts in 3D so it never sits still. "box": the spoken word rides an accent pill.
 */
export const Captions3D: React.FC<{ words: Word[]; scenes: Scene[]; keywords: string[]; accent: string; style: "3d" | "box"; mute: [number, number][] }> = ({ words, scenes, keywords, accent, style, mute }) => {
  const frame = useCurrentFrame();
  const t = frame / FPS;
  const groups = React.useMemo(() => groupWords(words, keywords), [words, keywords]);
  if (mute.some(([a, b]) => t >= a && t < b)) return null;
  const gi = groups.findIndex((g, i) => t >= g.start - 0.08 && (i === groups.length - 1 || t < groups[i + 1].start - 0.08));
  if (gi < 0) return null;
  const g = groups[gi];
  const scene = sceneAt(scenes, g.start);
  const pos = defaultPos(scene);
  if (pos === "none") return null;
  const next = groups[gi + 1];
  const endAt = Math.min(f(g.end + 0.5), next ? f(next.start) - 2 : Infinity);
  const out = interpolate(frame, [endAt - 4, endAt], [0, 1], clamp);
  if (out >= 1) return null;

  const keys = new Set(keywords.map(norm));
  const drift = Math.sin(frame / 22) * 5;
  const n = g.words.reduce((a, w) => a + w.text.length, 0);
  // Montserrat Black caps run ~0.72em per glyph; size the line to fit 1000 px.
  const size = Math.min(style === "box" ? 120 : 150, 1000 / (0.74 * n + 0.3 * (g.words.length - 1) + 0.5));

  return (
    <AbsoluteFill style={{ pointerEvents: "none", perspective: 1100 }}>
      <div style={{ position: "absolute", left: 40, right: 40, top: Y[pos] ?? 1300, display: "flex", flexWrap: "wrap", justifyContent: "center", alignItems: "center",
        columnGap: size * 0.28, rowGap: 6, transformStyle: "preserve-3d",
        transform: `translateY(-50%) rotateX(${style === "3d" ? 10 : 0}deg) rotateY(${style === "3d" ? drift : 0}deg) translateZ(${-out * 300}px)`,
        opacity: 1 - out, filter: out ? `blur(${out * 12}px)` : undefined }}>
        {g.words.map((w, k) => {
          const at = f(w.start) - 2;
          if (frame < at) return <span key={k} style={{ visibility: "hidden", fontFamily: CAP_FONT, fontWeight: 900, fontSize: size }}>{w.text}</span>;
          const sp = spring({ frame: frame - at, fps: FPS, config: { damping: 13, stiffness: 190, mass: 0.7 } });
          const active = t >= w.start - 0.03 && t < (g.words[k + 1]?.start ?? g.end + 0.2);
          const key = keys.has(norm(w.text)) || /\d/.test(w.text);
          const lift = active ? 1 : 0;
          const text = w.text.replace(/[.,;:]$/, "").toUpperCase();
          if (style === "box") {
            return (
              <span key={k} style={{ position: "relative", display: "inline-block", fontFamily: CAP_FONT, fontWeight: 900, fontSize: size, lineHeight: 1.15,
                color: active ? "#111" : "#fff", WebkitTextStroke: active ? undefined : "7px #000", paintOrder: "stroke fill",
                transform: `scale(${(0.6 + 0.4 * sp) * (active ? 1.08 : 1)}) rotate(${active ? -2 : 0}deg)`, padding: "0 14px" }}>
                <span style={{ position: "absolute", inset: "6% 0", borderRadius: 18, background: key ? accent : "#fff", zIndex: -1,
                  transform: `scale(${active ? spring({ frame: frame - at, fps: FPS, config: { damping: 12, stiffness: 260 } }) : 0})`, boxShadow: `0 10px 30px rgba(0,0,0,.45)` }} />
                {text}
              </span>
            );
          }
          const color = active ? accent : key ? accent : "#fff";
          const shade = active || key ? darken(accent, 0.45) : "#4a4f57";
          return (
            <span key={k} style={{ display: "inline-block", fontFamily: CAP_FONT, fontWeight: 900, fontSize: size, lineHeight: 1.05, letterSpacing: -1, color,
              textShadow: `${extrude(shade, 7)}${active || key ? `, ${glow(accent, 0.8)}` : ""}`,
              transformOrigin: "50% 100%",
              transform: `translateZ(${(1 - sp) * -260 + lift * 40}px) rotateX(${(1 - sp) * -80}deg) translateY(${(1 - sp) * 30 - lift * 8}px) scale(${1 + lift * 0.1})`,
              opacity: interpolate(sp, [0, 0.3], [0, 1], clamp), filter: sp < 0.9 ? `blur(${(1 - sp) * 10}px)` : undefined }}>
              {text}
            </span>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
