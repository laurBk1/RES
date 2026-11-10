# SOURCES — proveniența materialului copiat (vendored)

Data copierii: 2026-11-10. Fișierele sunt copii text fără modificări (fără media/binare, fără fișiere > 500 KB),
iar LICENSE-ul fiecărei surse se află lângă material.

| Folder în `skills/` | Repo sursă | Commit | Licență | Ce s-a copiat |
|---|---|---|---|---|
| `hyperframes/` | https://github.com/heygen-com/hyperframes | `651de1d948b0f619001e3705cba98fa415baf0dd` | Apache-2.0 | `skills/{hyperframes,hyperframes-cli,hyperframes-registry,media-use,remotion-to-hyperframes,reverse-any-video,slideshow,style-sampling,figma}` (fără mp3) |
| `herk-edit-kit/` | https://github.com/nateherkai/herk-edit-kit | `10511e5af86fc47756ea89803b397422e2d89284` | MIT (LICENSE) + `licenses/PIPELINE-USE-PERMISSION.txt` + Apache-2.0 pentru HyperFrames (`licenses/HYPERFRAMES-LICENSE`) | `.claude/skills/*` (15), `MOTION_PHILOSOPHY.md`, `docs/EDITING-PLAYBOOK.md`, `THIRD_PARTY_NOTICES.md`, `licenses/` |
| `motion-kit/` | https://github.com/hughminhphan/motion-kit | `6173e5c408f81f1989435843af3f0788b74bda96` | MIT | `skills/motion-designer` |
| `video-use/` | https://github.com/browser-use/video-use | `43cfc566833548093455c9d4a46bd69913b7e552` | MIT | `SKILL.md`, `install.md`, `helpers/`, `skills/manim-video` |
| `master-skills/` | https://github.com/Jakeschincariol/master-skills | `b5b43e44f0a976ad25bda5095a94c161aab2f086` | MIT | `skills/{build,edit,virality}` |
| `video-director/` | https://github.com/win4r/video-director | `02d1912ab251bf5235b45e8e7aad81b4bc786b15` | MIT | `video-director/` (text), `METHODOLOGY.md` |
| `claude-video-skills/` | https://github.com/Neelshah1810/Claude-Video-Skills | `d1645496774ce9af5941f3c410d75b1bf43e4fcb` | MIT | cele 11 skill-uri (text, exemple HTML < 500 KB) |
| `claude-code-video-toolkit/` | https://github.com/digitalsamba/claude-code-video-toolkit | `56654e4f0255ec5134655bdf41ab6e9bfb7a8f7b` | MIT | `.claude/skills/*` fără `remotion-official`, plus `skills/video-toolkit` |
| `remotion-transitions-digitalsamba/` | https://github.com/digitalsamba/claude-code-video-toolkit | `56654e4f0255ec5134655bdf41ab6e9bfb7a8f7b` | MIT | `lib/transitions/` |
| `remotion-scenes/` | https://github.com/lifeprompt-team/remotion-scenes | `02c7a84241da7010b5f59c420b0110aafd1d6f0d` | MIT | `src/scenes/` (surse text, ~750 KB) |
| `claude-video-editor-plugin/` | https://github.com/danielrosehill/Claude-Video-Editor-Plugin | `dd47c741c91370b80f2d195d3dd44c03805dcaa3` | MIT | `skills/` (40) |
| `ai-video-skill/` | https://github.com/TimoteoAltobrando/ai-video-skill | `c6ecf8a66829dd39f600172506bef8206513236a` | MIT | SKILL.md, references/, scripts/ |
| `jsath-claude-skills/` | https://github.com/jsath/claude-skills | `5f935e21c9cef2baf6106e6742e0fdd56f51ec78` | MIT | doar `skills/video/*` (12) |

## Omise intenționat
- `digitalsamba/claude-code-video-toolkit/.claude/skills/remotion-official` — copie a skill-urilor Remotion oficiale (remotion-dev/skills, fără licență declarată); instalează direct de la sursă.
- Repo-uri fără licență (NONE/NOASSERTION), doar indexate în README: remotion-dev/skills, av/remotion-bits, reactvideoeditor/remotion-templates, maxazure/video-editing-skill, andchir/remotion-animations, nishaj0/claude-for-everything, zhuyansen/awesome-claude-video-skills, naomimetzger/cookbook.
- Prea mari pentru copiere: sunsiyuan/ultramotion (~444 MB), Agentchengfeng/chengfeng-videocut-skills (~67 MB).
- Doar indexate: degueba/onda, neutral-Stage/remotion-captioneer, stefanwittwer/remotion-animated, wyzowl/sfx-kit.
- Din herk-edit-kit nu s-au copiat `examples/`, `video-projects/`, `assets/`, `style-library/`, `style-templates/` (media, brand AIS necedat pentru reutilizare).
