import { Audio } from "@remotion/media";
import React from "react";
import { AbsoluteFill, CalculateMetadataFunction, interpolate, Sequence, staticFile, useCurrentFrame } from "remotion";
import { Captions3D } from "./Captions3D";
import { groupWords, KineticCaptions } from "./KineticCaptions";
import { Overlays } from "./Overlays";
import { SceneView } from "./Scenes";
import { pickSfx } from "./sfx";
import { T_LEN, TransitionWrap } from "./Transitions";
import type { ShortProps, Transition } from "./types";
import { asset, clamp, CoreDur, f, FPS, norm } from "./util";

type Hit = { at: number; src: string; vol: number; kind: string };

/** Sound design: one sound per visible move, its peak (sfx-kit sync point) on the visual peak; never stacked. */
export function autoSfx(p: ShortProps): Hit[] {
  const hits: (Hit & { moment: number })[] = [];
  const add = (moment: number, kind: string, vol: number, seed = 0) => {
    const s = pickSfx(kind, seed);
    if (!s || moment < 0 || moment >= p.duration) return;
    hits.push({ at: Math.max(0, f(moment - s.sync)), moment: f(moment), src: s.src, vol: vol * s.gain * 1.6, kind });
  };
  const trans: Partial<Record<Transition, [string, number]>> = {
    flash: ["impact", 0.5], whip: ["whip", 0.55], "whip-up": ["whoosh", 0.5], zoom: ["zoom", 0.5], dolly: ["suck", 0.5],
    spin: ["whoosh", 0.45], glitch: ["glitch", 0.55], blur: ["swish", 0.35], lightleak: ["shimmer", 0.4], cube: ["flip", 0.5],
    iris: ["swish", 0.4], swipe: ["whip", 0.45],
  };
  p.scenes.forEach((s, i) => {
    const tin: Transition = i ? s.in ?? "cut" : "cut";
    const peak = s.start + T_LEN[tin] / 2 / FPS;
    const k = trans[tin];
    if (k) add(peak, k[0], k[1], i);
    if (tin === "flash") add(peak, "whoosh", 0.35, i);
    if (s.type === "title" || s.type === "text3d" || s.type === "grid") add(s.start + T_LEN[tin] / FPS, "boom", 0.6, i);
    if (s.type === "number") add(s.start + 0.1, "pop", 0.45, i);
    if (s.type === "glass" || s.type === "pip" || s.type === "split") add(s.start + 0.12, "swish", 0.3, i);
    if (s.type === "cards") {
      const step = Math.max(8, Math.floor((f(s.end - s.start) - 10) / s.items.length)) / FPS;
      s.items.forEach((_, j) => add(s.start + j * step + 0.15, "swish", 0.3, i + j));
    }
  });
  const keys = new Set((p.keywords ?? []).map(norm));
  groupWords(p.words, p.keywords ?? []).forEach((g) => g.words.forEach((w, j) => keys.has(norm(w.text)) && add(w.start, "pop", 0.3, j)));
  (p.overlays ?? []).forEach((o, i) => {
    if (o.type === "bookmark") add(o.at, "ding", 0.35, i);
    if (o.type === "cta") { add(o.at + 0.1, "riser", 0.35, i); add(o.at + 0.15, "boom", 0.5, i); }
    if (o.type === "bigword") { add(o.at, "suck", 0.45, i); add(o.at + 0.2, "impact", 0.6, i + 1); }
    if (o.type === "lightleak") add(o.at + 0.1, "shimmer", 0.35, i);
    if (o.type === "ring" || o.type === "eyebox" || o.type === "pill" || o.type === "views") add(o.at, "pop", 0.35, i);
    if (o.type === "arrow") add(o.at, "swish", 0.3, i);
  });
  hits.sort((a, b) => a.moment - b.moment);
  // Same kind within 4 frames, or a third sound within 3 frames, would smear: drop it.
  const kept: typeof hits = [];
  for (const h of hits) {
    const near = kept.filter((k) => h.moment - k.moment < 3);
    if (near.length >= 2 || kept.some((k) => k.kind === h.kind && h.moment - k.moment < 4)) continue;
    kept.push(h);
  }
  return kept;
}

const Grain: React.FC<{ amount: number }> = ({ amount }) => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ opacity: amount, mixBlendMode: "overlay", pointerEvents: "none" }}>
      <svg width="1080" height="1920">
        <filter id="g"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed={frame % 12} /></filter>
        <rect width="100%" height="100%" filter="url(#g)" />
      </svg>
    </AbsoluteFill>
  );
};

