# P4 – end-to-end POC, batch 01–10

**scope:** Offline saved batch 01-10 only; P1/P2/P3 artifacts unchanged. No editor, repository, Firebase, HTTP, AI or save.

**normalization:** Exact Mindmegette suffix on matching domain only. HowToStep headings joined with text; section entries retained once per input occurrence; HTML text/entities rendered; real line breaks preserved. Raw ingredient lines untouched.

**source_warning_provenance:** Oracle-assisted: SOURCE_WARNING comes from the already reviewed P2.5 audit, NOT a generic runtime source-error detector. Unsupported/parser notices come from P3 annotations. Without that audit some errors would be silent.

**manual_corrections:** Lower bound: unique field edits for known source quantity/name errors and supported-input parser name errors. Unknown units and missingQuantity require review but no fabricated conversion/value is counted as mandatory correction.

**verdict_policy:** BROKEN for pipeline preservation failure; POOR for >=3 rows and >=50% rows needing proven correction; otherwise REVIEW for any notice, READY only without notices. Policy is a transparent POC heuristic, not measured user effort.

**timing:** Desktop Dart JIT, Stopwatch, single sequential batch with cold first recipe. IO and audit annotation/report generation excluded; draft_build measures parser DTO mapping only. No network time.

```json
{
  "recipes": 10,
  "verdicts": {
    "READY": 0,
    "REVIEW": 7,
    "POOR": 3,
    "BROKEN": 0
  },
  "total_rows": 100,
  "clean_rows": 61,
  "warning_rows": 39,
  "source_error_rows": 22,
  "unsupported_unit_rows": 12,
  "parser_error_rows": 2,
  "invalid_quantity_rows": 11,
  "unknown_unit_rows": 1,
  "missing_quantity_rows": 7,
  "fallback_db_rows": 29,
  "manual_correction_fields_minimum": 24,
  "manual_corrections_average_per_recipe": 2.4,
  "title_suffix_removed_count": 5,
  "timing": {
    "normalization_ms": {
      "sum": 24.542,
      "average": 2.4542,
      "max": 20.149
    },
    "parser_ms": {
      "sum": 10.076999999999998,
      "average": 1.0076999999999998,
      "max": 5.54
    },
    "draft_build_ms": {
      "sum": 0.7510000000000002,
      "average": 0.07510000000000003,
      "max": 0.516
    },
    "total_local_ms": {
      "sum": 35.403000000000006,
      "average": 3.5403000000000007,
      "max": 26.214
    }
  }
}
```

| ID | Verdict | Kötelező mezőjavítás minimum | Normalizálás ms | Parser ms | Draft ms | Lokális összes ms |
|---|---|---|---|---|---|---|
| 01 | REVIEW | 0 | 20.149 | 5.54 | 0.516 | 26.214 |
| 02 | REVIEW | 3 | 0.509 | 0.778 | 0.031 | 1.322 |
| 03 | REVIEW | 4 | 1.042 | 0.768 | 0.038 | 1.852 |
| 04 | REVIEW | 0 | 0.419 | 0.302 | 0.016 | 0.739 |
| 05 | REVIEW | 0 | 0.494 | 1.037 | 0.038 | 1.573 |
| 06 | POOR | 7 | 0.252 | 0.34 | 0.023 | 0.617 |
| 07 | REVIEW | 1 | 0.211 | 0.235 | 0.017 | 0.465 |
| 08 | POOR | 3 | 0.356 | 0.264 | 0.015 | 0.637 |
| 09 | POOR | 5 | 0.212 | 0.359 | 0.036 | 0.609 |
| 10 | REVIEW | 1 | 0.898 | 0.454 | 0.021 | 1.375 |

A kategóriák átfednek; warning rows az érintett sorok uniója. A POOR nem adatvesztés: a forrás sok hibája miatt nagy a javítási igény. A címek 5 utótagja eltűnik; 32 lépéscímke 32 saját lépésszöveggel egy sorba kerül. 56 tényleges lépés megmarad. Fűszerbesorolás nincs.

## Preview-k

### 01

