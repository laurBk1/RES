// Spec for a "signature" Short, written by the agent as short.json. Times are seconds on the cut (clean) timeline.

export type Transition = "cut" | "flash" | "whip" | "whip-up" | "zoom" | "glitch" | "blur" | "lightleak" | "cube" | "iris" | "swipe" | "spin" | "dolly";
export type CaptionPos = "left" | "right" | "center" | "lower" | "upper" | "none";

export type Word = { text: string; start: number; end: number };

type Base = {
  start: number;
  end: number;
  /** How this scene enters. The previous scene's exit mirrors it. */
  in?: Transition;
  /** Flash color when in = "flash". */
  flashColor?: string;
  captions?: CaptionPos;
};

export type SpeakerScene = Base & {
  type: "speaker";
  /** 1 = full frame, 1.25 = punch-in. */
  zoom?: number;
  /** Face center as fractions of the frame, the zoom origin. */
  focus?: [number, number];
  /** Alternate footage on the same timeline, e.g. a pre-cropped close-up of the source. */
  src?: string;
  /** Fade the frame to black from this height (fraction) down: hides burned-in text and gives captions a dark bed. */
  fade?: number;
};
export type TitleScene = Base & { type: "title"; text: string; number?: string; label?: string; script?: string };
export type Text3DScene = Base & { type: "text3d"; text: string; color?: string };
export type CardsScene = Base & {
  type: "cards";
  bg?: "paper" | "dark" | "light" | "speaker" | string;
  items: { src: string; label?: string; from?: number }[];
  string?: boolean;
};
export type PhoneScene = Base & { type: "phone"; src?: string; from?: number; title?: string; bg?: "light" | "dark" };
export type BrollScene = Base & { type: "broll"; src: string; from?: number };
export type NumberScene = Base & { type: "number"; value: string; label?: string };
/** Liquid-glass list card; each item reveals when its first word is spoken (or evenly if not found). */
export type GlassScene = Base & { type: "glass"; title?: string; items: string[]; bg?: string };
/** Chrome kinetic title over a receding perspective grid with sparkles and a light beam. */
export type GridScene = Base & { type: "grid"; text: string; sub?: string };
/** B-roll on top, speaker on the bottom (or swapped), split by a glowing seam. */
export type SplitScene = Base & { type: "split"; src: string; from?: number; speakerTop?: boolean; focus?: [number, number] };
/** Speaker inside a glowing rounded card over a blurred copy, with tag chips around it. */
export type PipScene = Base & { type: "pip"; tags?: string[]; label?: string; focus?: [number, number] };

export type Scene = SpeakerScene | TitleScene | Text3DScene | CardsScene | PhoneScene | BrollScene | NumberScene | GlassScene | GridScene | SplitScene | PipScene;

export type Overlay =
  | { type: "bookmark"; at: number; dur?: number; text?: string; x?: number; y?: number }
  | { type: "arrow"; at: number; dur?: number; x: number; y: number; label: string; from?: "left" | "right" }
  | { type: "eyebox"; at: number; dur?: number; x: number; y: number; w: number; h: number; label?: string }
  | { type: "pill"; at: number; dur?: number; number?: string; text: string; y?: number }
  | { type: "cta"; at: number; dur?: number; keyword: string; text?: string; quote?: boolean }
  | { type: "views"; at: number; dur?: number; text: string; y?: number }
  | { type: "ring"; at: number; dur?: number; x: number; y: number; r: number }
  /** A giant extruded word that slams in at the center and dollies through the camera; captions pause meanwhile. */
  | { type: "bigword"; at: number; dur?: number; text: string; color?: string }
  /** A warm light leak sweeping across the frame. */
  | { type: "lightleak"; at: number; dur?: number };

export type ShortProps = {
  /** Paths are relative to the project folder. */
  source: string;
  duration: number;
  words: Word[];
  scenes: Scene[];
  overlays?: Overlay[];
  /** Words or phrases styled as big glowing keywords. */
  keywords?: string[];
  /** "3d" (default): one line, words flip in with depth and extrusion; "box": the spoken word sits on an accent pill; "stack": stacked lines beside the face. */
  captionStyle?: "3d" | "box" | "stack";
  accent?: string;
  music?: { src: string; volume?: number };
  sfx?: "auto" | "off";
  sfxVolume?: number;
  /** tint: a color laid over in soft-light, e.g. "#0f6b73" for a teal cinematic cast. */
  grade?: { contrast?: number; saturation?: number; brightness?: number; vignette?: number; grain?: number; tint?: string; tintAmount?: number };
  locale?: string;
};