/** One scene plus the tail it keeps playing under the next scene's entry; drives transition progress and impact shake. */
const SceneLayer: React.FC<{ i: number; p: ShortProps; ctx: React.ComponentProps<typeof SceneView>["ctx"]; core: number; tIn: Transition; tOut: Transition }> = ({ i, p, ctx, core, tIn, tOut }) => {
  const frame = useCurrentFrame();
  const s = p.scenes[i];
  const lin = T_LEN[tIn], lout = T_LEN[tOut];
  const pIn = lin ? interpolate(frame, [0, lin], [0, 1], clamp) : undefined;
  const pOut = lout ? interpolate(frame, [core, core + lout], [0, 1], clamp) : undefined;
  const hit = tIn === "flash" || tIn === "glitch" || s.type === "title" || s.type === "grid";
  const shake = hit ? interpolate(frame, [lin / 2, lin / 2 + 10], [16, 0], clamp) : 0;
  return (
    <TransitionWrap inT={tIn} outT={tOut} pIn={pIn} pOut={pOut} id={`s${i}`} frame={frame} shake={shake}>
      <CoreDur.Provider value={core}>
        <SceneView s={s} ctx={ctx} />
      </CoreDur.Provider>
    </TransitionWrap>
  );
};

export const Short: React.FC<ShortProps> = (p) => {
  const accent = p.accent ?? "#FFE600";
  const g = p.grade ?? {};
  const filter = `contrast(${g.contrast ?? 1.08}) saturate(${g.saturation ?? 1.12}) brightness(${g.brightness ?? 1})`;
  const ctx = { source: p.source, accent, words: p.words, keywords: p.keywords ?? [], filter, locale: p.locale ?? "ro-RO" };
  const sfxVol = p.sfxVolume ?? 1;
  const hits = React.useMemo(() => (p.sfx === "off" ? [] : autoSfx(p)), [p]);
  const style = p.captionStyle ?? "3d";
  const mute = (p.overlays ?? []).filter((o) => o.type === "bigword" || o.type === "cta").map((o) => [o.at - 0.05, o.at + (o.dur ?? (o.type === "cta" ? 3 : 1.1))] as [number, number]);
  const total = Math.round(p.duration * FPS);

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {p.scenes.map((s, i) => {
        const next = p.scenes[i + 1];
        const tIn: Transition = i ? s.in ?? "cut" : "cut";
        const tOut: Transition = next?.in ?? "cut";
        const from = f(s.start);
        const core = Math.max(1, f(s.end) - from);
        const tail = Math.min(T_LEN[tOut], total - from - core);
        return (
          <Sequence key={i} from={from} durationInFrames={core + Math.max(0, tail)} name={`${s.type} ${s.start}`}>
            <SceneLayer i={i} p={p} ctx={ctx} core={core} tIn={tIn} tOut={tOut} />
          </Sequence>
        );
      })}
      {g.tint && <AbsoluteFill style={{ background: `radial-gradient(circle at 70% 30%, transparent 20%, ${g.tint} 100%)`, mixBlendMode: "soft-light", opacity: g.tintAmount ?? 0.55, pointerEvents: "none" }} />}
      <AbsoluteFill style={{ background: `radial-gradient(circle at 50% 42%, transparent 55%, rgba(0,0,0,${g.vignette ?? 0.45}) 100%)`, pointerEvents: "none" }} />
      <Grain amount={g.grain ?? 0.07} />
      {style === "stack"
        ? <KineticCaptions words={p.words} scenes={p.scenes} keywords={p.keywords ?? []} accent={accent} />
        : <Captions3D words={p.words} scenes={p.scenes} keywords={p.keywords ?? []} accent={accent} style={style} mute={mute} />}
      <Overlays overlays={p.overlays ?? []} accent={accent} />

      <Audio src={asset(p.source)} />
      {p.music && <Audio src={asset(p.music.src)} volume={p.music.volume ?? 0.12} loop />}
      {hits.map((h, i) => (
        <Sequence key={`sfx${i}`} from={h.at} layout="none">
          <Audio src={staticFile(`sfx/${h.src}`)} volume={h.vol * sfxVol} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

export const calcShort: CalculateMetadataFunction<ShortProps> = ({ props }) => ({ durationInFrames: Math.max(1, Math.round(props.duration * FPS)) });
