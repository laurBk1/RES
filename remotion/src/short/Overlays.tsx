import { evolvePath } from "@remotion/paths";
import React from "react";
import { AbsoluteFill, Easing, interpolate, Sequence, useCurrentFrame } from "remotion";
import { BODY_FONT, CAP_FONT, KEY_FONT, SCRIPT_FONT } from "./fonts";
import type { Overlay } from "./types";
import { clamp, darkShadow, f, glow, pop } from "./util";

const Fade: React.FC<{ dur: number; children: (p: number) => React.ReactNode }> = ({ dur, children }) => {
  const frame = useCurrentFrame();
  const out = interpolate(frame, [Math.max(0, dur - 5), Math.max(1, dur)], [1, 0], clamp);
  return <AbsoluteFill style={{ opacity: out, pointerEvents: "none" }}>{children(frame)}</AbsoluteFill>;
};

const Bookmark: React.FC<{ frame: number; accent: string; text: string; x: number; y: number }> = ({ frame, accent, text, x, y }) => {
  const p = pop(frame, 0, 8);
  return (
    <div style={{ position: "absolute", left: x * 1080 - 90, top: y * 1920 - 120, display: "flex", flexDirection: "column", alignItems: "center",
      transform: `scale(${0.4 + 0.6 * p}) rotate(${(1 - p) * -20}deg)`, opacity: p }}>
      <svg width={180} height={220} viewBox="0 0 24 30" style={{ filter: `drop-shadow(0 0 16px ${accent}) drop-shadow(0 0 40px ${accent}88)` }}>
        <path d="M3 2h18v26l-9-7-9 7z" fill={accent} />
      </svg>
      <div style={{ marginTop: 14, fontFamily: BODY_FONT, fontWeight: 900, fontSize: 52, color: "#fff", textShadow: darkShadow, whiteSpace: "nowrap" }}>{text}</div>
    </div>
  );
};

const Arrow: React.FC<{ frame: number; accent: string; o: Extract<Overlay, { type: "arrow" }> }> = ({ frame, accent, o }) => {
  const tx = o.x * 1080, ty = o.y * 1920;
  const side = o.from === "left" ? -1 : 1;
  const sx = Math.min(800, Math.max(280, tx + side * 300)), sy = ty - 260;
  const d = `M ${sx} ${sy} Q ${tx + side * 40} ${sy - 40} ${tx + side * 20} ${ty - 30}`;
  const draw = interpolate(frame, [2, 14], [0, 1], clamp);
  return (
    <>
      <svg width={1080} height={1920} style={{ position: "absolute", filter: `drop-shadow(0 0 8px ${accent}99)` }}>
        {/* The dashed arrow is revealed through a mask that draws on, so the dash pattern stays intact. */}
        <mask id={`am${o.at}`}><path d={d} stroke="#fff" strokeWidth={16} fill="none" {...evolvePath(draw, d)} /></mask>
        <path d={d} stroke={accent} strokeWidth={8} fill="none" strokeLinecap="round" strokeDasharray="22 16" mask={`url(#am${o.at})`} />
        <path d={`M ${tx + side * 20 - 26} ${ty - 64} L ${tx + side * 20} ${ty - 30} L ${tx + side * 20 + 30} ${ty - 58}`} stroke={accent} strokeWidth={8} fill="none" strokeLinecap="round" opacity={draw >= 1 ? 1 : 0} />
      </svg>
      <div style={{ position: "absolute", left: sx - 250, width: 500, top: sy - 100, textAlign: "center", fontFamily: SCRIPT_FONT, fontSize: 76, color: accent, textShadow: glow(accent, 0.5), opacity: pop(frame, 0, 6) }}>{o.label}</div>
    </>
  );
};

