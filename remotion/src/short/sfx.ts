import kit from "./sfx-kit.json";

export type Sfx = { src: string; sync: number; gain: number };

const kinds = kit.kinds as unknown as Record<string, [string, string, number, number][]>;

/** A sound of `kind` from the curated sfx-kit set (public/sfx/kit), rotating siblings by `seed` so repeats vary. */
export function pickSfx(kind: string, seed = 0): Sfx | null {
  const list = kinds[kind];
  if (!list?.length) return null;
  const [id, , sync, vo] = list[seed % list.length];
  // Talking-head shorts have speech nearly everywhere, so the kit's under-voiceover trim always applies.
  return { src: `kit/${id}.wav`, sync, gain: Math.pow(10, vo / 20) };
}

export const kitFiles = () => Object.values(kinds).flat().map(([id, file]) => ({ id, file }));
