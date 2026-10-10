# A1.1 – Browser-shared text normalization

**Verdict: READY** – helyi automatizált ellenőrzések zöldek, ismert P0/P1 nincs.
A javítás utáni fizikai telefonos újrateszt még nem történt.

## Hiba és javítás

A valós Chrome-megosztás a DOM szövegtördelését követve külön sorba tette a
mennyiséget, mértékegységet és hozzávalónevet. Az Android transport ezt helyesen
adta át, de az eredeti parser önálló sorokat kapott.

Új pure, lokális SharedRecipeTextNormalizer csak a share belépésben fut:
shared text → URL-only ellenőrzés → normalizer → meglévő importdialog előtöltés
→ felhasználói Feldolgozás → változatlan RecipeTextParser → editor → mentés.
A kézi import és a dialog általános initialText szerződése nem változott.

## Safe merge

Csak teljes mennyiségsor + teljes ismert egységsor + egyetlen egyértelmű névsor
áll össze. A név betűvel kezdődik; számot, kettőspontot vagy mondatzáró írásjelet
nem tartalmazhat, és nem lehet önálló egység vagy ismert szakaszcím.
A három rész közötti üres sorok átugorhatók; más üres sorok és szakaszhatárok
megmaradnak. Nincs név több soron át történő összerakása.

ImportQuantityParser.parse és ImportUnitNormalizer.recognize újrahasznosítás:
- egész, pont/vessző tizedes és a már támogatott törtek;
- kizárólag meglévő unit/alias contract, beleértve dkg/dl/kk;
- a normalizer nem konvertál mennyiséget vagy egységet.

A kettőspontos címek külön soron maradnak. Hozzávalók/Fűszerek/Elkészítés címek
nem lehetnek összevont névsorok. Elkészítés/Elkészítés menete után a normalizer
nem alakítja át a prózát. Nincs RecipeTextParser-módosítás.

Már helyes és fel nem ismert input változatlan. Részleges minta, ismeretlen unit,
negatív/nulla mennyiség fail-safe módon érintetlen marad. Idempotencia tesztelt.
Lineáris sorbejárás, dependency és logging nélkül; a meglévő 20k inputkorlát maradt.

## Telefonos regression fixture és parser-integráció

A fixture pontosan a felhasználó által megadott hozzávalóstruktúrát tartalmazza;
nem letöltött oldal, nem újonnan kitalált captured payload.
A támogatott hármasok összeállnak, a három szakaszcím és ékezetek megmaradnak.

A mintában az `1` + `mokkáskanál vaníliaaroma` két sor NEM teljes ismert-unit
hármas: szándékosan két sor marad a partial-pattern/unknown-unit szabály szerint.
A már egysoros `1 mokkáskanál vaníliaaroma` szintén változatlan. Ez a hotfix nem
ígér új szemantikai támogatást ehhez; az editorban szükség szerint javítható.

Normalizer → meglévő parser teszt igazolja:
- tojás 1 db; tojássárgája 1 db;
- porcukor 20 dkg → 200 g; túró 50 dkg → 500 g;
- tejszín 2.5 dl → 250 ml; tejföl 50 g; citrom 0.5 db;
- liszt 1 ek; tojás 4 db; vaj 1 ek; kekszmorzsa 3 ek.
Minden konverzió továbbra is a parser meglévő rétegében történik.

## Érintett fájlok

- lib/sharing/shared_recipe_text_normalizer.dart (új)
- lib/home/presentation/screens/main_screen.dart (share-only bekötés)
- test/sharing/shared_recipe_text_normalizer_test.dart (új)
- test/sharing/fixtures/browser_split_ingredients.txt (új)
- test/sharing/text_share_test.dart (normalizált prefill és változatlan kézi prefill)
- A1_1_SHARED_TEXT_NORMALIZATION_REPORT.md (új)

Native inbox, channel, FIFO, UUID, singleTask, auth, korlátok, monetizáció és
RecipeTextParser forrása változatlan. URL-only snackbar a normalizer előtt marad;
URL szöveg a normalizertől sem változik. Nincs webfetch vagy site-specific runtime kód.

## Ellenőrzések

- Célzott sharing/recipes/auth/feature-gate: **679 PASS / 1 korábbi skipped**.
- Teljes Flutter suite: **1164 PASS / 1 korábbi skipped**.
- Flutter analyze --no-pub: **CLEAN**.
- Android debug APK --no-pub: **PASS**.
- git diff --check: **PASS**.
- Production normalizer keresés: nincs domain/weboldalnév/site regex, payload log.
- Native bridge teszt nem futott újra: native source nem változott.
- Backend teszt nem futott: backend változás nincs.
- Android build meglévő cloud_functions/KGP figyelmeztetése megmaradt;
  upgrade nem történt, build sikeres.

## Manuális újrateszt

A) Mindmegette / Chrome
1. Nyisd meg ugyanazt a receptoldalt, jelöld ki ugyanazt a hozzávalóblokkot.
2. Megosztás → Kuktám.
3. Textarea: `1 db tojás`, `20 dkg porcukor`, `2.5 dl tejszín` egy-egy sorban.
4. Ellenőrizd a szakaszcímeket és ékezeteket.
5. Feldolgozás után a támogatott hozzávalók ne három sorra szétesve jelenjenek meg.
6. Ellenőrizd 200 g porcukor / 500 g túró / 250 ml tejszín értékeket.
7. Az ismeretlen mokkáskanál részt ellenőrizd és szükség esetén kézzel javítsd.

B) Normál szöveg
1. Jegyzetből `1 db tojás` megosztása: változatlan prefill és helyes feldolgozás.
2. Kézi importba beillesztés: a korábbi viselkedés maradjon.

C) URL-only
1. Csak URL megosztásakor a korábbi útmutató jelenjen meg, ne induljon import/fetch.

D) Lifecycle
1. Egy cold és egy warm share-rel ismételd meg a mintát.
2. Egy importablak nyíljon; cancel után ne nyíljon újra magától.
3. Második gyors share ne írja felül az elsőt, maradjon FIFO.

## Ismert korlátok

Szándékosan konzervatív: több sorra bontott név, bizonytalan próza, számos vagy
írásjeles név, ismeretlen egység és részleges minták nincsenek találgatva.
Szakaszcímek eredeti parserbeli értelmezése változatlan; ez nem parser-redesign.
A1 memóriabeli pending/session és process-restart korlátai változatlanok.

ANDROID SHARE TEXT: IMPLEMENTED
SHARED TEXT NORMALIZATION: IMPLEMENTED
SITE-SPECIFIC RUNTIME CODE: NONE
WEB IMPORT: NOT IMPLEMENTED
IMAGE AI IMPORT: NOT IMPLEMENTED
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
MONETIZATION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
