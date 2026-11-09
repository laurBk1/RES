import { Audio } from "@remotion/media";
import { linearTiming, springTiming, TransitionSeries } from "@remotion/transitions";
import { slide } from "@remotion/transitions/slide";
import { wipe } from "@remotion/transitions/wipe";
import { AbsoluteFill, Sequence, staticFile } from "remotion";
import { HypeCaptions } from "./HypeCaptions";
import { Text3DTitle } from "./Text3DTitle";

// Smoke test for the toolchain: 3D title -> slide -> captions -> wipe -> 3D title, with SFX on each cut.
export const HypeDemo: React.FC = () => (
  <AbsoluteFill style={{ background: "#0b0b0d" }}>
    <TransitionSeries>
      <TransitionSeries.Sequence durationInFrames={60}>
        <Text3DTitle text="ȘOCANT!" color="#FACC15" background="radial-gradient(circle,#312e81,#0b0b0d)" />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={slide({ direction: "from-bottom" })} timing={springTiming({ config: { damping: 200 }, durationInFrames: 12 })} />
      <TransitionSeries.Sequence durationInFrames={75}>
        <HypeCaptions
          highlight="#FACC15"
          words={[
            { text: "Trei", startMs: 0, endMs: 400 },
            { text: "trucuri", startMs: 400, endMs: 900 },
            { text: "care", startMs: 900, endMs: 1150 },
            { text: "îți", startMs: 1150, endMs: 1400 },
            { text: "dublează", startMs: 1400, endMs: 2000 },
            { text: "vânzările", startMs: 2000, endMs: 2500 },
          ]}
        />
      </TransitionSeries.Sequence>
      <TransitionSeries.Transition presentation={wipe({ direction: "from-left" })} timing={linearTiming({ durationInFrames: 10 })} />
      <TransitionSeries.Sequence durationInFrames={60}>
        <Text3DTitle text="ÎNCEARCĂ!" color="#F472B6" background="radial-gradient(circle,#831843,#0b0b0d)" />
      </TransitionSeries.Sequence>
    </TransitionSeries>
    <Audio src={staticFile("sfx/whoosh.wav")} volume={0.7} />
    <Sequence from={52}><Audio src={staticFile("sfx/whip.wav")} volume={0.6} /></Sequence>
    <Sequence from={117}><Audio src={staticFile("sfx/vine-boom.wav")} volume={0.5} /></Sequence>
  </AbsoluteFill>
);
