---
name: video-short
description: "Turn a raw talking-head recording into a finished 1080x1920 Short, Reel, or TikTok with B-roll, motion graphics, captions, and music. Shows the plan in chat, then iterates on drafts the user comments on frame by frame. Use when someone wants to edit a raw recording into a vertical video or add captions, B-roll, or motion graphics to one."
---

# Video Short

Input: a raw talking-head recording. Output: `renders/<project>-vN.mp4` at 1080x1920 and 30 fps, a 720p copy in `renders/share/` small enough to send, and the `edit.md` that produced it.

You make every editorial call; the scripts measure, render, and serve the review page. Commands, the `edit.md` format, graphics, and style keys live in [reference.md](reference.md).

## Limba română (this fork)

This copy is set up for Romanian-language Shorts. Talk to the user in Romanian, and write every caption, card, `number:` label, and `graphic:` text in Romanian with full diacritics (ă â î ș ț, comma-below ș and ț, never cedilla ş ţ).

- **Transcription.** `transcribe.py` uses Whisper large-v3-turbo in Romanian by default (`VIDEO_SHORT_LANGUAGE=ro`), which gets Romanian words and diacritics right far more often than Parakeet. Set `VIDEO_SHORT_ENGINE=parakeet` for the faster Parakeet path. Still read the transcript and add `## Caption fixes` for each wrong word, e.g. `- Bucuresti -> București`. Cedilla ş ţ are turned into ș ț automatically.
- **Retakes and fillers.** Besides restarts, drop Romanian hesitations: „ăăă”, „îîî”, „mmm”, and stray „deci”, „gen”, „practic”, „adică”, „bine”, „nu?” when they carry no meaning. Keep them when they are part of the sentence.
- **Captions.** Romanian words run long, so the default style caps captions at 3 words and 22 characters, with bold white text on a dark band and yellow `## Emphasis`. Never split a word, and keep a preposition with its noun („în București”, not „în” alone) when it fits.
- **Numbers.** The style's `locale` is `ro-RO`: write `number: 1.500 lei` or `number: 89,5%`, where `.` groups thousands and `,` marks decimals; it counts up as 1.500 and 89,5. Set `"locale": "en-US"` for English-format numbers.
- **Sources and B-roll.** Prefer Romanian sources (articles, posts, sites) when the topic is local, and receipts in Romanian.
- **Style examples.** The house style is the "signature" look distilled from 10 reference reels in [../exemple/STIL.md](../exemple/STIL.md); read it before planning. For a new reference, run `analyze_ref.py` (below), look at every sheet, and update STIL.md. Borrow how it looks and moves, never its words or footage.

## Stil semnătură (default renderer: Remotion)

Signature Shorts render with the Remotion `Short` composition in `../remotion`, not HyperFrames: it has the kinetic stacked captions, neon titles, card scenes, phone mockup, flash/whip/zoom/glitch transitions, and automatic sound design the references use. Steps 1 (Cut) and 2 (Plan) below are unchanged; instead of `## Scenes` in `edit.md` and `render.py`, write `short.json` in the project and render it:

```bash
R=<skill>/../remotion
node $R/scripts/render-short.mjs "$P" --still=4.2      # one frame -> work/still-4.2.png, to check a moment fast
node $R/scripts/render-short.mjs "$P" --draft          # -> renders/<slug>-vN.mp4 at -14 LUFS + renders/share/ 720p
$S/py $S/qa.py "$P"                                    # same QA as before
$S/py $S/analyze_ref.py ref.mp4 work/ref               # a new reference reel: cuts, audio hits, transcript, frame sheets
```

`short.json` (times in seconds on the clean timeline; words come from `work/transcript_clean.json`; types in `remotion/src/short/types.ts`):

```json
{
  "source": "work/clean.mp4", "accent": "#FFE600",
  "keywords": ["trei", "rapide", "EDIT"],
  "fixes": [["Astă", "Astăzi vă"]],
  "scenes": [
    { "type": "speaker", "start": 0, "end": 3.0, "captions": "right", "focus": [0.5, 0.38] },
    { "type": "speaker", "start": 3.0, "end": 4.9, "in": "zoom", "zoom": 1.25, "captions": "left" },
    { "type": "title", "start": 4.9, "end": 6.4, "in": "flash", "text": "3 trucuri", "number": "3", "label": "Ghid rapid", "script": "simple" },
    { "type": "cards", "start": 6.4, "end": 10.6, "in": "whip", "bg": "paper", "string": true, "items": [{ "src": "broll/a.mp4", "label": "Tăieturi" }] },
    { "type": "phone", "start": 10.6, "end": 14.7, "in": "flash", "flashColor": "#FF8A00", "src": "broll/b.mp4", "title": "Text care se mișcă" },
    { "type": "broll", "start": 14.7, "end": 16.0, "in": "cut", "src": "broll/c.mp4", "from": 2.0 },
    { "type": "number", "start": 16.0, "end": 17.5, "in": "glitch", "value": "1.500 lei", "label": "pe lună" },
    { "type": "speaker", "start": 17.5, "end": 21.0, "in": "zoom", "zoom": 1.1, "captions": "none" }
  ],
  "overlays": [
    { "type": "bookmark", "at": 3.1 },
    { "type": "arrow", "at": 7.6, "dur": 2.5, "x": 0.62, "y": 0.42, "label": "la fiecare secundă" },
    { "type": "eyebox", "at": 1.2, "x": 0.5, "y": 0.3, "w": 0.3, "h": 0.06, "label": "Eu sunt Denis" },
    { "type": "cta", "at": 18.6, "dur": 3.4, "keyword": "EDIT" }
  ],
  "music": { "src": "music.mp3", "volume": 0.1 },
  "grade": { "contrast": 1.08, "saturation": 1.12, "vignette": 0.45, "grain": 0.07 }
}
```

