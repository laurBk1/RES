import React from "react";
import { Easing, interpolate, random, staticFile } from "remotion";

/** A scene's own length in frames, excluding the tail it keeps playing under the next scene's entry transition. */
export const CoreDur = React.createContext(30);
export const useCoreDur = () => React.useContext(CoreDur);

export const FPS = 30;
export const W = 1080;
export const H = 1920;
export const f = (s: number) => Math.round(s * FPS);

/** Project files live under public/p (a link to the project folder made by render-short.mjs). */
export const asset = (src: string) => (/^https?:/.test(src) ? src : staticFile(`p/${src.replace(/^\.?\//, "")}`));
export const isVideo = (src: string) => /\.(mp4|mov|webm|m4v)$/i.test(src);

export const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
export const easeOut = Easing.bezier(0.16, 1, 0.3, 1);

export const norm = (t: string) => t.toLowerCase().normalize("NFC").replace(/[^\p{L}\p{N}%$€.]+/gu, "").replace(/\.$/, "");

export const glow = (c: string, k = 1) => `0 0 ${14 * k}px ${c}AA, 0 0 ${36 * k}px ${c}66`;
export const darkShadow = "0 4px 18px rgba(0,0,0,.65), 0 2px 4px rgba(0,0,0,.5)";

/** 0 -> 1 pop progress for an element appearing at frame `at`. */
export const pop = (frame: number, at: number, len = 6) => interpolate(frame, [at, at + len], [0, 1], { ...clamp, easing: easeOut });

/** Deterministic per-frame jitter, for shakes and glitches. */
export const jitter = (seed: string, frame: number, amp: number) => (random(`${seed}-${frame}`) * 2 - 1) * amp;
