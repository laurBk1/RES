# skills/ — set de skill-uri pentru editare video scurt

Un folder cu skill-uri pentru agenți (Claude Code, Codex) care acoperă editarea video, motion graphics, subtitrări, tranziții și sunet. Fiecare skill este un director cu `SKILL.md`; le poți copia în `~/.claude/skills/` sau le poți folosi direct din repo. Materialul copiat (vendored) păstrează licența sursei lângă el; proveniența completă (repo, commit, licență, dată) este în [SOURCES.md](SOURCES.md). Stelele GitHub au fost citite la 2026-11-10.

Notă: repo-urile fără licență nu au fost copiate — apar doar ca link, cu comandă de instalare.

## Editare end-to-end

| Nume | GitHub | Stele | Licență | Vendored | Ce face |
|---|---|---|---|---|---|
| hyperframes (skills) | [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) | 81690 | Apache-2.0 | da — `hyperframes/` (9 skill-uri) | Video din HTML/GSAP: compoziții, CLI, registry, media, slideshow, Figma, Remotion→HyperFrames |
| herk-edit-kit | [nateherkai/herk-edit-kit](https://github.com/nateherkai/herk-edit-kit) | 2693 | MIT + permisiune pipeline | da — `herk-edit-kit/` (15 skill-uri) | Pipeline complet: tăiat liniști/greșeli, short-form, storytelling, showreel, ghid de montaj |
| video-use | [browser-use/video-use](https://github.com/browser-use/video-use) | 30826 | MIT | da — `video-use/` (2) | Editare video prin conversație: tăieturi, grading, subtitrări, overlay-uri animate |
| master-skills | [Jakeschincariol/master-skills](https://github.com/Jakeschincariol/master-skills) | 170 | MIT | da — `master-skills/` (3) | `/edit` taie pauzele, subtitrări de 1–3 cuvinte, vizuale dinamice; `/build`, `/virality` |
| video-director | [win4r/video-director](https://github.com/win4r/video-director) | 425 | MIT | da — `video-director/` (1) | Regie video în pași, cu QA și principii anti-„generic” |
| Claude-Video-Skills | [Neelshah1810/Claude-Video-Skills](https://github.com/Neelshah1810/Claude-Video-Skills) | 17 | MIT | da — `claude-video-skills/` (11) | Lansări, explainere, reclame sociale, data stories, tutoriale (HTML + MP4) |
| claude-code-video-toolkit | [digitalsamba/claude-code-video-toolkit](https://github.com/digitalsamba/claude-code-video-toolkit) | 2495 | MIT | da — `claude-code-video-toolkit/` (15) | Remotion, ffmpeg, moviepy, ElevenLabs, design video, înregistrări Playwright |
| Claude-Video-Editor-Plugin | [danielrosehill/Claude-Video-Editor-Plugin](https://github.com/danielrosehill/Claude-Video-Editor-Plugin) | 6 | MIT | da — `claude-video-editor-plugin/` (40) | Skill-uri modulare: auto-cut, burn-subtitles, normalize-audio, karaoke, render profiles |
| ai-video-skill | [TimoteoAltobrando/ai-video-skill](https://github.com/TimoteoAltobrando/ai-video-skill) | 5 | MIT | da — `ai-video-skill/` (1) | De la idee la livrare: ad-uri, Reels/Shorts, lyric videos, pe Remotion |
| jsath/claude-skills (video) | [jsath/claude-skills](https://github.com/jsath/claude-skills) | 16 | MIT | da — `jsath-claude-skills/` (12, doar categoria video) | Reels, caption-engine, raw-to-reel, longform, podcast repurpose |
| chengfeng-videocut-skills | [Agentchengfeng/chengfeng-videocut-skills](https://github.com/Agentchengfeng/chengfeng-videocut-skills) | 3196 | Apache-2.0 | nu (67 MB) | Agent de montaj pentru talking-head (vloguri, tutoriale) |
| video-editing-skill | [maxazure/video-editing-skill](https://github.com/maxazure/video-editing-skill) | 209 | fără licență | nu | Workflow voice-over/talking-head, chroma key, B-roll, subtitrări |
| cookbook | [naomimetzger/cookbook](https://github.com/naomimetzger/cookbook) | 10 | fără licență (NOASSERTION) | nu | „Rețete” de editare instalabile ca skill-uri |

## Motion graphics & animații

| Nume | GitHub | Stele | Licență | Vendored | Ce face |
|---|---|---|---|---|---|
| motion-kit | [hughminhphan/motion-kit](https://github.com/hughminhphan/motion-kit) | 31 | MIT | da — `motion-kit/` | Curbe per mișcare, timing după distanță, reacții în loc de stagger (GSAP/HyperFrames) |
| remotion-scenes | [lifeprompt-team/remotion-scenes](https://github.com/lifeprompt-team/remotion-scenes) | 68 | MIT | da — `remotion-scenes/scenes/` | 201+ scene Remotion: text, forme, efecte (grain, VHS, glitch), UI, particule |
| Onda | [degueba/onda](https://github.com/degueba/onda) | 31 | MIT | nu | 70 componente + 18 tranziții Remotion; instalare: `npx ondajs add <componentă>` |
| ultramotion | [sunsiyuan/ultramotion](https://github.com/sunsiyuan/ultramotion) | 9 | MIT | nu (444 MB) | 90 efecte, 65 șabloane, 21 motoare; `npx skills add sunsiyuan/ultramotion` |
| remotion-animated | [stefanwittwer/remotion-animated](https://github.com/stefanwittwer/remotion-animated) | 227 | MIT | nu | Animarea obiectelor în Remotion; `npm i remotion-animated` |
| remotion-dev/skills | [remotion-dev/skills](https://github.com/remotion-dev/skills) | 6725 | fără licență | nu | Skill-uri Remotion oficiale; `npx skills add remotion-dev/skills` |
| remotion-bits | [av/remotion-bits](https://github.com/av/remotion-bits) | 513 | fără licență | nu | Efecte de text, tranziții, particule, 3D, MCP |
| remotion-templates | [reactvideoeditor/remotion-templates](https://github.com/reactvideoeditor/remotion-templates) | 288 | fără licență | nu | 81 șabloane: charts, text animat, fundaluri, secvențe cinematice |
| remotion-animations | [andchir/remotion-animations](https://github.com/andchir/remotion-animations) | 4 | fără licență | nu | Animații gata făcute: lower thirds, text reveals |

## Tranziții

| Nume | GitHub | Stele | Licență | Vendored | Ce face |
|---|---|---|---|---|---|
| remotion-transitions-digitalsamba | [digitalsamba/claude-code-video-toolkit](https://github.com/digitalsamba/claude-code-video-toolkit/tree/main/lib/transitions) | 2495 | MIT | da — `remotion-transitions-digitalsamba/` | glitch, rgbSplit, zoomBlur, lightLeak, clockWipe, pixelate, checkerboard pentru `@remotion/transitions` |
| HyperFrames registry | [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) | 81690 | Apache-2.0 | skill-ul `hyperframes/hyperframes-registry/` | Blocuri/tranziții instalabile: `npx hyperframes add <nume>` |
| Onda (tranziții) | [degueba/onda](https://github.com/degueba/onda) | 31 | MIT | nu | 18 tranziții Remotion |

## Subtitrări

| Nume | GitHub | Stele | Licență | Vendored | Ce face |
|---|---|---|---|---|---|
| remotion-captioneer | [neutral-Stage/remotion-captioneer](https://github.com/neutral-Stage/remotion-captioneer) | 19 | MIT | nu | 14 stiluri de subtitrări animate cuvânt cu cuvânt (karaoke, highlight, typewriter) |
| caption-engine / reel-captions | [jsath/claude-skills](https://github.com/jsath/claude-skills) | 16 | MIT | da — `jsath-claude-skills/` | Skill-uri de subtitrări pentru reels |
| master-skills `/edit` | [Jakeschincariol/master-skills](https://github.com/Jakeschincariol/master-skills) | 170 | MIT | da — `master-skills/edit` | Subtitrări dinamice de 1–3 cuvinte |
| burn-subtitles | [danielrosehill/Claude-Video-Editor-Plugin](https://github.com/danielrosehill/Claude-Video-Editor-Plugin) | 6 | MIT | da — `claude-video-editor-plugin/burn-subtitles` | Arde subtitrări în video cu ffmpeg |

## Sunet

| Nume | GitHub | Stele | Licență | Vendored | Ce face |
|---|---|---|---|---|---|
| sfx-kit | [wyzowl/sfx-kit](https://github.com/wyzowl/sfx-kit) | 31 | CC0-1.0 | nu (renderer-ul din `../remotion` îl descarcă la setup) | 320 efecte sonore cu metadate pentru selecție automată |
| elevenlabs / acestep | [digitalsamba/claude-code-video-toolkit](https://github.com/digitalsamba/claude-code-video-toolkit) | 2495 | MIT | da — `claude-code-video-toolkit/{elevenlabs,acestep}` | Voce, SFX și muzică generate |
| normalize-audio | [danielrosehill/Claude-Video-Editor-Plugin](https://github.com/danielrosehill/Claude-Video-Editor-Plugin) | 6 | MIT | da — `claude-video-editor-plugin/normalize-audio` | Normalizare audio |

## Liste comunitare

| Nume | GitHub | Stele | Licență | Vendored | Ce face |
|---|---|---|---|---|---|
| awesome-claude-video-skills | [zhuyansen/awesome-claude-video-skills](https://github.com/zhuyansen/awesome-claude-video-skills) | 1829 | NOASSERTION | nu | ~180 repo-uri cu skill-uri video, grupate pe categorii |
| claude-for-everything | [nishaj0/claude-for-everything](https://github.com/nishaj0/claude-for-everything) | 28 | fără licență | nu | Skill-uri, plugin-uri și MCP: editing, motion graphics, sunet, 3D |

## Instalare în Claude Code

```bash
# Claude Code (un singur skill)
cp -r skills/herk-edit-kit/short-form-edit ~/.claude/skills/
cp -r skills/master-skills/edit ~/.claude/skills/

# Codex
cp -r skills/hyperframes/hyperframes ~/.agents/skills/

# Skill-uri externe (fără licență, neincluse)
npx skills add remotion-dev/skills
```

Pentru a instala tot un grup: `cp -r skills/hyperframes/*/ ~/.claude/skills/` (doar directoarele cu `SKILL.md`; ignoră `LICENSE`/`NOTICE`, dar păstrează-le dacă redistribui).

Note:
- Skill-urile care folosesc HyperFrames necesită `npx hyperframes@<versiune>` (Node ≥ 22 și ffmpeg); verifică versiunea cerută în `SKILL.md`.
- Skill-urile și componentele Remotion (`remotion-transitions-digitalsamba`, `remotion-scenes`, `claude-code-video-toolkit/remotion`) se folosesc cu proiectul din `../remotion`.
- `herk-edit-kit` include copii ale skill-urilor HyperFrames/GSAP (Apache-2.0, vezi `herk-edit-kit/licenses/`); la conflict de nume, alege una singură dintre versiunile `hyperframes`.
- Nu am rulat skill-urile; au fost copiate așa cum sunt în sursă.