/** One-off graphics laid over any scene: save prompt, arrows, face box, section pill, call to action, view count, ring. */
export const Overlays: React.FC<{ overlays: Overlay[]; accent: string }> = ({ overlays, accent }) => (
  <>
    {overlays.map((o, i) => {
      const dur = f(o.dur ?? (o.type === "cta" ? 3 : o.type === "bigword" ? 1.1 : o.type === "lightleak" ? 0.8 : 1.6));
      return (
        <Sequence key={i} from={f(o.at)} durationInFrames={dur} layout="none">
          <Fade dur={dur}>
            {(frame) => {
              switch (o.type) {
                case "bookmark":
                  return <Bookmark frame={frame} accent={accent} text={o.text ?? "Salvează clipul"} x={o.x ?? 0.75} y={o.y ?? 0.3} />;
                case "arrow":
                  return <Arrow frame={frame} accent={accent} o={o} />;
                case "eyebox": {
                  const p = pop(frame, 0, 7);
                  return (
                    <div style={{ position: "absolute", left: o.x * 1080 - (o.w * 1080) / 2, top: o.y * 1920 - (o.h * 1920) / 2, width: o.w * 1080, height: o.h * 1920,
                      border: `6px solid ${accent}`, borderRadius: 10, boxShadow: glow(accent, 0.6), transform: `rotate(-6deg) scale(${1.4 - 0.4 * p})`, opacity: p }}>
                      {o.label && <div style={{ position: "absolute", left: "105%", top: "50%", transform: "translateY(-50%)", whiteSpace: "nowrap", fontFamily: BODY_FONT, fontWeight: 900, fontSize: 54, color: "#fff", textShadow: darkShadow }}>{o.label}</div>}
                    </div>
                  );
                }
                case "pill": {
                  const p = pop(frame, 0, 8);
                  return (
                    <div style={{ position: "absolute", top: (o.y ?? 0.56) * 1920, left: 0, right: 0, display: "flex", justifyContent: "center", opacity: p, transform: `translateY(${(1 - p) * 20}px)` }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 16, padding: "12px 30px 12px 14px", borderRadius: 50, background: "rgba(18,18,22,.78)", border: "2px solid rgba(255,255,255,.12)" }}>
                        {o.number && <div style={{ width: 52, height: 52, borderRadius: 26, border: `4px solid ${accent}`, color: accent, fontFamily: BODY_FONT, fontWeight: 900, fontSize: 28, display: "flex", alignItems: "center", justifyContent: "center" }}>{o.number}</div>}
                        <div style={{ fontFamily: BODY_FONT, fontWeight: 700, fontSize: 38, color: "#fff" }}>{o.text}</div>
                      </div>
                    </div>
                  );
                }
                case "cta": {
                  const p = pop(frame, 0, 9);
                  const kw = o.quote === false ? o.keyword : `„${o.keyword}”`;
                  return (
                    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", flexDirection: "column", top: 300 }}>
                      <div style={{ fontFamily: BODY_FONT, fontWeight: 900, fontSize: 70, color: "#fff", textShadow: darkShadow, opacity: p }}>{o.text ?? "Comentează"}</div>
                      <div style={{ fontFamily: KEY_FONT, fontSize: Math.min(200, 2000 / Math.max(4, [...kw].length)), lineHeight: 1, color: accent, textShadow: glow(accent, 1.2), textTransform: "uppercase",
                        transform: `scale(${0.6 + 0.4 * pop(frame, 4, 8)})`, filter: `blur(${(1 - pop(frame, 4, 8)) * 14}px)` }}>{kw}</div>
                    </AbsoluteFill>
                  );
                }
                case "views": {
                  const p = pop(frame, 0, 8);
                  return (
                    <div style={{ position: "absolute", top: (o.y ?? 0.72) * 1920, left: 0, right: 0, display: "flex", justifyContent: "center", opacity: p, transform: `scale(${0.8 + 0.2 * p})` }}>
                      <div style={{ display: "flex", alignItems: "center", gap: 14, padding: "16px 34px", borderRadius: 50, background: "rgba(10,10,12,.82)", fontFamily: BODY_FONT, fontWeight: 800, fontSize: 48, color: "#fff" }}>
                        <svg width={48} height={48} viewBox="0 0 24 24"><path d="M12 5C6 5 2 12 2 12s4 7 10 7 10-7 10-7-4-7-10-7zm0 11a4 4 0 1 1 0-8 4 4 0 0 1 0 8z" fill="#fff" /></svg>
                        {o.text}
                      </div>
                    </div>
                  );
                }
                case "ring": {
                  const p = pop(frame, 0, 8);
                  return <div style={{ position: "absolute", left: o.x * 1080 - o.r * 1080, top: o.y * 1920 - o.r * 1080, width: o.r * 2160, height: o.r * 2160, borderRadius: "50%",
                    border: `8px solid ${accent}`, boxShadow: `${glow(accent)}, inset ${glow(accent, 0.6)}`, transform: `scale(${1.5 - 0.5 * p})`, opacity: p }} />;
                }
                case "bigword": {
                  // Slam in from 3x with blur, hold with a slow push, then dolly through the lens.
                  const c = o.color ?? accent;
                  const slam = interpolate(frame, [0, 6], [3.2, 1], { ...clamp, easing: Easing.bezier(0.16, 1, 0.3, 1) });
                  const thru = interpolate(frame, [dur - 7, dur], [1, 6], { ...clamp, easing: Easing.in(Easing.quad) });
                  const hold = interpolate(frame, [6, dur - 7], [1, 1.08], clamp);
                  const size = Math.min(300, 960 / (0.8 * Math.max(3, [...o.text].length)));
                  const depth = [...Array(12)].map((_, k) => `0 ${k + 1}px 0 ${k < 6 ? "#00000099" : "#000000cc"}`).join(", ");
                  return (
                    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", perspective: 1000, background: `radial-gradient(circle, rgba(0,0,0,.35), rgba(0,0,0,.7))`,
                      opacity: interpolate(frame, [0, 3], [0, 1], clamp) * interpolate(thru, [1, 4], [1, 0], clamp) }}>
                      <div style={{ fontFamily: CAP_FONT, fontWeight: 900, fontSize: size, lineHeight: 0.9, color: c, textTransform: "uppercase", letterSpacing: -3, textAlign: "center",
                        textShadow: `${depth}, ${glow(c, 1.4)}`, transform: `rotateX(12deg) rotateY(${Math.sin(frame / 12) * 6}deg) scale(${slam * thru * hold})`,
                        filter: `blur(${interpolate(slam, [1, 3.2], [0, 18])}px)` }}>{o.text}</div>
                    </AbsoluteFill>
                  );
                }
                case "lightleak": {
                  const p = interpolate(frame, [0, dur], [0, 1], clamp);
                  const x = interpolate(p, [0, 1], [-40, 140]);
                  return (
                    <AbsoluteFill style={{ mixBlendMode: "screen", opacity: Math.sin(Math.PI * p) }}>
                      <AbsoluteFill style={{ background: `radial-gradient(ellipse 60% 45% at ${x}% 30%, rgba(255,140,40,.9), rgba(255,50,30,.4) 45%, transparent 70%)` }} />
                      <AbsoluteFill style={{ background: `linear-gradient(115deg, transparent ${x - 25}%, rgba(255,230,170,.35) ${x - 10}%, transparent ${x + 5}%)` }} />
                    </AbsoluteFill>
                  );
                }
              }
            }}
          </Fade>
        </Sequence>
      );
    })}
  </>
);
