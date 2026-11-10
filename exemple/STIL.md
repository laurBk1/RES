# Stilul semnătură: analiza celor 10 clipuri de referință

Analiză cadru cu cadru (foi de cadre la 0,5 s, benzi în jurul fiecărei tăieturi, momentele cu efecte sonore detectate din sunet, transcriere Whisper), făcută cu `skill/scripts/analyze_ref.py`. Clipurile nu sunt în repository, pentru că aparțin creatorilor lor. Copiem doar limbajul vizual, nu textul și nici filmările.

| Clip | Creator | Durată | Tăieturi | Durata medie a unui cadru | Efecte audio |
|---|---|---|---|---|---|
| DehkOI3qX6d | Zache Seno | 44,8 s | 40 | 1,1 s | 28 |
| Dc1UHyaRheW | Zache Seno | 38,8 s | 33 | 1,1 s | 13 |
| DcjQ_P2Rj2D | Zache Seno | 34,3 s | 29 | 1,1 s | 35 |
| Dd4PxCiqVlg | Zache Seno (sound design) | 58,5 s | 26 | 2,2 s | 29 |
| DdI3BDbKamQ | Zache Seno (B-roll) | 34,4 s | 17 | 1,9 s | 16 |
| Dehjq7QqHeo | Zache Seno (fisheye) | 51,7 s | 19 | 2,6 s | 15 |
| DeJ8N6lIaLm | Adam Kelada (hooks) | 49,6 s | 14 | 3,3 s | 79 |
| DfAKqHUMPS7 | Aslan (motion design) | 47,3 s | 16 | 2,8 s | 61 |
| Dd1Mf7xzsbm | Barsol Media | 26,8 s | 36 | 0,7 s | 27 |
| DfFQiNCT8Lj | Barsol Media | 42,1 s | 28 | 1,5 s | 50 |

## Ce au în comun

1. **Ritm:** o schimbare vizuală (tăietură, zoom, grafică nouă) la fiecare 0,8–1,5 s. Puțin mai rar în explicații, iar la hook și la CTA vin 2–3 tăieturi foarte apropiate.
2. **Hook fără titlu static:** subtitrările se mișcă deja din primul cadru. Prima frază e o întrebare sau un „deci…”, iar până la ~2,5 s apare primul element grafic sau primul flash.
3. **Subtitrări cinetice, nu bandă de subtitrare:** 1–3 cuvinte pe rând, 2–4 rânduri stivuite **lângă** vorbitor (stânga sau dreapta feței, niciodată peste ea). Cuvintele normale sunt grotesk bold, alb, cu umbră moale. Cuvintele-cheie sunt condensed ultra-bold, MAJUSCULE, de ~1,7× mai mari, galben `#FFE600` cu glow. Intrarea: blur 12 px → clar, scale 0,78 → 1 și o ridicare de ~26 px, în ~6 cadre. Ieșirea: blur și micșorare în 4 cadre.
4. **O singură culoare de brand** (galben la Zache și Adam, roșu la Aslan și Barsol), folosită pentru cuvinte-cheie, glow, contururi neon, săgeți și inele.
5. **Fiecare idee rostită primește o scenă grafică** de 1,5–3 s:
   - carduri video rotunjite pe hârtie sau hartă, cu etichete pill albe și fir roșu între ele;
   - mockup de telefon cu zoom prin ecran;
   - titlu de secțiune neon (contur galben strălucitor), cu pill numerotat și un cuvânt scris de mână;
   - număr care crește.
6. **Indicatori desenați:** săgeată galbenă punctată, curbată, cu etichetă scrisă de mână; chenar galben rotit pe față („eye box”); inel galben în jurul subiectului; iconiță de bookmark „Salvează clipul” în primele ~5 s.
7. **Tranziții:**
   - flash alb, portocaliu sau galben de 3 cadre la intrare și 6 la ieșire, la schimbarea secțiunii;
   - whip lateral cu motion blur de 5 cadre între carduri;
   - zoom punch 1,15–1,3× pe vorbitor;
   - glitch RGB de 5 cadre, rar;
   - tăieturi seci pe B-roll, pe silaba cuvântului.
8. **Camera virtuală:** push lent de 1,00 → 1,05 în fiecare cadru și un „kick” de +5% pe cuvintele-cheie.
9. **Look:** contrast ridicat, saturație puțin crescută, highlights calde, vignetă, grain fin.
10. **Sunet:** whoosh pe fiecare mișcare (flash, zoom), whip pe whip, impact grav pe titluri, pop scurt pe cuvinte-cheie și carduri, ding pe bookmark, riser în CTA. Dd4PxCiqVlg adaugă regula: un ambient discret dedesubt, foley pe mișcare, un singur accent pe momentul important.
11. **CTA:** „Comentează „CUVÂNT” și îți trimit…”, cu cuvântul uriaș, galben, cu glow. Se încheie pe vorbitor.

## Ce nu e încă automatizat

- **Text în spatele subiectului** (Aslan „QANDAY”/„Omad”, Barsol „FILM”). Cere decuparea persoanei cadru cu cadru (segmentare), încă neinstalată.
- **Fisheye / barrel distortion** (Dehjq7QqHeo). Se poate face cu filtrul `lenscorrection` din ffmpeg pe B-roll.
- **Mockup-uri de interfață** (timeline de editare, foldere macOS). Se fac la cerere, ca `graphic:` HTML sau componentă Remotion.