```text
RECEPT: Rakott krumpli

HOZZÁVALÓK:
1.0 kg Burgonya
6.0 db Tojás
1.0 db Só
100.0 g Kolbász
500.0 ml Tejföl
2.0 db Tojássárgája
2.0 tk Vaj
100.0 g Bacon

WARNING (POC auditjelölések, nem általános automatikus felismerés):
3. sor: missingQuantity

ELKÉSZÍTÉS:
1. lépés: A rakott krumpli elkészítését azzal kezdjük, hogy a krumplikat 10-15 percre beáztatjuk hideg vízbe, majd alaposan megsikáljuk és leöblítjük. A tojásokat megmossuk.

2. lépés: A krumplit felöntjük annyi hideg vízzel, hogy bőven ellepje.

3. lépés: Hozzáadjuk a sót, és a forrástól számított 20 percig, fedő alatt puhára főzzük.

4. lépés: A tojásokat sós, hideg vízben feltesszük főni, és a forrástól számított 8 percig főzzük, majd hideg vízbe merítve azonnal lehűtjük.

5. lépés: A krumpliról leöntjük a vizet, még melegen lehúzzuk a héját, és hűlni hagyjuk. A kihűlt tojásokat is meghámozzuk, elnegyedeljük vagy felkarikázzuk.

6. lépés: A kolbászt meleg vízzel leöblítjük, így könnyen lehúzhatjuk a héját, aztán vékonyan felkarikázzuk.

7. lépés: A tejfölt egy kis tálba tesszük és elkeverjük benne a tojássárgákat.

8. lépés: A sütőt 180 fokra (gázsütő 3. fokozat) előmelegítjük.

9. lépés: A vajjal kikenünk egy lapos, tűzálló tálat, és hozzálátunk a hagyományos rakott krumpli rétegezéséhez.

10. lépés: Az aljára karikázzuk a krumpli felét, kissé megsózzuk, lazán összekeverjük, és elsimítjuk. Arányosan elosztva a tetejére rendezzük a tojást és a kolbászkarikákat, majd megkenjük a tejföl felével. A maradék krumplit felkarikázzuk, és kissé egymásra csúsztatva a tetejére rendezzük. Egyenletesen bevonjuk a maradék tejföllel, végül a tetejére göndörítjük a szalonnaszeleteket.

11. lépés: A sütőben addig sütjük, amíg a tejföl és a szalonna aranybarnára pirul (35-40 perc). Az elkészült rakott krumplit vegyes idénysalátával vagy ecetes savanyúsággal, kovászos uborkával tálaljuk.

FŰSZEREK: üres

VERDICT: REVIEW
A draft teljes, de parser/source/unsupported figyelmeztetés miatt ellenőrzés szükséges.
Bizonyított mezőjavítás minimum: 0. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 02

```text
RECEPT: Fasírt

HOZZÁVALÓK:
500.0 g sertéshús
2.0 db zsemle
1.0 db fej Vöröshagyma
1.0 db Olaj
3.0 db gerezd Fokhagyma
2.0 db Tojás
1.0 db kis kanál Majoránna
1.0 tk fűszerpaprika
1.0 db Só
1.0 db Bors
100.0 g Zsemlemorzsa
500.0 ml Olaj

WARNING (POC auditjelölések, nem általános automatikus felismerés):
1. sor: SOURCE_WARNING
3. sor: SOURCE_WARNING, UNSUPPORTED_UNIT
4. sor: missingQuantity
5. sor: UNSUPPORTED_UNIT
7. sor: UNSUPPORTED_UNIT
8. sor: SOURCE_WARNING
9. sor: missingQuantity
10. sor: missingQuantity

ELKÉSZÍTÉS:
1. lépés: A fasírt elkészítéséhez a zsemlét vízbe áztatjuk, majd alaposan kinyomkodjuk. Az apróra vágott hagymát olajon megdinszteljük. A fokhagymát összenyomjuk.

2. lépés: Minden hozzávalót alaposan összedolgozunk, majd ízlés szerint fűszerezzük a masszát.

3. lépés: Vizes kézzel gombócokat formázunk (van, aki lapos pogácsákat készít), és zsemlemorzsában megforgatjuk.

4. lépés: Végül nem túl forró olajban, oldalanként 5-5 perc alatt kisütjük a fasírtokat.

FŰSZEREK: üres

VERDICT: REVIEW
A draft teljes, de parser/source/unsupported figyelmeztetés miatt ellenőrzés szükséges.
Bizonyított mezőjavítás minimum: 3. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 03

