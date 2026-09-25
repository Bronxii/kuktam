# P2 – batch 01–10, offline tartalmi audit

Csak mentett P1 JSON + HTML JSON-LD és a 10 referencia. Nincs hálózat, parser, konverzió vagy extractor-módosítás. A szemantikus megfeleltetés dokumentált szöveges audit, nem automatikus hasonlósági mérés.

| ID | Cím | Verdict | Hozzávaló GT/ki | Exact/normalizált | Nyers/lépés/címke | Elkészítés |
|---|---|---|---|---|---|---|
| 01 | Rakott krumpli \| Mindmegette.hu | ACCEPTABLE | 8/8 | 0/8 | 22/11/11 | COMPLETE_WITH_SECTION_HEADINGS |
| 02 | Fasírt \| Mindmegette.hu | PARTIAL | 12/12 | 1/10 | 8/4/4 | COMPLETE_WITH_SECTION_HEADINGS |
| 03 | Húsleves \| Mindmegette.hu | PARTIAL | 14/14 | 5/13 | 14/7/7 | COMPLETE_WITH_SECTION_HEADINGS |
| 04 | Eredeti tiramisu \| Mindmegette.hu | ACCEPTABLE | 7/7 | 1/7 | 12/6/6 | COMPLETE_WITH_SECTION_HEADINGS |
| 05 | Zserbó alaprecept \| Mindmegette.hu | ACCEPTABLE | 17/17 | 0/17 | 8/4/4 | COMPLETE_WITH_SECTION_HEADINGS |
| 06 | Csirkepaprikás | PARTIAL | 10/10 | 0/5 | 3/3/0 | MISSING_STEP |
| 07 | Palacsinta alaprecept | PARTIAL | 7/7 | 0/6 | 3/3/0 | COMPLETE |
| 08 | Túrós csusza | PARTIAL | 6/6 | 0/3 | 6/6/0 | MISSING_STEP |
| 09 | Eredeti brassói aprópecsenye | PARTIAL | 9/9 | 0/2 | 5/5/0 | COMPLETE |
| 10 | Sajtos pogácsa | PARTIAL | 10/10 | 0/8 | 7/7/0 | COMPLETE |

Összesítés:
```json
{
  "verdicts": {
    "PERFECT": 0,
    "ACCEPTABLE": 3,
    "PARTIAL": 7,
    "FAILED": 0
  },
  "content_success_rate_percent": 30.0,
  "title": {
    "clean": 5,
    "decorated": 5,
    "wrong": 0
  },
  "ingredients": {
    "expected": 100,
    "extracted": 100,
    "exact_matches": 7,
    "normalized_matches_including_exact": 79,
    "reviewed_correspondences_not_accuracy": 100,
    "content_difference_pairs": 21,
    "missing_whole_lines": 0,
    "extra_whole_lines": 0,
    "duplicate_occurrences": 1,
    "introduced_duplicates": 0,
    "order_preserved_percent": 100
  },
  "instructions": {
    "raw_entries": 88,
    "actual_steps": 56,
    "step_headings": 32,
    "how_to_sections": 0,
    "complete": 3,
    "complete_with_section_headings": 5,
    "missing_step_or_detail_relative_gt": 2,
    "extra_content": 0,
    "order_error": 0,
    "lost_steps_by_extractor": 0,
    "duplicated_steps": 0
  },
  "source_json_ld_fidelity_cases": 10
}
```

A 100/100 hozzávaló-megfeleltetés NEM 100% pontosság: 21 sorban tartalmi eltérés van. Hiány/extra itt teljes sor hiányát jelenti; a hiányzó jelzőket és eltérő mennyiségeket külön számláljuk. Azonos nevű, eltérő mennyiségű hozzávalókat nem deduplikálunk. Az 05 két vaníliáscukor-sora a GT-ben és a forrásban is szerepel, nem új duplikáció.

Minden nyers ingredients és instructions adat egyezik a mentett HTML JSON-LD-jével. Az 56 valódi lépés és 32 lépéscímke szövege/sorrendje veszteségmentes. A 32 címke HowToStep.name, nem 32 valódi receptszakasz. A két MISSING_STEP minősítés GT-hez képesti részlethiány, nem extractor által elhagyott lépés.

## 01 – ACCEPTABLE

URL: https://www.mindmegette.hu/recept/rakott-krumpli

Cím: TITLE_DECORATION. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.


GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1, 2, 3, 5, 10]: COVERED
- 2 → [4, 5]: COVERED
- 3 → [6, 7]: COVERED
- 4 → [9, 10]: COVERED
- 5 → [10]: COVERED
- 6 → [8, 11]: COVERED
- Négy forráslépés szó szerinti &nbsp; entitást tartalmaz; extractor változatlanul megőrizte.

## 02 – PARTIAL

URL: https://www.mindmegette.hu/recept/fasirt

Cím: TITLE_DECORATION. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.

- Sor 1: `50 dkg darált sertéshús` → `50 dkg sertéshús`. Hiányzó darált jelző; kevésbé specifikus alapanyag a forrás JSON-LD-ben.
- Sor 8: `1 tk őrölt fűszerpaprika` → `1 tk fűszerpaprika`. Hiányzó őrölt jelző; kevésbé specifikus alapanyag a forrás JSON-LD-ben.

GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1]: COVERED
- 2 → [1]: COVERED
- 3 → [2]: COVERED
- 4 → [3]: COVERED
- 5 → [4]: COVERED

## 03 – PARTIAL

URL: https://www.mindmegette.hu/recept/husleves

Cím: TITLE_DECORATION. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.

- Sor 14: `10 dkg levesbetét tészta` → `10 dkg levelestészta`. levesbetét tészta ↔ levelestészta: nem puszta formázás. Forrás/referencia eltérés; automatikus javítás nem indokolt.

GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1]: COVERED
- 2 → [2]: COVERED
- 3 → [3, 4]: COVERED
- 4 → [6, 7]: COVERED
- 5 → [5, 7]: COVERED

## 04 – ACCEPTABLE

URL: https://www.mindmegette.hu/recept/eredeti-tiramisu

Cím: TITLE_DECORATION. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.


GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1]: COVERED
- 2 → [2]: COVERED
- 3 → [3]: COVERED
- 4 → [4]: COVERED
- 5 → [5]: COVERED
- 6 → [6]: COVERED

## 05 – ACCEPTABLE

URL: https://www.mindmegette.hu/recept/zserbo-alaprecept

Cím: TITLE_DECORATION. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.


GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1]: COVERED
- 2 → [2]: COVERED
- 3 → [3]: COVERED
- 4 → [3]: COVERED
- 5 → [3, 4]: COVERED
- 6 → [4]: COVERED

## 06 – PARTIAL

URL: https://www.nosalty.hu/recept/csirkepaprikas

Cím: MATCH. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.

- Sor 2: `0.5 ek sertészsír` → `0 ek Sertészsír`. 0.5 ↔ 0: valódi mennyiségi eltérés.
- Sor 3: `0.5 közepes db vöröshagyma` → `0 közepes db Vöröshagyma`. 0.5 ↔ 0: valódi mennyiségi eltérés.
- Sor 4: `0.5 tk fűszerpaprika` → `0 teáskanál Fűszerpaprika`. 0.5 tk ↔ 0 teáskanál: mennyiségi eltérés ÉS eltérő egységmegfogalmazás; nincs unit-konverzió.
- Sor 9: `só ízlés szerint` → `0 ízlés szerint Só`. A forrás 0 ízlés szerint előtagot ad. A 0 nem tekinthető helyes mennyiségnek.
- Sor 10: `bors ízlés szerint` → `0 ízlés szerint Bors`. A forrás 0 ízlés szerint előtagot ad. A 0 nem tekinthető helyes mennyiségnek.

GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [2]: COVERED
- 2 → [2, 3]: COVERED
- 3 → [3]: COVERED
- 4 → [3]: PARTIAL_OR_MISSING_DETAIL
- 5 → []: PARTIAL_OR_MISSING_DETAIL
- GT 4: hőkiegyenlítés nincs kifejtve a forrásban; GT 5: nokedli/köret tálalás nincs a JSON-LD-ben. Forrás 3: botmixeres pürésítés szerepel, a tömör GT ezt nem említi. Nem extractorveszteség.

## 07 – PARTIAL

URL: https://www.nosalty.hu/recept/palacsinta-alaprecept

Cím: MATCH. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.

- Sor 7: `0.5 dl napraforgó olaj` → `0 dl Napraforgó olaj`. 0.5 ↔ 0: valódi mennyiségi eltérés.

GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1]: COVERED
- 2 → [2]: COVERED
- 3 → [2]: COVERED
- 4 → [3]: COVERED

## 08 – PARTIAL