- Scene types: `speaker` (the recording; `zoom` 1.15–1.3 for a punch-in, `focus` = face center), `title` (neon section word), `text3d` (extruded 3D word; slower, renders with SwiftShader), `cards` (1–4 rounded clips/stills on `paper`, `dark`, `light`, `speaker`, or an image; `string` draws a red thread between them), `phone` (mockup that zooms through at the end), `broll` (full-bleed clip with a slow push), `number` (counts up in ro-RO format).
- Scenes must tile the timeline with no gaps. `in` is `cut`, `flash`, `whip`, `zoom`, `glitch`, or `blur`; the previous scene's exit mirrors it.
- `captions` per scene: `left`/`right` stack beside the face (pick the side away from the face), `center`, `lower` (one line, the default on graphic scenes), `none` (titles, CTA). Keywords become the big glowing word and get a pop sound and a zoom kick; choose 1 per sentence at most, the word a viewer should remember.
- Pacing from STIL.md: change something every 0.8–1.5 s; a graphic scene per idea; speaker on screen at least half the time; flash into each section; whip between cards; zoom punch on the speaker every 2–3 s; bookmark in the first 5 s; CTA with the keyword in the last 3–4 s.
- Sound is automatic (`"sfx": "off"` to disable, `"sfxVolume"` to scale): whoosh before flashes and zooms, whip on whips, impact on titles, pop on keywords/cards/rings, ding on the bookmark, riser into the CTA. Sounds live in `remotion/public/sfx` (32 from `@remotion/sfx`, 5 synthesized by `scripts/gen-sfx.mjs`).
- Every `src` path is relative to the project folder. Check stills at each scene change before a full render; a full render of 20 s takes about a minute and a half here.

On first use, run `setup.sh`. If it lists missing tools, tell the user Video Short needs them and offer to install them with the commands it prints. A Gemini API key with billing enabled is optional, for generated images, video, and music. Ask the user to save it in `~/.config/video-short/.env` rather than paste it into chat.

## 1. Cut

Make one folder per Short, named with a short slug, where the user asks, else `projects_dir` from the style file, else the current folder. Leave the recording untouched and point `Source:` at it.

Run `transcribe.py` and read every line of `work/transcript_raw.md`. The transcript keeps ums, stutters, and restarts, so retakes show in the text. When the recording is longer than the Short, such as a full tutorial, first pick its strongest 30 to 60 seconds: cuts can be one or a few ranges from anywhere in the file. Write `## Cuts` in `edit.md`:

- Keep the last complete take of any repeated line. Drop false starts, stray fillers, and dead air.
- Cut between words, never inside one; use the word times in the `.json` for a restart mid-sentence.
- Start about 0.1s before the first word and end about 0.1s after the last. Leave a natural breath after commas and list items. Never speed up the voice.

Run `cut.py --look` and read the gridded stills, taken from the kept footage, for `Framing: x, y`, the face center. A landscape recording crops to vertical around that point. Add `--grade` to compare a subtle ffmpeg grade side by side, or use `Grade: none` when the footage already looks good.

Run `cut.py`, then read `work/transcript_clean.md`. Fix any clipped word or surviving retake and run it again. All scene times use this cut timeline.

## 2. Plan

Ask the user whether they have sources for the Short: the tweets, articles, posts, and demos behind each claim. When they do, their sources drive the visuals, because a viewer can tell when the visuals are what the speaker is actually talking about. When they don't, search online, and have the user confirm the B-roll you found in the plan before you build on it. Then write `## Scenes` in `edit.md`, one row per shot, with start and end on spoken words. When the user shares a reel they like, study it first with contact sheets and cut strips for its pacing, layouts, and transitions; borrow how it moves, never its words or assets.