```text
RECEPT: Húsleves

HOZZÁVALÓK:
1.0 kg színhús
500.0 g csont
500.0 g vegyes zöldség
1.0 db fej Hagyma
2.0 db gerezd Fokhagyma
10.0 db szem Bors
1.0 db cseresznyepaprika
1.0 db csapott mokkáskanál szeklice
1.0 db csokor Petrezselyem
150.0 g Kelkáposzta
1.0 db Zöldpaprika
1.0 db Paradicsom
1.0 db Só
100.0 g levelestészta

WARNING (POC auditjelölések, nem általános automatikus felismerés):
3. sor: SOURCE_WARNING
4. sor: SOURCE_WARNING, UNSUPPORTED_UNIT
5. sor: UNSUPPORTED_UNIT
6. sor: UNSUPPORTED_UNIT
7. sor: missingQuantity, SOURCE_WARNING
8. sor: SOURCE_WARNING, UNSUPPORTED_UNIT
9. sor: UNSUPPORTED_UNIT
13. sor: missingQuantity

ELKÉSZÍTÉS:
1. lépés: A húsleves elkészítéséhez elsőként a húst és a zöldségeket alaposan megmosunk, megtisztítjuk.

2. lépés: Egy nagyobb fazék aljára fektetjük a szétütött csontokat, arra a 3-4 darabba vágott húst, és felöntjük annyi hideg vízzel, hogy bőven (4-5 ujjnyira) ellepje. Forrásig hevítjük - a régi hagyománnyal szemben nem habozzuk le, mert oda az értékes fehérje, leülepszik szépen az a hab magától, nem lesz zavaros tőle a leves.

3. lépés: Hozzáadjuk (teatojásba zárva) a szemes borsot, a fokhagymát, a sáfrányos szeklicét - gyönyörű színt ad a levesnek -, a cseresznyepaprikát, a hagymát egészben és egy kevés sót. Fedő nélkül, lassú forralással, gyöngyöztetve fél óráig főzzük.

4. lépés: Ezután beletesszük a hasábokra vágott zöldségeket, a kelkáposztát, a zöldpaprikát és a paradicsomot egészben, a csokorban hagyott petrezselymet, és további lassú gyöngyöztető forralással, fedő nélkül az egészet puhára főzzük.

5. lépés: Közben enyhén sós vízben megfőzzük a levestésztát, leszűrjuk. Kevés húslevest merünk rá, hogy melegen tartsuk.

6. lépés: Ezután következik a művészet: a húsleves felszínéről kanállal eltávolítjuk a fölösleges zsiradékot, majd sűrű szövésű szitakanálon keresztül, merőkanállal - éppen csak szelíden megbillentve a fazekat, hogy fel ne zavarosítsuk a levest - előmelegített levesestálba szűrjuk.

7. lépés: A tésztát a forró leveshez adjuk, külön tálon kínáljuk a zöldséget és a húst, amelyet fogyaszthatunk a leveshez, vagy második fogásként is különféle mártásokkal.

FŰSZEREK: üres

VERDICT: REVIEW
A draft teljes, de parser/source/unsupported figyelmeztetés miatt ellenőrzés szükséges.
Bizonyított mezőjavítás minimum: 4. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 04

```text
RECEPT: Eredeti tiramisu

HOZZÁVALÓK:
4.0 db Tojás
200.0 g Porcukor
100.0 ml Rum
500.0 g Mascarpone
300.0 ml kávé
1.0 doboz Babapiskóta
1.0 db Kakaópor

WARNING (POC auditjelölések, nem általános automatikus felismerés):
7. sor: missingQuantity

ELKÉSZÍTÉS:
1. lépés: Az eredeti tiramisu receptje szerint első lépésként a tojásokat kettéválasztjuk.

2. lépés: A tojássárgáját habosra kikeverjük a cukorral, hozzáadjuk a rumot, végül pedig a mascarponét, és addig keverjük, míg sima és kissé habos krémet kapunk.

3. lépés: A tojásfehérjéből robotgéppel kemény habot verünk, majd óvatosan belekeverjük a mascarponés krémbe .

4. lépés: Lefőzzük a kávét. Amikor langyosra hűlt, belemártjuk a babapiskótákat úgy, hogy félig átázzanak.

