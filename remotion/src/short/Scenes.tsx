import { evolvePath } from "@remotion/paths";
import React from "react";
import { AbsoluteFill, Img, interpolate, OffthreadVideo, useCurrentFrame, useVideoConfig } from "remotion";
import { BODY_FONT, KEY_FONT, SCRIPT_FONT } from "./fonts";
import { Text3DTitle } from "../Text3DTitle";
import type { BrollScene, CardsScene, NumberScene, PhoneScene, Scene, SpeakerScene, TitleScene, Word } from "./types";
import { asset, clamp, darkShadow, easeOut, f, glow, isVideo, norm, pop } from "./util";

type Ctx = { source: string; accent: string; words: Word[]; keywords: string[]; filter: string; locale: string };

/** A clip or still that fills its box; videos start `from` seconds in (default: the scene's own time on the source). */
export const Media: React.FC<{ src: string; from: number; style?: React.CSSProperties; filter?: string; position?: string }> = ({ src, from, style, filter, position }) => {
  const common: React.CSSProperties = { width: "100%", height: "100%", objectFit: "cover", objectPosition: position ?? "50% 40%", filter, ...style };
  return isVideo(src) ? <OffthreadVideo src={asset(src)} trimBefore={f(from)} muted style={common} /> : <Img src={asset(src)} style={common} />;
};

/** Blurred, darkened speaker behind graphic scenes, so the frame never goes empty. */
const SpeakerBackdrop: React.FC<{ ctx: Ctx; start: number; dim?: number }> = ({ ctx, start, dim = 0.35 }) => (
  <AbsoluteFill style={{ transform: "scale(1.15)" }}>
    <Media src={ctx.source} from={start} filter={`blur(28px) brightness(${dim}) saturate(1.2)`} />
  </AbsoluteFill>
);

const Paper: React.FC = () => (
  <AbsoluteFill style={{ background: "radial-gradient(circle at 30% 25%, #e9d7b0 0%, #c9a978 45%, #8a6a43 100%)" }}>
    <AbsoluteFill style={{ background: "repeating-linear-gradient(115deg, rgba(90,60,30,.06) 0 2px, transparent 2px 9px)", mixBlendMode: "multiply" }} />
    <AbsoluteFill style={{ background: "radial-gradient(circle, transparent 50%, rgba(40,25,10,.55) 100%)" }} />
  </AbsoluteFill>
);

const Backdrop: React.FC<{ bg?: string; ctx: Ctx; start: number }> = ({ bg, ctx, start }) => {
  if (!bg || bg === "speaker") return <SpeakerBackdrop ctx={ctx} start={start} />;
  if (bg === "paper") return <Paper />;
  if (bg === "light") return <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 35%, #ffffff, #e4e6ea)" }} />;
  if (bg === "dark") return <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 35%, #2a2a31, #0b0b0d)" }} />;
  return (
    <AbsoluteFill style={{ transform: "scale(1.1)" }}>
      <Media src={bg} from={0} filter="blur(18px) brightness(.55)" />
    </AbsoluteFill>
  );
};

export const Speaker: React.FC<{ s: SpeakerScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const [fx, fy] = s.focus ?? [0.5, 0.38];
  const keys = new Set(ctx.keywords.map(norm));
  // A 5% scale kick that settles over 8 frames on every keyword the speaker hits.
  const kick = ctx.words
    .filter((w) => w.start >= s.start && w.start < s.end && keys.has(norm(w.text)))
    .reduce((k, w) => Math.max(k, interpolate(frame, [f(w.start - s.start), f(w.start - s.start) + 8], [0.05, 0], clamp)), 0);
  const push = interpolate(frame, [0, durationInFrames], [1, 1.05]);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ transform: `scale(${(s.zoom ?? 1) * push * (1 + kick)})`, transformOrigin: `${fx * 100}% ${fy * 100}%` }}>
        <Media src={s.src ?? ctx.source} from={s.start} filter={ctx.filter} position={`${fx * 100}% ${fy * 100}%`} />
      </AbsoluteFill>
      {s.fade !== undefined && (
        <AbsoluteFill style={{ background: `linear-gradient(180deg, transparent ${(s.fade - 0.14) * 100}%, rgba(0,0,0,.85) ${(s.fade - 0.04) * 100}%, #000 ${s.fade * 100}%)` }} />
      )}
    </AbsoluteFill>
  );
};

