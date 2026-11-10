import { Composition } from "remotion";
import { HypeCaptions, hypeCaptionsSchema } from "./HypeCaptions";
import { HypeDemo } from "./HypeDemo";
import { calcShort, Short } from "./short/Short";
import type { ShortProps } from "./short/types";

const emptyShort: ShortProps = { source: "work/clean.mp4", duration: 1, words: [], scenes: [{ type: "speaker", start: 0, end: 1 }] };

export const Root: React.FC = () => (
  <>
  <Composition id="Short" component={Short} width={1080} height={1920} fps={30} durationInFrames={30} defaultProps={emptyShort} calculateMetadata={calcShort} />
  <Composition id="HypeDemo" component={HypeDemo} width={1080} height={1920} fps={30} durationInFrames={173} />
  <Composition
    id="HypeCaptions"
    component={HypeCaptions}
    width={1080}
    height={1920}
    fps={30}
    durationInFrames={90}
    schema={hypeCaptionsSchema}
    defaultProps={{
      words: [
        { text: "Știați", startMs: 0, endMs: 450 },
        { text: "că", startMs: 450, endMs: 700 },
        { text: "500.000", startMs: 700, endMs: 1400 },
        { text: "de", startMs: 1400, endMs: 1600 },
        { text: "români", startMs: 1600, endMs: 2200 },
        { text: "cumpără", startMs: 2200, endMs: 2600 },
        { text: "online?", startMs: 2600, endMs: 3000 },
      ],
      highlight: "#FACC15",
    }}
  />
  </>
);