5. lépés: Belehelyezzük a babapiskótákat egy sorban egy kisebb tepsibe, vagy üvegtálba. Rásimítjuk a krém felét, erre teszünk még egy réteg kávéba áztatott babapiskótát, és végül a maradék krémmel befedjük.

6. lépés: Minimum 2 órát hűtőszekrényben állni hagyjuk. Közvetlenül a tálalás előtt a tiramisu tetejére kakaóport szórunk.

FŰSZEREK: üres

VERDICT: REVIEW
A draft teljes, de parser/source/unsupported figyelmeztetés miatt ellenőrzés szükséges.
Bizonyított mezőjavítás minimum: 0. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 05

```text
RECEPT: Zserbó alaprecept

HOZZÁVALÓK:
250.0 g Darált dió
200.0 g Porcukor
1.0 db Citrom
1.0 csomag Vaníliás cukor
400.0 g Baracklekvár
2.0 ek Rum
10.0 g Élesztő
50.0 ml Tej
500.0 g Liszt
250.0 g Margarin
1.0 db mokkáskanál Szódabikarbóna
100.0 g Porcukor
1.0 db Tojássárgája
1.0 csomag Vaníliás cukor
2.0 ek Tejföl
150.0 g Étcsokoládé
1.0 tk Étolaj

WARNING (POC auditjelölések, nem általános automatikus felismerés):
11. sor: UNSUPPORTED_UNIT

ELKÉSZÍTÉS:
1. lépés: A zserbó elkészítéséhez a diót összekeverjük a porcukorral, a citrom lereszelt héjával és a vaníliás cukorral.

2. lépés: Az élesztőt langyos tejben felfuttatjuk. A lisztet elmorzsoljuk a margarinnal. Hozzáadjuk az élesztős tejet, a szódabikarbónát, a porcukrot, a tojássárgáját, a vaníliás cukrot és a tejfölt, és jól összedolgozzuk.

3. lépés: Az összegyúrt tésztát három részre osztjuk. Az első részt kinyújtjuk, és kibéleljük vele a 24×38 cm-es tepsit. Megkenjük a baracklekvár felével, meglocsoljuk 1 ek rummal, majd rászórjuk a cukros dió felét. Beborítjuk a másik kinyújtott tésztalappal, amit ismét megkenünk lekvárral, megöntözünk rummal, és rászórjuk a dió másik felét. Ráhelyezzük a harmadik kinyújtott tésztát, kissé rányomkodjuk, és villával megszurkáljuk.

4. lépés: Előmelegített sütőben 200 fokon kb. 30 perc alatt világosbarnára sütjük, majd a tepsiben hagyjuk kihűlni. Amíg hűl a tészta, elkészítjük a mázat. Az étcsokoládét vízgőz felett felolvasztjuk az olajjal, és a süteményre kenjük. Megvárjuk, amíg megszárad, majd felszeleteljük.

FŰSZEREK: üres

VERDICT: REVIEW
A draft teljes, de parser/source/unsupported figyelmeztetés miatt ellenőrzés szükséges.
Bizonyított mezőjavítás minimum: 0. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 06

```text
RECEPT: Csirkepaprikás

HOZZÁVALÓK:
6.0 db Csirke alsócomb
[JAVÍTANDÓ] ek Sertészsír
[JAVÍTANDÓ] db közepes db Vöröshagyma
[JAVÍTANDÓ] tk Fűszerpaprika
1.0 db közepes db Zöldpaprika
1.0 db közepes db Paradicsom
200.0 g Tejföl
1.0 ek Finomliszt
[JAVÍTANDÓ] db ízlés szerint Só
[JAVÍTANDÓ] db ízlés szerint Bors

WARNING (POC auditjelölések, nem általános automatikus felismerés):
2. sor: invalidQuantity, SOURCE_WARNING
3. sor: invalidQuantity, SOURCE_WARNING
4. sor: invalidQuantity, SOURCE_WARNING
5. sor: PARSER_WARNING
6. sor: PARSER_WARNING
9. sor: invalidQuantity, SOURCE_WARNING
10. sor: invalidQuantity, SOURCE_WARNING

