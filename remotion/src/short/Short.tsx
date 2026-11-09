import { Audio } from "@remotion/media";
import React from "react";
import { AbsoluteFill, CalculateMetadataFunction, Sequence, staticFile, useCurrentFrame } from "remotion";
import { groupWords, KineticCaptions } from "./KineticCaptions";
import { Overlays } from "./Overlays";
import { SceneView } from "./Scenes";
import { Flash, TransitionWrap } from "./Transitions";
import type { ShortProps } from "./types";
import { asset, f, FPS, norm } from "./util";

type Hit = { at: number; src: string; vol: number };

/** Sound design from the references: whoosh on moves, impact on titles, pop on keywords and cards, ding on save, riser into the CTA. */
export function autoSfx(p: ShortProps): Hit[] {
  const hits: Hit[] = [];
  const add = (t: number, src: string, vol: number) => t >= 0 && t < p.duration && hits.push({ at: f(t), src, vol });
  p.scenes.forEach((s, i) => {
    if (i > 0) {
      if (s.in === "flash") { add(s.start - 0.28, "whoosh.wav", 0.55); add(s.start, "impact.wav", 0.3); }
      if (s.in === "whip") add(s.start - 0.12, "whip.wav", 0.5);
      if (s.in === "zoom") add(s.start - 0.2, "whoosh.wav", 0.45);
      if (s.in === "glitch") { add(s.start, "switch.wav", 0.5); add(s.start + 0.07, "tick.wav", 0.4); }
      if (s.in === "blur") add(s.start - 0.1, "swish.wav", 0.35);
    }
    if (s.type === "title" || s.type === "text3d") add(s.start + 0.03, "impact.wav", 0.55);
    if (s.type === "number") add(s.start + 0.1, "pop.wav", 0.4);
    if (s.type === "cards") {
      const step = Math.max(8, Math.floor((f(s.end - s.start) - 10) / s.items.length)) / FPS;
      s.items.forEach((_, k) => add(s.start + k * step, "swish.wav", 0.35));
    }
  });
  const keys = new Set((p.keywords ?? []).map(norm));
  groupWords(p.words, p.keywords ?? []).forEach((g) => g.words.forEach((w) => keys.has(norm(w.text)) && add(w.start - 0.02, "pop.wav", 0.28)));
  (p.overlays ?? []).forEach((o) => {
    if (o.type === "bookmark") add(o.at, "ding.wav", 0.3);
    if (o.type === "cta") { add(o.at - 1.15, "riser.wav", 0.3); add(o.at + 0.13, "impact.wav", 0.4); }
    if (o.type === "ring" || o.type === "eyebox" || o.type === "pill" || o.type === "views") add(o.at, "pop.wav", 0.3);
    if (o.type === "arrow") add(o.at, "swish.wav", 0.3);
  });
  // Keep one sound per 3-frame window so stacked triggers don't clip.
  hits.sort((a, b) => a.at - b.at);
  return hits.filter((h, i) => !hits.slice(0, i).some((g) => Math.abs(g.at - h.at) < 3 && g.src === h.src));
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

export const Short: React.FC<ShortProps> = (p) => {
  const accent = p.accent ?? "#FFE600";
  const g = p.grade ?? {};
  const filter = `contrast(${g.contrast ?? 1.08}) saturate(${g.saturation ?? 1.12}) brightness(${g.brightness ?? 1})`;
  const ctx = { source: p.source, accent, words: p.words, keywords: p.keywords ?? [], filter, locale: p.locale ?? "ro-RO" };
  const sfxVol = p.sfxVolume ?? 1;
  const hits = React.useMemo(() => (p.sfx === "off" ? [] : autoSfx(p)), [p]);

  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {p.scenes.map((s, i) => {
        const next = p.scenes[i + 1];
        const from = f(s.start);
        return (
          <Sequence key={i} from={from} durationInFrames={Math.max(1, f(s.end) - from)} name={`${s.type} ${s.start}`}>
            <TransitionWrap inT={i ? s.in ?? "cut" : "cut"} outT={next?.in ?? "cut"} id={`s${i}`}>
              <SceneView s={s} ctx={ctx} />
            </TransitionWrap>
          </Sequence>
        );
      })}
      <AbsoluteFill style={{ background: `radial-gradient(circle at 50% 42%, transparent 55%, rgba(0,0,0,${g.vignette ?? 0.45}) 100%)`, pointerEvents: "none" }} />
      <Grain amount={g.grain ?? 0.07} />
      <KineticCaptions words={p.words} scenes={p.scenes} keywords={p.keywords ?? []} accent={accent} />
      <Overlays overlays={p.overlays ?? []} accent={accent} />
      {p.scenes.map((s, i) => (i > 0 && s.in === "flash" ? <Flash key={`fl${i}`} at={f(s.start)} color={s.flashColor ?? "#ffffff"} /> : null))}

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
