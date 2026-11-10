import React from "react";
import { AbsoluteFill, Easing, interpolate } from "remotion";
import type { Transition } from "./types";
import { clamp, jitter } from "./util";

/**
 * Overlap transitions: the outgoing scene keeps playing for `T` frames past its end while the incoming scene
 * plays its first `T` frames on top, so both layers move together (no hard swap). Lengths at 30 fps.
 */
export const T_LEN: Record<Transition, number> = {
  cut: 0, flash: 8, whip: 8, "whip-up": 8, zoom: 10, glitch: 8, blur: 10,
  lightleak: 14, cube: 12, iris: 12, swipe: 10, spin: 10, dolly: 10,
};

const inE = Easing.bezier(0.55, 0, 1, 0.45); // power2.in-ish: exits accelerate
const outE = Easing.bezier(0.16, 1, 0.3, 1); // expo.out: entries decelerate
const tri = (p: number) => 1 - Math.abs(p * 2 - 1); // 0 -> 1 at the midpoint -> 0

type Look = { transform: string; filters: string[]; opacity: number; clip?: string; origin?: string; overlay?: React.ReactNode; svg?: React.ReactNode };

/** Directional motion blur: CSS blur is round, an SVG gaussian with a 0 y-deviation streaks along x (or y). */
const MotionBlurDef: React.FC<{ id: string; x: number; y: number }> = ({ id, x, y }) => (
  <svg width={0} height={0} style={{ position: "absolute" }}>
    <filter id={id} x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation={`${x} ${y}`} /></filter>
  </svg>
);

const GlitchDef: React.FC<{ id: string; amt: number; seed: number }> = ({ id, amt, seed }) => (
  <svg width={0} height={0} style={{ position: "absolute" }}>
    <filter id={id} x="-10%" y="-10%" width="120%" height="120%" colorInterpolationFilters="sRGB">
      <feTurbulence type="fractalNoise" baseFrequency="0.0001 0.09" numOctaves="1" seed={seed} result="n" />
      <feDisplacementMap in="SourceGraphic" in2="n" scale={amt * 140} xChannelSelector="R" yChannelSelector="A" result="d" />
      <feColorMatrix in="d" type="matrix" values="1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0" result="r" />
      <feOffset in="r" dx={amt * 22} result="ro" />
      <feColorMatrix in="d" type="matrix" values="0 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0" result="gb" />
      <feOffset in="gb" dx={-amt * 22} result="gbo" />
      <feBlend in="ro" in2="gbo" mode="screen" />
    </filter>
  </svg>
);

const Streak: React.FC<{ p: number; vertical?: boolean }> = ({ p, vertical }) => {
  const pos = interpolate(p, [0, 1], [-60, 160]);
  return (
    <AbsoluteFill style={{ pointerEvents: "none", mixBlendMode: "screen", opacity: tri(p) }}>
      <AbsoluteFill style={{ background: vertical
        ? `linear-gradient(180deg, transparent ${pos - 18}%, rgba(255,250,235,.9) ${pos}%, transparent ${pos + 18}%)`
        : `linear-gradient(100deg, transparent ${pos - 14}%, rgba(255,250,235,.95) ${pos}%, transparent ${pos + 14}%)`, filter: "blur(10px)" }} />
    </AbsoluteFill>
  );
};

const Leak: React.FC<{ p: number }> = ({ p }) => {
  const x = interpolate(p, [0, 1], [-30, 90]);
  return (
    <AbsoluteFill style={{ pointerEvents: "none", mixBlendMode: "screen", opacity: Math.min(1, tri(p) * 1.4) }}>
      <AbsoluteFill style={{ background: `radial-gradient(ellipse 70% 55% at ${x}% 35%, rgba(255,150,40,.95), rgba(255,60,20,.55) 40%, transparent 70%)` }} />
      <AbsoluteFill style={{ background: `radial-gradient(ellipse 50% 40% at ${100 - x}% 75%, rgba(255,220,120,.8), transparent 65%)` }} />
    </AbsoluteFill>
  );
};