ELKÉSZÍTÉS:
A combokat megmossuk, szárazra itatjuk. A hagymát meghámozzuk, apróra vágjuk. A paprikát mossuk, kockára vágjuk. A paradicsomot mossuk, kockákra vágjuk.

A zsírt egy serpenyőben felhevítjük, rászórjuk a hagymát, és megpirítjuk. A tűzről levesszük, hozzákeverjük az édesnemes paprikát és kb. 100 ml vizet öntünk hozzá. Hozzáadjuk a csirkecombokat, a zöldpaprikát és a paradicsomot. Sóval, borssal ízesítjük.

Fedő alatt mérsékelt tűzőn, puhára pároljuk (ha szükséges öntsünk hozzá kevés vizet). A húst kiszedjük. A párolólét botmixerrel pürésítjük, hozzáadjuk a liszttel elkevert tejfölt, és 2-3 perc alatt mártássá forraljuk. A combokkal együtt még egyszer felforraljuk.

FŰSZEREK: üres

VERDICT: POOR
Legalább 3 sor és a sorok legalább fele bizonyított mezőjavítást igényel (előre rögzített POC-küszöb).
Bizonyított mezőjavítás minimum: 7. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 07

```text
RECEPT: Palacsinta alaprecept

HOZZÁVALÓK:
3.0 db Tojás
2.0 ek Cukor
1.0 csomag Vaníliás cukor
240.0 g Finomliszt
400.0 ml Tej
300.0 ml Szódavíz
[JAVÍTANDÓ] ml Napraforgó olaj

WARNING (POC auditjelölések, nem általános automatikus felismerés):
7. sor: invalidQuantity, SOURCE_WARNING

ELKÉSZÍTÉS:
Egy tálba ütjük a tojásokat, majd a cukrokkal együtt kikeverjük.

Folyamatos keverés mellett hozzáadjuk a tojásos keverékhez a lisztet, majd a tejet és a szódát, végül az olajat, és csomómentesre keverjük.

Egy serpenyőt vagy palacsintasütőt egy ecsettel vékonyan megkenünk olajjal, majd megsütjük a palacsintákat.

FŰSZEREK: üres

VERDICT: REVIEW
A draft teljes, de parser/source/unsupported figyelmeztetés miatt ellenőrzés szükséges.
Bizonyított mezőjavítás minimum: 1. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 08

```text
RECEPT: Túrós csusza

HOZZÁVALÓK:
400.0 g Csuszatészta
[JAVÍTANDÓ] db ízlés szerint Só
350.0 g Füstölt szalonna
200.0 ml Víz
200.0 ml Tejföl
450.0 g Tehéntúró

WARNING (POC auditjelölések, nem általános automatikus felismerés):
2. sor: invalidQuantity, SOURCE_WARNING
4. sor: SOURCE_WARNING
5. sor: SOURCE_WARNING

ELKÉSZÍTÉS:
A tésztát lobogó, enyhén sós vízben fogkeményre kifőzzük.

A szalonnát egy centis darabokra felkockázzuk, serpenyőbe tesszük. Felöntjük annyi vízzel, ami éppen ellepi, és közepes lángon melegíteni kezdjük. Egészen addig folytatjuk, amíg minden csepp víz el nem párolog, sőt utána szép barnára, zsírjára sütjük. (A vízre azért van szükség, mert így kívül ropogós, de belül puha marad.) Ha elkészült, akkor szűrőlapáttal kivesszük a szalonnát, és félretesszük.

A zsírt is kiöntjük, csak három evőkanállal hagyunk benne, ehhez hozzáadjuk a tejfölt, és alaposan elkeverjük.

A kifőtt tésztát összeforgatjuk a tejfölös keverék és a túró egyharmadával, majd a sütőt grill fokozatra és maximum hőfokra állítjuk, és 10-12 percre betesszük, amíg meg nem pirul a tészta széle.

Kivesszük a tésztát a sütőből, átforgatjuk, majd hozzáadjuk a túró és tejföl második harmadát, és újra visszatesszük a sütőbe 10 percre.

Ha kész, azonnal tálaljuk. A tetejét a maradék tejföllel és túróval meglocsoljuk.

FŰSZEREK: üres

VERDICT: POOR
Legalább 3 sor és a sorok legalább fele bizonyított mezőjavítást igényel (előre rögzített POC-küszöb).
Bizonyított mezőjavítás minimum: 3. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 09

