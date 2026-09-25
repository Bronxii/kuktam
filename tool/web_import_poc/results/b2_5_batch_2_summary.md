# Batch 2 / B2.5 – összesítő és döntési riport

Csak 11–20. A meglévő B2.0–B2.4 riportok összesítése; nem történt új letöltés vagy benchmark.

## Döntés

- **TECHNICAL FEASIBILITY: PASS** – 10/10 technikai siker, veszteségmentes extractor.
- **HUNGARIAN-MARKET FEASIBILITY: CONDITIONAL** – ígéretes magyar, szerkeszthető import; a javítási igény és a néma fallback miatt felhasználói ellenőrzés szükséges.
- **CURRENT INTERNATIONAL FEASIBILITY: CONDITIONAL** – felügyelt draft készíthető, de általánosan megbízható angol importnak nem tekinthető.
- Az eredmény 10 receptre és két domainre vonatkozik; nem általános sikerarány. A magyar célpiac értékelését nem az angol támogatáshiány határozza meg.

## Technikai extraction

10 URL, 10 SUCCESS, 0 failure/retry/fallback/HTTP-hiba/többjelöltes eset. Nem észleltünk anti-bot akadályt; JS-renderelés nem kellett. Domainonként 5/5 SUCCESS. A végső URL-ek változatlanok; köztes redirectlánc és charset nem volt önálló mérési adat.

| Csoport | Mérőszám | Átlag ms | Medián ms | Min ms | Max ms |
|---|---|---:|---:|---:|---:|
| Összes | fetch_ms | 584.617 | 168.452 | 84.752 | 1636.703 |
| Összes | extract_ms | 27.820 | 19.564 | 13.232 | 96.153 |
| Összes | total_ms | 612.440 | 223.686 | 101.275 | 1656.137 |
| www.bbcgoodfood.com | fetch_ms | 142.241 | 90.535 | 84.752 | 321.045 |
| www.bbcgoodfood.com | extract_ms | 16.070 | 14.448 | 13.232 | 19.696 |
| www.bbcgoodfood.com | total_ms | 158.314 | 103.769 | 101.275 | 340.744 |
| www.mindmegette.hu | fetch_ms | 1026.992 | 1582.600 | 105.485 | 1636.703 |
| www.mindmegette.hu | extract_ms | 39.569 | 24.838 | 19.432 | 96.153 |
| www.mindmegette.hu | total_ms | 1066.565 | 1607.442 | 139.466 | 1656.137 |

Egy kérés/URL, desktop Dart JIT; a hálózati és helyi idők külön. A leggyorsabb 17, a leglassabb 15 volt.

## Adatmegőrzés és snapshotstabilitás

**Extractor: STRONG.** 110/110 hozzávalósor, 70/70 instrukcióbejegyzés. Elvesztett, hozzáadott, módosított sor, sorrendhiba, címmódosítás és jelöltválasztási hiba: 0. A 70 entry headingeket is tartalmaz, nem 70 főzési lépést jelent.

8 snapshot csak HTML-szinten változott; 2 teljesen azonos. Látható receptváltozás 0, unresolved 0. Az eredeti ground truth továbbra is érvényes. Mind a 10 B2.0 SHA256 újra ellenőrizve.

## Source JSON-LD quality

| Domain | Sor | Egyező/normalizált | Hiányzó megjegyzés | Hiányzó csoportcím | Díszített cím | Verdict |
|---|---:|---:|---:|---:|---:|---|
| www.bbcgoodfood.com | 62 | 62 | 0 | 1 | 0 | USABLE_WITH_ISSUES |
| www.mindmegette.hu | 48 | 46 | 2 | 0 | 5 | USABLE_WITH_ISSUES |

Mindmegette 14/8: hiányzik `(1,5 kg)`; 14/9: hiányzik `(házi)`. Az első kiegészítő mennyiségi adatvesztés, miközben az elsődleges `1 fej` megmaradt. Fő quantity/unit eltérés, hiányzó/extra hozzávalósor és instrukciótartalom-vesztés mindkét domainen 0. A 12-es öt bekezdése egy JSON-LD string, azonos teljes szöveggel. Good Food 17: `For the filling` csoportcím hiányzik. **Mind forrásprobléma, nem extractorhiba.**

## Parser quality

110 sor = 2 SOURCE_ERROR + 108 értékelt. 108 = 73 támogatott/helyes + 35 unsupported + 0 támogatott parserhiba.