URL: https://www.nosalty.hu/recept/turos-csusza

Cím: MATCH. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.

- Sor 2: `só ízlés szerint` → `0 ízlés szerint Só`. A forrás 0 ízlés szerint előtagot ad. A 0 nem puszta formázás.
- Sor 4: `2.5 dl víz` → `2 dl Víz`. 2.5 ↔ 2: valódi mennyiségi eltérés.
- Sor 5: `2.5 dl tejföl` → `2 dl Tejföl`. 2.5 ↔ 2: valódi mennyiségi eltérés.

GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1]: COVERED
- 2 → [2]: COVERED
- 3 → [3]: COVERED
- 4 → [4]: COVERED
- 5 → [4, 5]: COVERED
- 6 → [6]: PARTIAL_OR_MISSING_DETAIL
- GT 6 ropogós szalonnával tálalása nincs a forrás 6-ban; az csak maradék tejfölt/túrót említ. A szalonna kisütése és félretétele megvan a 2. lépésben. Nem extractorveszteség.

## 09 – PARTIAL

URL: https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye

Cím: MATCH. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.

- Sor 1: `1 kg sertéshús` → `1 kg Sertéshús az eredeti recept bélszínt ír`. Kiegészítő forrásszöveg: az eredeti recept bélszínt ír. Nem külön hozzávaló.
- Sor 2: `15 dkg füstölt szalonna` → `15 dkg Füstölt szalonna ízlés szerint`. Kiegészítő forrásszöveg: ízlés szerint. Nem külön hozzávaló.
- Sor 3: `1.5 kg burgonya` → `1 kg Burgonya`. 1.5 ↔ 1: valódi mennyiségi eltérés.
- Sor 6: `só ízlés szerint` → `0 ízlés szerint Só`. A forrás 0 ízlés szerint előtagot ad.
- Sor 7: `bors ízlés szerint` → `0 ízlés szerint Bors`. A forrás 0 ízlés szerint előtagot ad.
- Sor 8: `majoranna ízlés szerint` → `0 ízlés szerint Majoranna`. A forrás 0 ízlés szerint előtagot ad.
- Sor 9: `kakukkfű ízlés szerint` → `0 ízlés szerint Kakukkfű`. A forrás 0 ízlés szerint előtagot ad.

GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1]: COVERED
- 2 → [2]: COVERED
- 3 → [3, 4]: COVERED
- 4 → [5]: COVERED
- A szalonna felhasználása sem a GT, sem a JSON-LD elkészítésében nincs részletezve; nem extractor által elhagyott lépés.

## 10 – PARTIAL

URL: https://www.nosalty.hu/recept/sajtos-pogacsa

Cím: MATCH. Hozzávalósorrend: PRESERVED. Teljes hiányzó/extra sor: 0/0. Új duplikáció: 0.

- Sor 5: `2.5 dkg friss élesztő` → `2 dkg Friss élesztő`. 2.5 ↔ 2: valódi mennyiségi eltérés.
- Sor 6: `1 dl tej` → `1 dl Tej langyos`. Kiegészítő forrásszöveg: langyos. Nem külön hozzávaló.

GT-lépés → kinyert valódi lépések (1-alapú):

- 1 → [1]: COVERED
- 2 → [2, 3]: COVERED
- 3 → [3, 4]: COVERED
- 4 → [4]: COVERED
- 5 → [5]: COVERED
- 6 → [6, 7]: COVERED
- A 7. forráslépésben szó szerinti \r\n\r\n karakterlánc van; az output ezt változatlanul őrzi.

## Következtetés és javaslat (nem implementálva)

A technikai 10/10 siker nem azonos a tartalmi sikerrel (3/10). A forrás JSON-LD már tartalmazza a 8 mennyiségi eltérést, 7 nullás ízlés szerinti előtagot, 2 hiányzó jelzőt, 1 eltérő tésztanevet és 3 kiegészítő megjegyzést. Ezek nem extractor által okozott adatveszteségek.

P3 előtt nem indokolt átírni a nyers extractort. A későbbi normalizáló/prezentációs rétegben külön kezelhető a pontos webhely-utótag, a lépéscímke, a HTML-entitás és a literális sortörés. A hibás/nullás mennyiséget tilos találgatással javítani; forrásminőségi figyelmeztetés és felhasználói ellenőrzés szükséges. P3 majd külön engedéllyel indulhat, a forráshibákat a parser hibáitól elválasztva.
