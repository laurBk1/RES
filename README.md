# Video Short (română)

Variantă a [petergyang/video-short](https://github.com/petergyang/video-short) (licență MIT) adaptată pentru clipuri în limba română: transcrie înregistrarea, taie bâlbele și pauzele și scoate un Short vertical 1080×1920 cu subtitrări clare, motion graphics, B-roll și muzică.

## Structură

- `skill/`: skill-ul (instrucțiuni în `SKILL.md`, comenzi în `reference.md`, scripturi în `scripts/`).
- `exemple/`: clipuri de referință pentru stil.
- `proiecte/`: câte un folder pentru fiecare Short (înregistrarea brută, `edit.md`, randările).
- `skills/`: 110 skill-uri de editare video, motion graphics, tranziții și sunet, copiate cu licențele lor (vezi `skills/README.md`).

## Ce s-a schimbat față de original

- Diacriticele cu sedilă (ş ţ) din transcriere devin automat ș ț corecte.
- Numerele animate folosesc formatul românesc (`1.500`, `89,5%`), prin cheia `locale` din stil.
- Stilul implicit are subtitrări bold, cu fundal închis, maximum 3 cuvinte pe ecran și evidențiere galbenă.
- `SKILL.md` are reguli pentru română: diacritice, ezitări tipice („ăăă”, „deci”, „gen”), corecturi de subtitrare și analiza clipurilor din `exemple/`.

## Cum se folosește

```text
/video-short editează clipul proiecte/<nume>/raw.mp4
```

Prima rulare are nevoie de ffmpeg, yt-dlp, Python 3.10+, Node 22+ și de modelul Parakeet (circa 1 GB). Vezi `skill/scripts/setup.sh`.