export const Title: React.FC<{ s: TitleScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const p = pop(frame, 0, 9);
  const size = Math.min(330, 1700 / Math.max(3, [...s.text].length));
  return (
    <AbsoluteFill>
      <SpeakerBackdrop ctx={ctx} start={s.start} dim={0.28} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", flexDirection: "column" }}>
        {(s.number || s.label) && (
          <div style={{ display: "flex", alignItems: "center", gap: 18, padding: "14px 30px 14px 16px", borderRadius: 60, background: "rgba(20,20,24,.72)",
            border: "2px solid rgba(255,255,255,.14)", marginBottom: 40, opacity: pop(frame, 4, 8), transform: `translateY(${(1 - pop(frame, 4, 8)) * 30}px)` }}>
            {s.number && <div style={{ width: 64, height: 64, borderRadius: 32, border: `4px solid ${ctx.accent}`, color: ctx.accent, fontFamily: BODY_FONT, fontWeight: 900, fontSize: 36, display: "flex", alignItems: "center", justifyContent: "center", boxShadow: glow(ctx.accent, 0.6) }}>{s.number}</div>}
            {s.label && <div style={{ color: "#fff", fontFamily: BODY_FONT, fontWeight: 800, fontSize: 40, textTransform: "uppercase", letterSpacing: 2 }}>{s.label}</div>}
          </div>
        )}
        <div style={{ position: "relative", transform: `scale(${1.35 - 0.35 * p}) rotate(-3deg)`, filter: `blur(${(1 - p) * 18}px)`, opacity: Math.min(1, p * 1.5) }}>
          <div style={{ fontFamily: KEY_FONT, fontSize: size, lineHeight: 1, textTransform: "uppercase", color: `${ctx.accent}26`, WebkitTextStroke: `5px ${ctx.accent}`,
            filter: `drop-shadow(0 0 18px ${ctx.accent}) drop-shadow(0 0 50px ${ctx.accent}88)`, whiteSpace: "nowrap" }}>{s.text}</div>
          {s.script && <div style={{ position: "absolute", right: -20, top: -size * 0.32, fontFamily: SCRIPT_FONT, fontSize: size * 0.42, color: "#fff", transform: "rotate(-8deg)",
            textShadow: darkShadow, opacity: pop(frame, 7, 6) }}>{s.script}</div>}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const Cards: React.FC<{ s: CardsScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const n = s.items.length;
  const step = Math.max(8, Math.floor((durationInFrames - 10) / n));
  const big = n === 1;
  const cw = big ? 760 : 560, ch = big ? 1000 : 720;
  // Zig-zag slots; the newest card sits center-right, older ones drift left and shrink, leaving a trail.
  const slots = s.items.map((_, i) => (big ? { x: 540, y: 820 } : { x: 540 + (i % 2 ? -150 : 150), y: 760 + (i % 2 ? 140 : -40) }));
  const shown = s.items.map((_, i) => pop(frame, i * step, 10));
  const pathD = slots.map((p, i) => `${i ? "L" : "M"} ${p.x} ${p.y + ch * 0.3}`).join(" ");
  return (
    <AbsoluteFill>
      <Backdrop bg={s.bg ?? "paper"} ctx={ctx} start={s.start} />
      {s.string && n > 1 && (
        <svg width={1080} height={1920} style={{ position: "absolute" }}>
          <path d={pathD} stroke="#d4111e" strokeWidth={9} fill="none" strokeLinecap="round"
            {...evolvePath(interpolate(frame, [0, step * (n - 1) + 10], [0, 1], clamp), pathD)} />
        </svg>
      )}
      {s.items.map((it, i) => {
        const p = shown[i];
        if (p <= 0) return null;
        const age = s.items.slice(i + 1).reduce((a, _, j) => a + pop(frame, (i + 1 + j) * step, 10), 0);
        const x = slots[i].x - age * 70, y = slots[i].y - age * 20;
        const kb = interpolate(frame, [i * step, durationInFrames], [1, 1.08], clamp);
        return (
          <div key={i} style={{ position: "absolute", left: x - cw / 2, top: y - ch / 2, width: cw,
            transform: `translateX(${(1 - p) * 520}px) rotate(${(1 - p) * 10 + (i % 2 ? -2 : 2)}deg) scale(${1 - age * 0.12})`,
            filter: `blur(${(1 - p) * 22 + age * 1.5}px)`, opacity: Math.min(1, p * 1.6) * (1 - age * 0.25), zIndex: i }}>
            <div style={{ width: cw, height: ch, borderRadius: 44, overflow: "hidden", boxShadow: "0 30px 70px rgba(0,0,0,.45)", border: "3px solid rgba(255,255,255,.65)" }}>
              <Media src={it.src} from={it.from ?? 0} style={{ transform: `scale(${kb})` }} filter={ctx.filter} />
            </div>
            {it.label && (
              <div style={{ margin: "26px auto 0", width: "fit-content", padding: "14px 38px", borderRadius: 60, background: "#fff", color: "#111",
                fontFamily: BODY_FONT, fontWeight: 800, fontSize: 44, boxShadow: "0 10px 30px rgba(0,0,0,.3)", transform: `scale(${pop(frame, i * step + 5, 6)})` }}>{it.label}</div>
            )}
          </div>
        );
      })}
    </AbsoluteFill>
  );
};

export const Phone: React.FC<{ s: PhoneScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  const grow = interpolate(frame, [0, durationInFrames - 6], [0.55, 0.92], { ...clamp, easing: easeOut });
  const through = interpolate(frame, [durationInFrames - 6, durationInFrames], [1, 2.6], clamp);
  const words = (s.title ?? "").split(/\s+/).filter(Boolean);
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ background: s.bg === "dark" ? "radial-gradient(circle, #26262c, #0b0b0d)" : "radial-gradient(circle at 50% 40%, #fbfbfc, #dfe2e7)" }} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
        <div style={{ width: 860, height: 1760, borderRadius: 120, background: "#0e0e10", padding: 26, boxShadow: "0 50px 120px rgba(0,0,0,.35)",
          transform: `scale(${grow * through})`, filter: `blur(${(through - 1) * 6}px)` }}>
          <div style={{ position: "relative", width: "100%", height: "100%", borderRadius: 96, overflow: "hidden", background: "#000" }}>
            <Media src={s.src ?? ctx.source} from={s.from ?? s.start} filter={ctx.filter} />
            <div style={{ position: "absolute", top: 22, left: "50%", width: 230, height: 62, marginLeft: -115, borderRadius: 40, background: "#000" }} />
            <div style={{ position: "absolute", top: 150, left: 40, right: 40, textAlign: "center", display: "flex", flexDirection: "column", alignItems: "center" }}>
              {words.map((w, i) => {
                const p = pop(frame, 4 + i * 5, 6);
                return <div key={i} style={{ fontFamily: KEY_FONT, fontSize: i === 1 && words.length > 2 ? 230 : 120, lineHeight: 0.95, color: ctx.accent, textTransform: "uppercase",
                  textShadow: glow(ctx.accent, 0.7), opacity: p, transform: `scale(${0.7 + 0.3 * p})`, filter: `blur(${(1 - p) * 10}px)` }}>{w}</div>;
              })}
            </div>
          </div>
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const Broll: React.FC<{ s: BrollScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();
  return (
    <AbsoluteFill style={{ transform: `scale(${interpolate(frame, [0, durationInFrames], [1.02, 1.12])})` }}>
      <Media src={s.src} from={s.from ?? 0} filter={ctx.filter} />
    </AbsoluteFill>
  );
};

export const NumberCard: React.FC<{ s: NumberScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const m = s.value.match(/-?\d[\d.]*(?:,\d+)?/);
  const raw = m ? m[0] : "0";
  const [whole, frac = ""] = raw.split(",");
  const target = parseFloat(whole.replace(/\./g, "") + (frac ? `.${frac}` : ""));
  const v = target * interpolate(frame, [3, 27], [0, 1], { ...clamp, easing: easeOut });
  const shown = s.value.replace(raw, v.toLocaleString(ctx.locale, { minimumFractionDigits: frac.length, maximumFractionDigits: frac.length }));
  const p = pop(frame, 0, 8);
  return (
    <AbsoluteFill>
      <SpeakerBackdrop ctx={ctx} start={s.start} dim={0.3} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", flexDirection: "column" }}>
        <div style={{ fontFamily: KEY_FONT, fontSize: Math.min(300, 1500 / Math.max(3, shown.length)), color: ctx.accent, textShadow: glow(ctx.accent, 1.2), transform: `scale(${0.8 + 0.2 * p})`, filter: `blur(${(1 - p) * 14}px)` }}>{shown}</div>
        {s.label && <div style={{ marginTop: 20, padding: "0 80px", textAlign: "center", fontFamily: BODY_FONT, fontWeight: 800, fontSize: 64, color: "#fff", textShadow: darkShadow, opacity: pop(frame, 10, 8) }}>{s.label}</div>}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const SceneView: React.FC<{ s: Scene; ctx: Ctx }> = ({ s, ctx }) => {
  switch (s.type) {
    case "speaker": return <Speaker s={s} ctx={ctx} />;
    case "title": return <Title s={s} ctx={ctx} />;
    case "text3d": return <Text3DTitle text={s.text} color={s.color ?? ctx.accent} background="radial-gradient(circle,#2b2b33,#0b0b0d)" />;
    case "cards": return <Cards s={s} ctx={ctx} />;
    case "phone": return <Phone s={s} ctx={ctx} />;
    case "broll": return <Broll s={s} ctx={ctx} />;
    case "number": return <NumberCard s={s} ctx={ctx} />;
  }
};
