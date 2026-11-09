import { createTikTokStyleCaptions } from "@remotion/captions";
import { loadFont } from "@remotion/google-fonts/Montserrat";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { z } from "zod";

const { fontFamily } = loadFont("normal", { weights: ["900"], subsets: ["latin", "latin-ext"] });

export const hypeCaptionsSchema = z.object({
  words: z.array(z.object({ text: z.string(), startMs: z.number(), endMs: z.number() })),
  highlight: z.string(),
});

// Word-by-word captions: the page pops in, and the spoken word turns the highlight color.
export const HypeCaptions: React.FC<z.infer<typeof hypeCaptionsSchema>> = ({ words, highlight }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const ms = (frame / fps) * 1000;
  const { pages } = createTikTokStyleCaptions({
    captions: words.map((w) => ({ text: ` ${w.text}`, startMs: w.startMs, endMs: w.endMs, timestampMs: null, confidence: null })),
    combineTokensWithinMilliseconds: 900,
  });
  const page = pages.find((p) => ms >= p.startMs && ms < p.startMs + p.durationMs) ?? pages[pages.length - 1];
  const pop = spring({ frame: frame - Math.round((page.startMs / 1000) * fps), fps, config: { damping: 12, stiffness: 220 } });

  return (
    <AbsoluteFill style={{ background: "linear-gradient(160deg,#1e1b4b,#0b0b0d)", justifyContent: "center", alignItems: "center" }}>
      <div style={{ position: "absolute", top: 1250, width: 980, display: "flex", flexWrap: "wrap", justifyContent: "center", columnGap: 44, transform: `scale(${interpolate(pop, [0, 1], [0.6, 1])})` }}>
        {page.tokens.map((t) => {
          const active = ms >= t.fromMs && ms < t.toMs;
          return (
            <span
              key={t.fromMs}
              style={{
                fontFamily, fontWeight: 900, fontSize: 104, textTransform: "uppercase", lineHeight: 1.1,
                color: active ? highlight : "white", WebkitTextStroke: "6px black", paintOrder: "stroke",
                textShadow: "0 8px 24px rgba(0,0,0,.6)", display: "inline-block",
                transform: `scale(${active ? 1.08 : 1})`,
              }}
            >
              {t.text.trim()}
            </span>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};