```text
RECEPT: Eredeti brassói aprópecsenye

HOZZÁVALÓK:
1.0 kg Sertéshús az eredeti recept bélszínt ír
150.0 g Füstölt szalonna ízlés szerint
1.0 kg Burgonya
2.0 db Vöröshagyma
8.0 db gerezd Fokhagyma
[JAVÍTANDÓ] db ízlés szerint Só
[JAVÍTANDÓ] db ízlés szerint Bors
[JAVÍTANDÓ] db ízlés szerint Majoranna
[JAVÍTANDÓ] db ízlés szerint Kakukkfű

WARNING (POC auditjelölések, nem általános automatikus felismerés):
3. sor: SOURCE_WARNING
5. sor: UNSUPPORTED_UNIT
6. sor: invalidQuantity, SOURCE_WARNING
7. sor: invalidQuantity, SOURCE_WARNING
8. sor: invalidQuantity, SOURCE_WARNING
9. sor: invalidQuantity, SOURCE_WARNING

ELKÉSZÍTÉS:
A megmosott, meghámozott burgonyát apró kockákra vágjuk, zsírban megsütjük.

A sertéshúst is kockákra vágjuk, majd nagyon kevés zsíron pirítani kezdjük.

A meghámozott vöröshagymát felaprítjuk, vagy lereszeljük. A fokhagymát szintén felaprítjuk.

Hozzáadjuk a húshoz, majd fűszerezzük.

A burgonyát és a húst az eredeti recept szerint összekeverjük, de ez a lépés elhagyható.

FŰSZEREK: üres

VERDICT: POOR
Legalább 3 sor és a sorok legalább fele bizonyított mezőjavítást igényel (előre rögzített POC-küszöb).
Bizonyított mezőjavítás minimum: 5. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```

### 10

```text
RECEPT: Sajtos pogácsa

HOZZÁVALÓK:
200.0 g Vaj
400.0 g Finomliszt
2.0 db Tojás
200.0 ml Tejföl
20.0 g Friss élesztő
100.0 ml Tej langyos
1.0 db Cukor
1.0 db kávéskanál Só
150.0 g Sajt
1.0 db Tojás a kenéshez

WARNING (POC auditjelölések, nem általános automatikus felismerés):
5. sor: SOURCE_WARNING
7. sor: unknownUnit, UNSUPPORTED_UNIT
8. sor: UNSUPPORTED_UNIT

ELKÉSZÍTÉS:
Készítsük el a kovászt. Ehhez az élesztőt a langyos tejbe morzsoljuk el. Szórjuk meg egy csipet cukorral és egy kis liszttel, majd tegyük félre meleg helyre kb. 10 percre. Akkor jó, ha az élesztő szépen felhólyagosodik.

A lisztet a vajjal és egy csipet sóval morzsoljuk el. A tejfölt keverjük el a tojással.

A lisztbe beletesszük a felfuttatott élesztőt és a tejfölös tojást, majd jól összedolgozzuk. Könnyű tésztát kell kapjunk.

Takarjuk le, és hagyjuk kelni meleg helyen. Körülbelül 30 perc után nyújtsuk ki nagyjából 1,5 centire, összehajtogatjuk. Tíz perc múlva megint kinyújtjuk és összehajtogatjuk. Ezt háromszor ismételjük meg.

Megint kinyújtjuk kb 1,5 centi vastagra. Megkenjük tojással, sózzuk, majd megszórjuk reszelt sajttal.

Pogácsaszaggatóval szaggassuk ki, és kezünkkel kicsit formázzuk, sodorjuk meg. Így a sütőben felfele fog nőni a pogácsánk, nem fog elfolyni, és nem lesz lapos.

Lehetőség szerint magas falú tepsibe pakoljuk őket egymástól kb. 2 centire, hogy ne nőjenek össze.

180 fokos sütőben 25 perc alatt készre sütjük.

FŰSZEREK: üres

VERDICT: REVIEW
A draft teljes, de parser/source/unsupported figyelmeztetés miatt ellenőrzés szükséges.
Bizonyított mezőjavítás minimum: 1. Az unsupported egységek átváltása nincs találgatva; további user-döntést igényelhet.

```
