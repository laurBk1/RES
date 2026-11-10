import { evolvePath } from "@remotion/paths";
import React from "react";
import { AbsoluteFill, Easing, Img, interpolate, OffthreadVideo, useCurrentFrame } from "remotion";
import { BODY_FONT, CAP_FONT, KEY_FONT, SCRIPT_FONT } from "./fonts";
import { Text3DTitle } from "../Text3DTitle";
import type { BrollScene, CardsScene, GlassScene, GridScene, NumberScene, PhoneScene, PipScene, Scene, SpeakerScene, SplitScene, TitleScene, Word } from "./types";
import { asset, clamp, darkShadow, easeOut, f, glow, isVideo, norm, pop, useCoreDur } from "./util";

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
  const durationInFrames = useCoreDur();
  const [fx, fy] = s.focus ?? [0.5, 0.38];
  const keys = new Set(ctx.keywords.map(norm));
  // A 5% scale kick that settles over 8 frames on every keyword the speaker hits.
  const kick = ctx.words
    .filter((w) => w.start >= s.start && w.start < s.end && keys.has(norm(w.text)))
    .reduce((k, w) => Math.max(k, interpolate(frame, [f(w.start - s.start), f(w.start - s.start) + 8], [0.05, 0], clamp)), 0);
  const push = interpolate(frame, [0, durationInFrames], [1, 1.05]);
  return (
    <AbsoluteFill>
      {(s.zoom ?? 1) < 1 && <SpeakerBackdrop ctx={{ ...ctx, source: s.src ?? ctx.source }} start={s.start} dim={0.45} />}
      <AbsoluteFill style={{ transform: `scale(${(s.zoom ?? 1) * push * (1 + kick)})`, transformOrigin: `${fx * 100}% ${fy * 100}%`,
        ...((s.zoom ?? 1) < 1 ? { borderRadius: 40, overflow: "hidden", boxShadow: "0 40px 100px rgba(0,0,0,.6)" } : {}) }}>
        <Media src={s.src ?? ctx.source} from={s.start} filter={ctx.filter} position={`${fx * 100}% ${fy * 100}%`} />
      </AbsoluteFill>
      {s.fade !== undefined && (
        // Below the fade line: a blurred, darkened mirror of the frame (a glossy floor) instead of flat black.
        <div style={{ position: "absolute", left: 0, right: 0, top: `${s.fade * 100}%`, bottom: 0, overflow: "hidden" }}>
          <div style={{ position: "absolute", left: 0, top: `${-s.fade * 1920}px`, width: 1080, height: 1920, transform: "scaleY(-1)", transformOrigin: `50% ${s.fade * 100}%` }}>
            <Media src={s.src ?? ctx.source} from={s.start} filter="blur(26px) brightness(.32) saturate(1.2)" position={`${fx * 100}% ${fy * 100}%`} />
          </div>
          <AbsoluteFill style={{ background: "linear-gradient(180deg, rgba(0,0,0,.55), rgba(0,0,0,.15) 30%, rgba(0,0,0,.6))" }} />
        </div>
      )}
      {s.fade !== undefined && (
        <AbsoluteFill style={{ background: `linear-gradient(180deg, transparent ${(s.fade - 0.1) * 100}%, rgba(0,0,0,.7) ${s.fade * 100}%, transparent ${(s.fade + 0.06) * 100}%)` }} />
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
  const durationInFrames = useCoreDur();
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
  const durationInFrames = useCoreDur();
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
  const durationInFrames = useCoreDur();
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

/** Liquid-glass list (iOS-style inner highlight); rows land on the word that names them. */
export const Glass: React.FC<{ s: GlassScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const dur = useCoreDur();
  const step = Math.max(8, Math.floor((dur - 12) / Math.max(1, s.items.length)));
  const at = s.items.map((it, i) => {
    const first = norm(it.split(/\s+/)[0] ?? "");
    const w = ctx.words.find((x) => x.start >= s.start - 0.1 && x.start < s.end && norm(x.text) === first);
    return w ? Math.max(0, f(w.start - s.start) - 2) : 6 + i * step;
  });
  const card = pop(frame, 0, 10);
  return (
    <AbsoluteFill>
      <Backdrop bg={s.bg ?? "speaker"} ctx={ctx} start={s.start} />
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", perspective: 1400 }}>
        <div style={{ width: 900, padding: "56px 54px 40px", borderRadius: 48, border: "1.5px solid rgba(255,255,255,.22)",
          background: "linear-gradient(135deg, rgba(255,255,255,.14), rgba(255,255,255,.04) 40%, rgba(255,255,255,.02) 60%, rgba(255,255,255,.10))",
          backdropFilter: "blur(18px) saturate(1.2)", boxShadow: "inset 0 1px 0 rgba(255,255,255,.35), 0 40px 90px rgba(0,0,0,.5)",
          transform: `rotateX(${(1 - card) * 25 + Math.sin(frame / 30) * 2}deg) rotateY(${Math.sin(frame / 40) * 4}deg) scale(${0.85 + 0.15 * card})`, opacity: card }}>
          {s.title && <div style={{ fontFamily: KEY_FONT, fontSize: 96, lineHeight: 1, color: ctx.accent, textTransform: "uppercase", textShadow: glow(ctx.accent, 0.7), marginBottom: 26 }}>{s.title}</div>}
          {s.items.map((it, i) => {
            const p = pop(frame, at[i], 9);
            return (
              <div key={i} style={{ display: "flex", alignItems: "center", gap: 26, padding: "22px 0", borderTop: i ? "1px solid rgba(255,255,255,.1)" : undefined,
                opacity: p, transform: `translateX(${(1 - p) * -60}px)`, filter: `blur(${(1 - p) * 8}px)` }}>
                <div style={{ width: 66, height: 66, flex: "none", borderRadius: 33, background: ctx.accent, color: "#111", fontFamily: BODY_FONT, fontWeight: 900, fontSize: 34,
                  display: "flex", alignItems: "center", justifyContent: "center", boxShadow: glow(ctx.accent, 0.6), transform: `scale(${0.5 + 0.5 * p})` }}>{i + 1}</div>
                <div style={{ fontFamily: BODY_FONT, fontWeight: 800, fontSize: 58, color: "#fff", lineHeight: 1.1 }}>{it}</div>
              </div>
            );
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

/** Chrome headline over a receding grid floor, sparkles, and a conic light beam; exits by dollying through the type. */
export const Grid: React.FC<{ s: GridScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const dur = useCoreDur();
  const words = s.text.split(/\s+/);
  const size = Math.min(260, 960 / (0.8 * Math.max(4, ...words.map((w) => w.length))));
  const dolly = interpolate(frame, [dur - 8, dur + 6], [1, 5], { ...clamp, easing: Easing.in(Easing.quad) });
  return (
    <AbsoluteFill style={{ background: "#030304", overflow: "hidden" }}>
      <div style={{ position: "absolute", left: -600, right: -600, top: 980, height: 1600, transformOrigin: "50% 0", transform: "perspective(900px) rotateX(62deg)",
        backgroundImage: "repeating-linear-gradient(90deg, rgba(255,255,255,.09) 0 2px, transparent 2px 110px), repeating-linear-gradient(0deg, rgba(255,255,255,.09) 0 2px, transparent 2px 110px)",
        backgroundPositionY: `${frame * 3}px`, maskImage: "linear-gradient(180deg, transparent, #000 25%, #000 70%, transparent)" }} />
      <AbsoluteFill style={{ background: `conic-gradient(from 180deg at 50% -10%, transparent 160deg, ${ctx.accent}22 180deg, transparent 200deg)`, filter: "blur(30px)" }} />
      {[...Array(28)].map((_, i) => {
        const x = 40 + ((i * 397) % 1000), y = 200 + ((i * 613) % 1500);
        const tw = 0.3 + 0.7 * Math.abs(Math.sin(frame / 9 + i * 1.7));
        return <div key={i} style={{ position: "absolute", left: x, top: y, color: "#fff", opacity: tw * 0.55, fontFamily: BODY_FONT, fontSize: 26, fontWeight: 300 }}>+</div>;
      })}
      <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", flexDirection: "column", transform: `scale(${dolly})`, opacity: interpolate(dolly, [1, 4], [1, 0], clamp) }}>
        {words.map((w, i) => {
          const at = 2 + i * 5;
          const p = pop(frame, at, 8);
          const sweep = interpolate(frame, [at, at + 18], [100, 0], clamp);
          return (
            <div key={i} style={{ fontFamily: CAP_FONT, fontWeight: 900, fontSize: size, lineHeight: 0.95, textTransform: "uppercase", letterSpacing: -2,
              backgroundImage: `linear-gradient(90deg, #8a8f99 0%, #fff ${30 + (100 - sweep) * 0.4}%, ${ctx.accent} ${55 + (100 - sweep) * 0.3}%, #fff 80%, #9aa0aa 100%)`,
              backgroundSize: "300% 100%", backgroundPosition: `${sweep}% 0`, WebkitBackgroundClip: "text", color: "transparent",
              filter: `drop-shadow(0 0 22px rgba(255,255,255,.35)) blur(${(1 - p) * 14}px)`,
              transform: `translateY(${(1 - p) * 80}px) scale(${0.8 + 0.2 * p})`, opacity: p }}>{w}</div>
          );
        })}
        {s.sub && <div style={{ marginTop: 30, fontFamily: BODY_FONT, fontWeight: 700, fontSize: 52, color: "rgba(255,255,255,.75)", letterSpacing: 6, textTransform: "uppercase", opacity: pop(frame, 12, 10) }}>{s.sub}</div>}
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

export const Split: React.FC<{ s: SplitScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const p = pop(frame, 0, 10);
  const [fx, fy] = s.focus ?? [0.5, 0.3];
  const half = (node: React.ReactNode, y: number) => (
    <div style={{ position: "absolute", left: 0, right: 0, top: y, height: 960, overflow: "hidden", transform: `translateY(${(1 - p) * (y ? 120 : -120)}px)` }}>
      <div style={{ width: "100%", height: "100%", transform: `scale(${interpolate(frame, [0, 120], [1.04, 1.12])})` }}>{node}</div>
    </div>
  );
  const broll = <Media src={s.src} from={s.from ?? 0} filter={ctx.filter} />;
  const speaker = <Media src={ctx.source} from={s.start} filter={ctx.filter} position={`${fx * 100}% ${fy * 100}%`} />;
  return (
    <AbsoluteFill style={{ background: "#000" }}>
      {half(s.speakerTop ? speaker : broll, 0)}
      {half(s.speakerTop ? broll : speaker, 960)}
      <div style={{ position: "absolute", left: 0, right: 0, top: 957, height: 6, background: ctx.accent, boxShadow: glow(ctx.accent, 1), transform: `scaleX(${p})` }} />
    </AbsoluteFill>
  );
};

export const Pip: React.FC<{ s: PipScene; ctx: Ctx }> = ({ s, ctx }) => {
  const frame = useCurrentFrame();
  const p = pop(frame, 0, 10);
  const [fx, fy] = s.focus ?? [0.5, 0.3];
  const tags = s.tags ?? [];
  const slots = [[90, 360], [640, 520], [70, 1260], [620, 1420]];
  return (
    <AbsoluteFill>
      <SpeakerBackdrop ctx={ctx} start={s.start} dim={0.3} />
      <div style={{ position: "absolute", left: 190, top: 470, width: 700, height: 980, borderRadius: 56, overflow: "hidden",
        border: `3px solid ${ctx.accent}AA`, boxShadow: `${glow(ctx.accent, 1)}, 0 40px 100px rgba(0,0,0,.6)`,
        transform: `perspective(1400px) rotateY(${(1 - p) * -30 + Math.sin(frame / 35) * 3}deg) scale(${0.8 + 0.2 * p})`, opacity: p }}>
        <Media src={ctx.source} from={s.start} filter={ctx.filter} position={`${fx * 100}% ${fy * 100}%`} style={{ transform: "scale(1.5)", transformOrigin: `${fx * 100}% ${fy * 100}%` }} />
      </div>
      {s.label && <div style={{ position: "absolute", top: 1490, left: 0, right: 0, textAlign: "center" }}>
        <span style={{ padding: "12px 34px", borderRadius: 40, background: ctx.accent, color: "#111", fontFamily: BODY_FONT, fontWeight: 900, fontSize: 40, letterSpacing: 2, textTransform: "uppercase" }}>{s.label}</span>
      </div>}
      {tags.slice(0, 4).map((tag, i) => {
        const q = pop(frame, 6 + i * 6, 8);
        const [x, y] = slots[i];
        return (
          <div key={i} style={{ position: "absolute", left: x, top: y, padding: "16px 28px", borderRadius: 18, background: "rgba(15,15,18,.75)", border: "1.5px solid rgba(255,255,255,.18)",
            boxShadow: "inset 0 1px 0 rgba(255,255,255,.25)", fontFamily: BODY_FONT, fontWeight: 800, fontSize: 40, color: "#fff",
            opacity: q, transform: `translateY(${(1 - q) * 30}px) scale(${0.8 + 0.2 * q}) translateY(${Math.sin(frame / 18 + i) * 6}px)` }}>
            <span style={{ color: ctx.accent, marginRight: 12 }}>⌁</span>{tag}
          </div>
        );
      })}
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
    case "glass": return <Glass s={s} ctx={ctx} />;
    case "grid": return <Grid s={s} ctx={ctx} />;
    case "split": return <Split s={s} ctx={ctx} />;
    case "pip": return <Pip s={s} ctx={ctx} />;
  }
};