function look(t: Transition, role: "in" | "out", p: number, id: string, frame: number): Look {
  const L: Look = { transform: "", filters: [], opacity: 1 };
  const q = role === "in" ? 1 - p : p; // 0 = settled, 1 = fully transitioned away
  const e = role === "in" ? outE(p) : inE(p);
  switch (t) {
    case "whip":
    case "whip-up": {
      const v = t === "whip-up";
      const off = role === "out" ? -e * 100 : (1 - e) * 100;
      L.transform = v ? `translateY(${off}%)` : `translateX(${off}%)`;
      const mb = tri(p) * 70;
      L.svg = <MotionBlurDef id={id} x={v ? 0 : mb} y={v ? mb : 0} />;
      L.filters.push(`url(#${id})`);
      if (role === "in") L.overlay = <Streak p={p} vertical={v} />;
      break;
    }
    case "zoom": {
      L.transform = role === "out" ? `scale(${1 + e * 0.9})` : `scale(${1 + (1 - e) * 0.6})`;
      L.filters.push(`blur(${tri(p) * 18}px)`);
      if (role === "in") L.opacity = interpolate(p, [0.35, 0.6], [0, 1], clamp);
      break;
    }
    case "dolly": {
      L.transform = role === "out" ? `scale(${1 + e * 2.5})` : `scale(${0.85 + 0.15 * e})`;
      if (role === "out") { L.opacity = 1 - interpolate(p, [0.4, 1], [0, 1], clamp); L.filters.push(`blur(${e * 14}px)`); }
      break;
    }
    case "spin": {
      L.transform = role === "out" ? `rotate(${e * 25}deg) scale(${1 + e * 0.6})` : `rotate(${-(1 - e) * 25}deg) scale(${1 + (1 - e) * 0.6})`;
      L.filters.push(`blur(${tri(p) * 16}px)`);
      if (role === "in") L.opacity = interpolate(p, [0.35, 0.6], [0, 1], clamp);
      break;
    }
    case "flash": {
      L.filters.push(`brightness(${1 + tri(p) * 2.2})`, `blur(${tri(p) * 8}px)`);
      if (role === "in") {
        L.opacity = interpolate(p, [0.45, 0.55], [0, 1], clamp);
        L.transform = `scale(${1 + (1 - e) * 0.06})`;
        L.overlay = <AbsoluteFill style={{ background: "#fff", opacity: interpolate(p, [0.25, 0.5, 1], [0, 0.95, 0], clamp), pointerEvents: "none" }} />;
      }
      break;
    }
    case "lightleak": {
      if (role === "in") { L.opacity = interpolate(p, [0.3, 0.7], [0, 1], { ...clamp, easing: Easing.inOut(Easing.ease) }); L.overlay = <Leak p={p} />; }
      L.filters.push(`brightness(${1 + tri(p) * 0.5})`);
      break;
    }
    case "glitch": {
      const amt = tri(p);
      L.svg = <GlitchDef id={id} amt={amt} seed={frame % 7} />;
      L.filters.push(`url(#${id})`);
      L.transform = `translate(${jitter(id, frame, 30 * amt)}px, ${jitter(`${id}y`, frame, 8 * amt)}px)`;
      if (role === "in") L.opacity = p < 0.5 ? 0 : 1;
      break;
    }
    case "blur": {
      L.filters.push(`blur(${tri(p) * 26}px)`);
      if (role === "in") L.opacity = interpolate(p, [0.2, 0.8], [0, 1], clamp);
      break;
    }
    case "cube": {
      const a = role === "out" ? -e * 90 : (1 - e) * 90;
      L.origin = role === "out" ? "100% 50%" : "0% 50%";
      L.transform = `perspective(1600px) translateX(${role === "out" ? -e * 100 : (1 - e) * 100}%) rotateY(${a}deg)`;
      L.filters.push(`brightness(${1 - q * 0.45})`);
      break;
    }
    case "iris": {
      if (role === "in") {
        const r = interpolate(e, [0, 1], [0, 120]);
        L.clip = `circle(${r}% at 50% 42%)`;
        L.overlay = <AbsoluteFill style={{ pointerEvents: "none", background: `radial-gradient(circle at 50% 42%, transparent ${r * 0.62 - 1}%, rgba(255,255,255,.55) ${r * 0.62}%, transparent ${r * 0.62 + 1.5}%)`, opacity: tri(p) }} />;
      } else L.transform = `scale(${1 + e * 0.12})`;
      break;
    }
    case "swipe": {
      if (role === "in") {
        const x = interpolate(e, [0, 1], [-40, 140]);
        L.clip = `polygon(0 0, ${x}% 0, ${x - 30}% 100%, 0 100%)`;
        L.overlay = <Streak p={p} />;
      } else L.transform = `translateX(${-e * 12}%)`;
      break;
    }
    case "cut":
      break;
  }
  return L;
}

/** Wraps one scene; `pIn`/`pOut` are 0..1 progress of its entry and exit transitions (undefined outside them). */
export const TransitionWrap: React.FC<{ inT: Transition; outT: Transition; pIn?: number; pOut?: number; id: string; frame: number; shake?: number; children: React.ReactNode }> = ({ inT, outT, pIn, pOut, id, frame, shake = 0, children }) => {
  const a = pIn !== undefined && pIn < 1 ? look(inT, "in", pIn, `${id}i`, frame) : null;
  const b = pOut !== undefined && pOut > 0 ? look(outT, "out", pOut, `${id}o`, frame) : null;
  const sx = shake ? jitter(`${id}sx`, frame, shake) : 0;
  const sy = shake ? jitter(`${id}sy`, frame, shake * 0.6) : 0;
  const transform = [shake ? `translate(${sx}px, ${sy}px)` : "", a?.transform ?? "", b?.transform ?? ""].join(" ").trim();
  const filters = [...(a?.filters ?? []), ...(b?.filters ?? [])];
  return (
    <AbsoluteFill>
      {a?.svg}
      {b?.svg}
      <AbsoluteFill
        style={{
          transform: transform || undefined,
          transformOrigin: a?.origin ?? b?.origin ?? "50% 50%",
          filter: filters.length ? filters.join(" ") : undefined,
          opacity: (a?.opacity ?? 1) * (b?.opacity ?? 1),
          clipPath: a?.clip ?? b?.clip,
          background: "#000",
          overflow: "hidden",
        }}
      >
        {children}
      </AbsoluteFill>
      {a?.overlay}
    </AbsoluteFill>
  );
};
