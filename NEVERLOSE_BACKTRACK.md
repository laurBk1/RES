# Neverlose Backtrack — network-safe manual assist

Fișier: `neverlose_backtrack.lua`. Este pentru Neverlose **CS:GO legacy**, nu
Gamesense sau CS2. Înlocuiește scriptul atașat BT Extend v2; nu le rula simultan.

## Ce face și ce nu face

- Implicit nu modifică nicio comandă: modul manual trebuie activat explicit.
- Cu ragebot activ, inclusiv un override activ, nu intervine în aim/fire/tickcount.
  Dacă nu poate citi starea ragebotului, refuză modul manual.
- Nu scrie `send_packet`, choke, mișcare, butoane de atac, cvar-uri, minimum damage
  sau setări de exploit. Nu încearcă să coordoneze fakelag-ul altui script.
- Manual assist intervine numai la input de foc, cu o armă de foc, alegând capul
  istoric cu cel mai mic FOV eligibil. La egalitate preferă recordul mai nou.
  Nu trage automat, nu calculează hitchance, penetration sau damage și nu verifică
  dacă arma este gata să tragă. Ținerea apăsată a focului poate modifica aim/tick și
  în comenzile dintre focuri; arma și jocul decid când se execută focul efectiv.
- Recordurile provin din `net_update_end`, folosind simulation time și copii ale
  pozițiilor. Sunt eliminate la discontinuități, dormancy, schimbarea identității,
  respawn, rundă nouă și deconectare. Cache-ul este limitat la 128 recorduri/jucător.
- Tick-ul cerut este `round((simulation_time + interpolation) / tickinterval)`.
  Interpolarea ține cont de cvar-urile disponibile ale serverului.
- Filtrul de vârstă folosește limita din meniu și `sv_maxunlag`; verificarea temporală
  cu latența outgoing este o euristică conservatoare, nu o validare din partea serverului.
- Verificarea de vizibilitate este un trace în lumea **actuală**, nu o reconstrucție
  a hitbox-urilor/lumii din trecut. Datele lipsă și erorile de trace resping candidatul.

**Nu extinde istoricul serverului și nu injectează recorduri în ragebot.** API-ul
public consultat nu documentează o astfel de operație. Latența, interpolation și
choke nu formează un „buget de shift” care poate fi crescut arbitrar. Nu există
probe de îmbunătățire a hit-rate-ului și nici validare în clientul Neverlose aici.

## Instalare / configurare

1. Dezactivează BT Extend v2, altfel acesta continuă să schimbe `send_packet` și
   poate menține override-ul minimum damage. După descărcarea scriptului vechi,
   verifică setările de minimum damage și interpolation: el le modifica fără restore.
2. Copiază `neverlose_backtrack.lua` în folderul scripturilor Neverlose și încarcă-l.
3. Pentru ragebot, lasă `Manual assist` oprit; scriptul nu îi adaugă funcționalități.
4. Pentru test manual, oprește ragebot, activează `Manual assist`, începe cu FOV 8°
   și limită 150 ms, apoi apasă foc normal. Setările sunt limite, nu valori optime demonstrate.
5. Activează `Debug console` pentru motivul blocării sau candidatul ales. Un mesaj
   `manual candidate` nu confirmă un hit sau acceptarea tick-ului de către server.

Căile UI `Aimbot / Ragebot / Main / Enabled` și `Enable` sunt încercate prin `pcall`.
Ele nu sunt garantate pentru toate build-urile; dacă nu sunt găsite, nu se ghicește
starea și nu se aplică manual assist. Interfața nu a fost verificată vizual în client.

## Verificare reproductibilă

```sh
luajit tests/neverlose_backtrack_test.lua
luajit -bl neverlose_backtrack.lua > /dev/null
```

Testele încarcă întregul script cu mock-uri de API, fără client Neverlose. Ele
verifică logica și absența modificărilor de rețea, nu comportamentul serverului,
interacțiunea cu alte scripturi sau eficiența în meci. Fișierele Gamesense nu sunt modificate.

## API consultat

- https://docs-csgo.neverlose.cc/documentation/variables/entity
- https://docs-csgo.neverlose.cc/documentation/events
- https://docs-csgo.neverlose.cc/documentation/variables/utils
- https://docs-csgo.neverlose.cc/documentation/variables/ui
- https://docs-csgo.neverlose.cc/documentation/variables/cvar
- https://docs-csgo.neverlose.cc/documentation/variables/globals
- https://docs-csgo.neverlose.cc/documentation/variables/rage

Au fost consultate secțiunile relevante, nu presupus că fiecare funcție din API
este utilă pentru backtrack. `rage.exploit` documentează charge/defensive/teleport,
nu selecția sau injectarea recordurilor de lag compensation.
