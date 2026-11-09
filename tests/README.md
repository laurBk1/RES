# Verificarea mytools.lua

Din rădăcina repository-ului:

```sh
luajit tests/mytools_aa_test.lua
luajit -bl mytools.lua > /dev/null
```

Testele execută secțiunile anti-aim din fișierul livrat cu mock-uri Gamesense:
selectarea stării, prioritățile manual/on-use, intervalele de choke, feedback-ul
impacturilor, resetarea între vieți/runde, trace-urile și limitele sliderelor.
Nu încarcă subsistemele vechi de vizualizare, Steamworks sau animații și nu
înlocuiesc un test în joc.

## Utilizare și limite

- Setările nu mai sunt suprascrise la încărcare. Pentru preset, apasă explicit
  **Load Adaptive Preset** în Home/Anti-Aim; acesta înlocuiește setările anti-aim.
- Tastele manuale comută la apăsare, nu repetat cât sunt ținute apăsate.
- Freestanding folosește probe aproximative de cover, nu hitbox-uri reconstruite.
  Pentru aceeași țintă, probele rulează la patru tick-uri, iar o schimbare de parte
  necesită două probe consecutive. Beneficiul în meci nu a fost măsurat.
- Anti-brute deduplică impacturile aceluiași adversar în același tick. Fără un ID
  de foc în eveniment, nu poate separa perfect două focuri în același tick sau
  impacturi ale aceluiași foc livrate în tick-uri diferite.
- Defensive se bazează pe un rollback observat de tickbase de 1–16 tick-uri.
  Este o euristică, nu o dovadă a unei ferestre sigure. O cerere `force_defensive`
  și un impact apropiat nu mai sunt tratate drept confirmare.
- `force_defensive` era deja folosit în script, dar nu apare în documentația publică
  consultată; comportamentul lui trebuie confirmat în build-ul Gamesense folosit.
- Denumirile vechi „Unhittable”/„Anti-Resolver” nu sunt garanții de performanță.
  Nu există validare vizuală sau de hit-rate în CS:GO pentru această actualizare.

Referințe API consultate:
- https://gamesensical.gitbook.io/docs/developers/globals/client
- https://gamesensical.gitbook.io/docs/developers/development/events

În joc, verifică în special: tranzițiile standing/moving/crouch/air, apăsare și
menținere manuală, folosirea/defuzarea, DT activ/inactiv și resetarea după respawn.