- **Hook in the first 3 seconds.** Ask whether a viewer would now watch to the end. Open on the hook line with the speaker or the strongest visual, and make it clear with the sound off, since most phone viewers start muted. Plant one question there that the Short answers before it ends. Close on the speaker, and when it fits, bring back the hook's visual so the Short comes full circle.
- **Layouts:** `a-roll` (full-screen speaker), `punch` (tighter speaker for emphasis), `split` (visual on top, speaker below), `b-roll` (visual full screen). For news and commentary, the main visual is a `receipt:` in a split: the cited tweet, article, or page as a clean card, cropped to the lines that matter with the key line marked, held while the speaker discusses it.
- **Keep the speaker present** for at least half the Short, and end each full-screen B-roll shot within about 3.5 seconds, because viewers connect with a face.
- **Visuals show what the words don't:** the product doing the thing, the result, the proof. Captions already carry the words. Show the real product or UI, captured from the actual screen, and mock it up only when the real one isn't available. Never invent numbers or results.
- **Everything off-camera moves.** Real footage first. Otherwise a list card that adds a row per spoken item, a `number:` that counts up to a stat the speaker says, or a `graphic:` you write for anything else, such as a flow or a before and after. Never use a still image as B-roll; an image is only the first frame of a generated video clip, a `page:` capture that scrolls, or a receipt. Skip dim UI panels and waveforms, which lose viewers. When a graphic leads into a clip, end it on the clip's first frame so the cut disappears.
- **Readable and clean.** A graphic fills its panel, with text a viewer can read on a phone at a glance. Never put a card or overlay over the speaker's face.
- **Pace by the kind of Short.** Commentary and news hold each receipt for as long as the speaker discusses it, often 4 to 8 seconds, with plain talking stretches between; constant swaps there read as random. Demos and spoken lists cut faster, around 1 to 2 seconds a shot, giving each named thing its own clip or card row on its spoken word. Either way, put the first visual change within about a second, on the first strong word. Use each clip once.

Find B-roll in this order: the user's sources and own footage, including the screen-share parts of a longer recording, then official demos and the media in posts or launch pages about the topic. Look at frames across every clip's range before proposing it. Reject clips that carry their own captions, kinetic text, or rapid cuts, such as promo videos, since they flash stray words on screen, and any shot that would crop the speaker's face or a line of source text. Use each clip's useful seconds with `@start-end`, and `hold` its last frame instead of letting a short clip loop. Keep every line of on-screen text whole: capture web pages with `capture.py`, which reflows them to phone width, and show them as `page:` drifting down one complete section. When product UI is too small to read, `zoom` into one complete card or field rather than cropping text at the edges. Use footage the user has the right to use. Show a brand's logo only from its official file, never redrawn or generated; without one, write the name.

When the user has a Gemini key and a shot has no good footage, propose generating it: a Nano Banana image, a Gemini Omni Flash video clip, or a Lyria music bed. Generate only what the user approves, because each call costs money.

Add `## Caption fixes` for misspelled names, and `## Emphasis` for the rare term that earns a box in the caption, such as a product name or the main number, so captions stay quiet. For music, use the user's track, a Lyria bed they approve, or none. Lyria sometimes returns slow solo piano, so share a generated bed for a listen and regenerate it if it lacks the groove the user asked for. When the user names a song or artist, describe its genre, tempo, and instruments in the Lyria prompt instead of the name. When the speaker mentions the music, raise it there with `Music lift`. Leave sound effects off unless the user asks.

Show the plan in chat and wait for a go:

- One line per scene: time, layout, what's on screen, and the words spoken.
- Each B-roll clip you found online: its link and what it shows in the seconds you'd use, for the user to keep, swap, or drop.
- What you propose to generate, if anything, and the music.

## 3. Draft and review

Run `render.py --draft`, then `qa.py` on it, and fix failed frame checks before review. Run `review.py` in a persistent shell session and open its printed URL. Verify the moving picture and seeking in the real browser. The server keeps playback available after Send.

Run `review.py --poll WORK` in the foreground and await it while the user reviews; keep the agent turn active so Send delivers notes without another chat prompt. The page shows whether an agent is listening. Read each returned batch and its frames, apply the notes to `edit.md`, render, and rerun `review.py --no-open` with the same project. After verifying the next draft, run `review.py --ack WORK BATCH_ID` and poll again. Keep unacknowledged notes until applied. Repeat until an approval batch arrives. If review pauses, tell the user that later notes remain saved until listening resumes.

## 4. Final

Run `render.py`, then `qa.py`, and fix any failed check. Look at `opening.jpg`, `contact.jpg`, and `cuts/*.jpg` in `work/qa/`:

- Captions never cover the mouth or chin.
- Every cut lands on the right word, with no blank, frozen, or stretched frames.
- Text and clip details are readable at phone size.

You can't hear the mix, so ask the user to listen for music level and clipped words. Run [eval.md](eval.md), then share the video path, duration, and loudness.

## Style

Fonts and colors come from a style file: `--style`, then `style.json` in the project, then `~/.config/video-short/style.json`, then the bundled default. When the user gives a note about the look, offer to save it to their style file so every Short gets it.
