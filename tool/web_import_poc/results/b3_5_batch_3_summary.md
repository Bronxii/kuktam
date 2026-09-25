# B3.5 – Batch 3 összesítő és döntési riport

Kizárólag a mentett B3.0–B3.4 riportok összesítése; nincs új hálózati kérés vagy benchmark. A 10 technikai esetből 8 tartalmi/parser/draft eset értékelhető. P5 nem indult.

## Technikai eredmény

10 URL: **8 SUCCESS, 2 HTTP_ERROR (403), 0 FETCH_ERROR**. B3.1 retry: 0; fallback: 0; többjelöltes eset: 0. BBC Good Food: 8/8 (100%); Food Network: 0/2; teljes batch: 80%. JS-renderelés/fallback nem kellett a 8 sikeres oldalhoz. Az elérhetetlen két oldal esetére ebből nem következik semmi.

### Food Network – 29–30

ACCESS_BLOCKED / UNRESOLVED_CONTENT. Nincs használható receptsnapshot, verified ground truth, parserbenchmark vagy draft. A 403 hozzáférési megtagadás; konkrét anti-bot mechanizmus nem igazolt. Ez **fetch/access limitation**, nem extractor-, parser- vagy source-quality hiba. B3.0 korábbi próbái nem B3.1 retry-k. A B3.1 403 testek nem maradtak meg receptsnapshotként.

### Mentett B3.1 időeredmények (csak 8 SUCCESS, ms)

| Szakasz | Átlag | Medián | Minimum | Maximum |
|---|---:|---:|---:|---:|
| fetch_ms | 105.995 | 93.463 | 89.977 | 189.488 |
| extract_ms | 26.476 | 16.005 | 14.068 | 92.506 |
| total_ms | 132.475 | 110.560 | 104.246 | 282.005 |

403 idő külön: 29 = 96,184 ms; 30 = 74,163 ms total, extraction nem futott. Desktop hálózati/JIT mérés, nem telefonos teljesítményígéret.

## Extractor és source quality

**Extractor STRONG:** 8/8 LOSSLESS; 82/82 ingredient és 47/47 instruction entry megőrizve, 8/8 cím változatlan. Elveszett/hozzáadott/módosított sor, sorrendhiba, title mutation és candidate-selection hiba: mind 0. Csak a hozzáférhető 8 oldalra érvényes.

**Source quality CONDITIONAL:** 81 pontos + 1 whitespace-egyezés = 82/82 tartalmi ingredient match. Quantity/unit/note/ingredient hiány vagy extra sor: 0. A 25 receptből három csoportcím (filling, crumble, optional topping), a 28-ból a To serve csoport hiányzik. Ezek source-struktúrahiányok. 47/47 elkészítési lépés teljes; content omission, block-structure eltérés és sorrendhiba: 0. A megjelenített Step 1… sorszámok prezentációs jelölések, nem elveszett recepttartalom. Cím: 8 CLEAN, 0 decorated/wrong. Receptminősítés: 6 GOOD, 2 USABLE_WITH_ISSUES.

Snapshot reconciliation: 21 és 24 csak technikai HTML-változás, recepttartalom változatlan; a másik hat snapshot azonos. B3.0 referenciák használhatók. 29–30 tartalom továbbra unresolved.

## Parser

82 valid source sor; ingredient SOURCE_ERROR = 0. **51/51 támogatott sor helyes (100%), támogatott-input parserhiba = 0.** 31 unsupported = 27 unit/kifejezés + 4 quantity grammar. Overall valid-input success: 51/82 = 62,20%. A csoportcímhiány nem ingredient parserhiba.

- Quantity: 72/73 = 98,63%; 9 nem értékelhető szemantikai mennyiség kizárva. Explicit mennyiség: 66/67 = 98,51%; az egy eltérés a 2 squirts + alternative tsp ambiguous/null esete, PARSER_LIMITATION.
- Támogatott unit: 51/51, ebből explicit mértékegység 30/30 = 100%.
- Szemantikai névpontosság: 51/82 = 62,20%; támogatott sorokon 51/51. Ez nem raw-text adatvesztés.
- ½ helyesen 0,5; tsp/tbsp támogatás ebből nem következik. Nem előforduló formákra nincs pontosságállítás.

## Unsupported kategóriák

| Kategória | Sor | Jelleg |
|---|---:|---|
| SIMPLE_ALIAS_CANDIDATE | 14 | Elsődleges tbsp; későbbi termékdöntés, most nincs alias |
| QUANTITY_GRAMMAR | 4 | Range tsp, compound kg/lb/oz, litres/pints, squirts + alternative tsp |
| SEMANTIC_DECISION | 13 | Garlic cloves, bunch, piece, pinch, handful, stick |

A 4 cloves sor szegfűszegként támogatott darabszámos hozzávaló; nem azonos a garlic-cloves unitproblémával. Gramos mennyiség után a can leíró részként marad.

## Silent fallback

