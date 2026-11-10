// Synthesize the short accent sounds that @remotion/sfx lacks, into public/sfx. No licensing: they are made here.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const dir = path.join(process.cwd(), "public", "sfx");
fs.mkdirSync(dir, { recursive: true });

// aevalsrc expressions, 48 kHz stereo; t is seconds.
const sounds = {
  // Short pitched-down blip for words and cards appearing.
  "pop.wav": { d: 0.09, e: "0.8*sin(2*PI*(900*t-3500*t*t))*exp(-45*t)" },
  // Sub drop plus noise crack for section titles and the hook.
  "impact.wav": { d: 0.9, e: "0.9*sin(2*PI*(70*t-25*t*t))*exp(-4.5*t)+0.35*(random(0)*2-1)*exp(-30*t)" },
  // Rising filtered noise into a reveal.
  "riser.wav": { d: 1.2, e: "0.5*(random(0)*2-1)*pow(t/1.2,2)+0.25*sin(2*PI*(200*t+300*t*t))*pow(t/1.2,3)", af: "highpass=f=400,lowpass=f=6000" },
  // Tiny click for typewriter text and UI.
  "tick.wav": { d: 0.03, e: "0.6*(random(0)*2-1)*exp(-200*t)", af: "highpass=f=2000" },
  // Airy swish that is softer than whoosh.wav, for card slides.
  "swish.wav": { d: 0.35, e: "0.6*(random(0)*2-1)*sin(PI*t/0.35)", af: "highpass=f=1200,lowpass=f=5000,volume=6dB" },
};

for (const [name, s] of Object.entries(sounds)) {
  const filters = [s.af, "alimiter=limit=0.7"].filter(Boolean).join(",");
  execFileSync("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", `aevalsrc='${s.e}':s=48000:d=${s.d}:c=stereo`, "-af", filters, path.join(dir, name)]);
}
console.log(`${Object.keys(sounds).length} synthesized sounds in public/sfx`);