| Csoport | Valid sor | Támogatott/helyes | Unsupported | Overall siker | Explicit quantity | Explicit supported unit | Név |
|---|---:|---:|---:|---:|---|---|---|
| Összes | 108 | 73/73 | 35 | 67.59% | 85/86 (98.84%) | 47/47 (100.00%) | 74/108 (68.52%) |
| www.bbcgoodfood.com | 62 | 36/36 | 26 | 58.06% | 50/51 (98.04%) | 21/21 (100.00%) | 36/62 (58.06%) |
| www.mindmegette.hu | 46 | 37/37 | 9 | 80.43% | 35/35 (100.00%) | 26/26 (100.00%) | 38/46 (82.61%) |

Supported-input accuracy mindkét domainen 100%. A quantity fallbackeket is beszámító mutató 101/102 = 99,02%; az explicit, értékelhető quantity 85/86 = 98,84%. Hat összetett/szöveges alak nem értékelhető egyszerű quantityként, ezért kizárt, nem sikeres. A 16 mennyiség nélküli sor 1 db-je elfogadott fallback, nem a forrás által állított mennyiség. Az egy quantity-eltérés az alternatív számozott mennyiséget tartalmazó unsupported sorhoz kötődik. Névmutató az unsupported sorokat is tartalmazza; támogatott neveknél 73/73 helyes.

## Unsupported input

35 érvényes forrású unsupported sor: Mindmegette 9, Good Food 26. Minden forrást számolva 36, mert egy SOURCE_ERROR sor is unsupported.

| Kifejezés | Összes / valid sor |
|---|---:|
| 2 x 400g cans | 2 / 2 |
| cloves | 3 / 3 |
| csipet | 1 / 1 |
| drop | 1 / 1 |
| fej | 4 / 3 |
| gerezd | 2 / 2 |
| half a … jar | 1 / 1 |
| heaped tsp; alternative level tbsp | 1 / 1 |
| kis fej | 1 / 1 |
| kávéskanál | 1 / 1 |
| large handful | 1 / 1 |
| mokkáskanál | 1 / 1 |
| range tbsp | 1 / 1 |
| rashers | 1 / 1 |
| stick | 1 / 1 |
| tbsp | 9 / 9 |
| tsp | 5 / 5 |

Kategorizálás, implementációs javaslat nélkül:
- **A – alias/lexikai szabály jelleg:** tsp/tbsp rövidítések; ismert measure-tokenek felismerése. A felismerés nem jelent automatikus szemantikai konverziót.
- **B – összetett quantity grammar:** `2 x 400g`, tartomány, half-a-jar, alternatív mennyiségek.
- **C – szemantikai döntés:** cloves/rashers/stick/handful/drop, púpozott vagy csapott kanál, magyar fej/gerezd/kanálkifejezések. Egy token több kategóriában is releváns lehet.

## End-to-end használhatóság

| Csoport | READY | REVIEW | POOR | BROKEN | Javítás/recept | Review-only/recept | Néma fallback | Érintett recept |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Összes | 0 | 5 | 5 | 0 | 3.8 | 1.6 | 27 | 10 |
| www.mindmegette.hu | 0 | 4 | 1 | 0 | 2.2 | 2.2 | 8 | 5 |
| www.bbcgoodfood.com | 0 | 1 | 4 | 0 | 5.4 | 1.0 | 19 | 5 |

Required: one action per objectively misleading/unsupported ingredient row, overlapping reasons counted once; plus one action per missing source ingredient group. Review-only: non-required rows with accepted missing-quantity fallback. Clean means no production OR POC warning. Source/unsupported/warning/risk categories overlap. Source-error rows excluded from silent risk, not excluded from user correction needs.

BROKEN if title/preparation empty or no ingredient rows. READY if 0 required actions. POOR if >=4 required actions OR required actions / ingredient rows >=40%. Otherwise REVIEW. Group loss counts one structural action and cannot necessarily be restored in existing editor without notes; no new editor support assumed.

110 sorból 57 clean, 53 warningos. 37 javítandó sor + 1 hiányzó csoportcím = 38 javítási művelet. A csoportcím helyreállítása jelenlegi editorban megjegyzést/workaroundot igényelhet; nincs feltételezett új csoportmező. A korrekciószám nem szerkesztési időmérés.

## SILENT_BAD_FALLBACK_RISK

