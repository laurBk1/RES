// Spec for a "signature" Short, written by the agent as short.json. Times are seconds on the cut (clean) timeline.

export type Transition = "cut" | "flash" | "whip" | "zoom" | "glitch" | "blur";
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

export type Scene = SpeakerScene | TitleScene | Text3DScene | CardsScene | PhoneScene | BrollScene | NumberScene;

export type Overlay =
  | { type: "bookmark"; at: number; dur?: number; text?: string; x?: number; y?: number }
  | { type: "arrow"; at: number; dur?: number; x: number; y: number; label: string; from?: "left" | "right" }
  | { type: "eyebox"; at: number; dur?: number; x: number; y: number; w: number; h: number; label?: string }
  | { type: "pill"; at: number; dur?: number; number?: string; text: string; y?: number }
  | { type: "cta"; at: number; dur?: number; keyword: string; text?: string; quote?: boolean }
  | { type: "views"; at: number; dur?: number; text: string; y?: number }
  | { type: "ring"; at: number; dur?: number; x: number; y: number; r: number };

export type ShortProps = {
  /** Paths are relative to the project folder. */
  source: string;
  duration: number;
  words: Word[];
  scenes: Scene[];
  overlays?: Overlay[];
  /** Words or phrases styled as big glowing keywords. */
  keywords?: string[];
  accent?: string;
  music?: { src: string; volume?: number };
  sfx?: "auto" | "off";
  sfxVolume?: number;
  /** tint: a color laid over in soft-light, e.g. "#0f6b73" for a teal cinematic cast. */
  grade?: { contrast?: number; saturation?: number; brightness?: number; vignette?: number; grain?: number; tint?: string; tintAmount?: number };
  locale?: string;
};