**21/82 sor (25,61%), 6/8 recept.** Például tbsp/cloves/stick/bunch warning nélkül a névben marad, canonical unit = db. A draft menthetőnek tűnhet, de felülvizsgálatot igényel. Production warning: 16 sor; production + POC auditjelzés uniója: 37 sor. A POC jelzések ismert, soronként auditált besorolások; nem implementált production felismerés.

## End-to-end használhatóság

**1 READY / 2 REVIEW / 5 POOR / 0 BROKEN**. Mind a 8 draft létrejön; ez nem jelent automatikusan helyes receptet. 31 javítandó sor + 4 strukturális javítás = 35 művelet, átlag **4,375/recept**. 6 review-only mező = **0,75/recept**. 45 clean + 37 warningos sor = 82. A warning/unsupported/silent kategóriák átfednek; a csoportcímeket nem számoljuk ingredient sornak.

B2.4 szerinti küszöb: READY 0 kötelező javítás; POOR legalább 4 javítás vagy legalább 40%; egyéb javítandó draft REVIEW; használhatatlan BROKEN. Egy sor több érintett mezője egy művelet. A hiányzó csoportcím külön strukturális művelet.

8/8 cím változatlan; 47/47 step megmaradt sorrendben; spices üres. A jelenlegi angol draftok többsége jelentős kézi munkát kér.

## B2.4 és B3.4

| Mutató | B2.4 (10 recept) | B3.4 (8 recept) |
|---|---:|---:|
| READY / REVIEW / POOR / BROKEN | 0 / 5 / 5 / 0 | 1 / 2 / 5 / 0 |
| Átlagos kötelező javítás | 3,8 | 4,375 |
| Silent fallback sor | 27 | 21 |

Különböző méretű és nyelvi összetételű minta; a két nyers darabszám nem önmagában minőségi trend. B3 hozzáférhető része teljesen angol; B2 vegyes. Nincs összevont P5-statisztika.

## Magyar és angol tanulság

A B2.5 riport a magyar öt receptre 2,2, az angol ötre 5,4 kötelező javítást mért receptenként; a magyar részben is előfordult silent fallback. B1/P2.5 pedig bizonyította, hogy a látható magyar recept és JSON-LD eltérhet úgy, hogy az extractor adatmegőrzése teljes. Ezért a magyar fókusz életképesebbnek látszó korrekciós terhelését sem szabad feltétel nélküli production-readiness állításként kezelni.

B3 megerősíti a jelenlegi magyar parser angol unit-/quantity-grammar korlátait; a támogatott inputok helyesek, a nemzetközi használat több ellenőrzést és korrekciót igényel. A nyelvek/source domainek minőségét P5-ben is külön kell tartani.

## Döntés

| Kapu | Verdict | Indok |
|---|---|---|
| TECHNICAL FEASIBILITY | CONDITIONAL | Good Food 8/8 működik, Food Network 403 |
| SOURCE QUALITY | CONDITIONAL | Teljes ingredients/steps, négy logikai csoportcím hiányzik |
| PARSER FEASIBILITY | CONDITIONAL | Supported 100%, 31 unsupported és 21 silent fallback |
| END-TO-END USABILITY | CONDITIONAL | Minden draft szerkeszthető, de 5/8 POOR |

**P5 összesítő előtt nem szükséges extractor-, parser-, benchmark-tool- vagy ground-truth-metodika-javítás.** Ez a mérések összegezhetőségére vonatkozik, nem production élesíthetőségre. Az access blockot nem kell megkerülni vagy kitalált adattal pótolni.

Batch 3 lezárható a dokumentált korlátokkal. Külön jóváhagyás után P5: a meglévő 30 esetből készült riportok döntési szintű összesítése, technikai failure-eket megtartva, hozzáférhetetlen tartalmakat kizárva a tartalmi/parser/usability nevezőkből. Kötelező külön rétegek: source vs extractor, supported vs unsupported parser, silent fallback és magyar vs angol használhatóság. **P5 most nem indult.**

## Bizonyítékok és konzisztencia

ID-k, 82 raw ingredient sor, 47 instruction entry, B3.3→B3.4 production mezők/warningok/silent jelölések, nevezők és átfedések ellenőrizve. A JSON összesítő a forrásriportok SHA256 hashét rögzíti. Korábbi riportot vagy production kódot nem módosítottunk.

- [b3_0_source_truth_audit.json](b3_0_source_truth_audit.json)
- [b3_1_batch_21-30.json](b3_1_batch_21-30.json)
- [b3_2_content_source_quality.json](b3_2_content_source_quality.json)
- [b3_3_parser_batch_21-28.json](b3_3_parser_batch_21-28.json)
- [b3_4_e2e_batch_21-28.json](b3_4_e2e_batch_21-28.json)

## Lefuttatott ellenőrzések

- Riportkonzisztencia és nevezők: PASS.
- POC tests: 62/62 PASS.
- POC dart analyze: tiszta.
- Production flutter analyze --no-pub: tiszta.
- Git diff-check és az új riportok whitespace-ellenőrzése: PASS.
- Csak a két B3.5 riport új; nincs production/extractor/parser módosítás, új benchmark, commit vagy push.