**27 sor, 10/10 recept**: Mindmegette 8 sor/5 recept; Good Food 19 sor/5 recept. A magyar fej/gerezd/kanálalakok és az angol tsp/tbsp/cloves/rashers/stick látszólag érvényes `db` értékkel jelenhetnek meg. A névben megmaradó unit nem feltétlenül készteti a felhasználót ellenőrzésre.

A production parser 24 sort jelölt warninggal; a POC 53 sort jelöl a production és auditjelzések uniójával. A POC **kézzel ellenőrzött B2.2/B2.3 metadata alapján** figyelmeztet: ez nem implementált production felismerés. A forráshibás sorok a silent-risk számlálóból kizártak, a kézi javítási igényből nem.

## Magyar és angol következtetés

A magyar célpiacon a kisebb, 2,2 javítás/recept terhelés és a támogatott inputok hibamentes feldolgozása indokolja a további mérést. Ugyanakkor 5 magyar receptből mindegyikben volt néma fallback: feltétel nélküli production készültség nem állítható.

Az angol rész 5,4 javítás/recept terhelése főleg a jelenlegi magyar parser unsupported egység- és kifejezéskészletéből ered. Ez külön lokalizációs/termékhatár; nem cáfolja a magyar feature életképességét. A 0 BROKEN azt jelenti, hogy szerkeszthető draft készül, nem azt, hogy automatikusan helyes.

## Batch 3 előtti döntés

**Nem szükséges extractor-, parser-, benchmark-logika- vagy ground-truth-metodika-javítás Batch 3 mérése előtt.** Az új batch külön scope-paraméterezése/adaptálása szükséges lehet, de ez nem jelenlegi hiba és most nem készült el. Ugyanazt a változatlan baseline-t érdemes tovább mérni. Production integráció előtt a néma fallback UX-kockázatot külön rendezni kell; ez nem Batch 3 indulási feltétel.

Batch 3 továbbviendő módszere:
- Visible page is ground truth; preserve snapshot/SHA256/@VISIBLE evidence.
- JSON-LD, extractor, parser remain separate layers.
- Exclude source-error rows from parser accuracy denominators.
- Reconcile snapshot changes before content scoring.
- Measure silent fallback separately; distinguish audit vs production warnings.
- Report Hungarian/English usability separately.
- Keep unsupported grammar out of supported-input denominator; disclose unmeasured forms.
- Reuse correction thresholds and overlap counting; no automatic source repair.

## Elfogadott UX-irány – csak dokumentáció

Közös **Recept importálása** felület: a szövegmező receptszöveget vagy recept URL-t fogad. Pontosan egy érvényes http/https URL → webimport; minden más → szöveges import. Mindkettő ugyanabba a szerkeszthető preview/editor folyamatba érkezik. A gyanús/hibás sorok jól látható jelölést kapjanak a szöveges import mintájára. Automatikus vak mentés nincs. Későbbre hely marad a **Fénykép csatolása** lehetőségnek; képimport most nem készül.

## Ellenőrzések és bizonyítékok

Riport-ID-k, fő számlálók, source/parser nevezők, 110 sor mezőinek B2.3→B2.4 egyezése, snapshot SHA256 és átfedések ellenőrizve. 35 valid unsupported + 1 source-error átfedés = 36 total unsupported; 37 javítandó sor + 1 strukturális javítás = 38. Korábbi riportok nem módosultak.
- [b2_0_source_truth_audit.json](b2_0_source_truth_audit.json)
- [b2_1_batch_11-20.json](b2_1_batch_11-20.json)
- [b2_2_content_source_quality.json](b2_2_content_source_quality.json)
- [b2_2_snapshot_reconciliation.json](b2_2_snapshot_reconciliation.json)
- [b2_3_parser_batch_11-20.json](b2_3_parser_batch_11-20.json)
- [b2_4_e2e_batch_11-20.json](b2_4_e2e_batch_11-20.json)

## Következő lépés

Külön jóváhagyással Batch 3 source-truth audit (21–30): először a látható oldalakhoz kötött ground truth ellenőrzése és bizonyítékok rögzítése. Csak azután technikai és tartalmi benchmark. Batch 3 nem indult el. Production kód, parser és alias nem változott. Nincs commit/push.

## Lefuttatott ellenőrzések

- POC tests: 52/52 PASS.
- POC dart analyze: tiszta.
- Production flutter analyze --no-pub: tiszta.
- Riportkonzisztencia és source/parser nevezők: PASS.
- git diff --check és az új riportok whitespace-ellenőrzése: PASS.
- Csak ez a két B2.5 riport új; production és korábbi eredményfájl nem változott.
