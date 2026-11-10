import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import type { Transition } from "./types";
import { clamp, jitter } from "./util";

/**
 * Wraps one scene and applies its entry transition (from `inT`) and its exit (mirroring the next scene's `outT`).
 * Lengths follow the references: whip 5 f, zoom 7 f, flash 3 f up and 6 f down, glitch 5 f.
 */
export const TransitionWrap: React.FC<{ inT: Transition; outT: Transition; id: string; children: React.ReactNode }> = ({ inT, outT, id, children }) => {
  const frame = useCurrentFrame();
  const { durationInFrames: d } = useVideoConfig();
  const left = d - frame;
  let tx = 0, ty = 0, scale = 1, blur = 0, opacity = 1, rgb = 0;

  if (inT === "whip") { const p = interpolate(frame, [0, 5], [1, 0], clamp); tx += p * 700; blur += p * 30; }
  if (inT === "zoom") { const p = interpolate(frame, [0, 7], [1, 0], clamp); scale *= 1 + p * 0.35; blur += p * 18; }
  if (inT === "flash") { blur += interpolate(frame, [0, 6], [14, 0], clamp); scale *= interpolate(frame, [0, 8], [1.08, 1], clamp); }
  // Starts at 45% opacity, not 0, so the first frame is never black.
  if (inT === "blur") { const p = interpolate(frame, [0, 9], [1, 0], clamp); blur += p * 24; opacity *= 1 - p * 0.55; }
  if (inT === "glitch" && frame < 6) { tx += jitter(id, frame, 40); ty += jitter(`${id}y`, frame, 14); rgb = 14; }

  if (outT === "whip") { const p = interpolate(frame, [d - 5, d], [0, 1], clamp); tx -= p * 700; blur += p * 30; }
  if (outT === "zoom") { const p = interpolate(frame, [d - 5, d], [0, 1], clamp); scale *= 1 + p * 0.2; blur += p * 10; }
  if (outT === "flash") blur += interpolate(frame, [d - 4, d], [0, 12], clamp);
  if (outT === "glitch" && left <= 3) { tx += jitter(`${id}o`, frame, 30); rgb = 10; }

  return (
    <AbsoluteFill
      style={{
        transform: `translate(${tx}px, ${ty}px) scale(${scale})`,
        filter: [blur > 0.3 ? `blur(${blur}px)` : "", rgb ? `drop-shadow(${rgb}px 0 0 rgba(255,0,60,.8)) drop-shadow(${-rgb}px 0 0 rgba(0,240,255,.8))` : ""].join(" ") || undefined,
        opacity,
        background: "#000",
      }}
    >
      {children}
      {rgb > 0 && (
        <AbsoluteFill style={{ background: `repeating-linear-gradient(0deg, transparent 0 ${40 + (frame % 3) * 17}px, rgba(255,255,255,.12) ${40 + (frame % 3) * 17}px ${48 + (frame % 3) * 17}px)` }} />
      )}
    </AbsoluteFill>
  );
};

/** Full-frame flash around a cut at `at` (frames): ramps up over 3 frames, holds, and decays over 6. */
export const Flash: React.FC<{ at: number; color: string }> = ({ at, color }) => {
  const frame = useCurrentFrame();
  const o = frame < at ? interpolate(frame, [at - 3, at], [0, 1], clamp) : interpolate(frame, [at, at + 1, at + 7], [1, 0.9, 0], clamp);
  if (o <= 0) return null;
  return <AbsoluteFill style={{ background: `radial-gradient(circle, ${color} 0%, ${color} 40%, ${color}CC 100%)`, opacity: o, mixBlendMode: "screen", pointerEvents: "none" }} />;
};
