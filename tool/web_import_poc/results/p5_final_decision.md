# P5 – Kuktám webes receptimport: végső döntés

**TECHNICAL GO: YES · HUNGARIAN PRODUCTION GO: CONDITIONAL · CURRENT INTERNATIONAL GO: NO**

A technológiai alap alkalmas célzott magyar integráció megtervezésére. A jelenlegi POC nem élesíthető változtatás nélkül. A döntés 30 mentett esetet foglal össze; nincs új letöltés, benchmark, production-kód vagy P6-megvalósítás. A minta kicsi és célzott, nem reprezentatív piaci megbízhatósági becslés.

## Módszer és nevezők

30 technikai URL; 28 hozzáférhető recept/draft; 292 ingredientsor; 24 SOURCE_ERROR kizárva a parserpontosságból; 268 valid input, ebből 193 supported és 75 unsupported. 29–30 minden tartalmi/parser/usability nevezőből kimarad, technikai failure marad.

**Összevonási korrekció:** Batch 1 P4 mezőjavításokat és eltérő verdictküszöböt használt, ezért az eredeti verdict-összeg nem azonos módszerű használhatósági mérés. Mindkettőt megőrizzük: eredeti riportösszeg, illetve egységes P5 újraszámlálás kizárólag mentett sorbesorolásokból. Új parserfuttatás nem történt.

Egységes szabály: egy source-error/unsupported/parser-error sor egy kötelező művelet, az átfedés egyszer számít; hiányzó csoportcím külön strukturális művelet. Review-only: a többi production-warningos sor. READY: 0 kötelező javítás; POOR: >=4 művelet vagy >=40%; egyéb javítandó draft REVIEW. A becslés nem mért felhasználói munkaráfordítás; READY mellett is lehet review-only mező.

## Technikai fetch

**28/30 = 93,33% SUCCESS**; HTTP_ERROR 2; FETCH_ERROR/NO_JSON_LD/NO_RECIPE/INVALID_JSON_LD/MULTIPLE_RECIPES/INVALID_RECIPE mind 0. Normál benchmark retry 0, fallback 0. B3.0 auditkor történt külön hozzáférési próbák nem benchmark-retry-k.

| Domain | Siker / URL | Arány |
|---|---:|---:|
| www.bbcgoodfood.com | 13/13 | 100.00% |
| www.foodnetwork.com | 0/2 | 0.00% |
| www.mindmegette.hu | 10/10 | 100.00% |
| www.nosalty.hu | 5/5 | 100.00% |

Food Network 29–30: HTTP 403, ACCESS_LIMITATION. Nincs használható receptsnapshot/verified ground truth/parsereredmény/draft. Ez hozzáférési korlát, nem extractor-, parser- vagy source-quality hiba. Konkrét anti-bot mechanizmus nincs bizonyítva.

## Extractor reliability — PASS

28 hozzáférhető inputon **292/292 ingredient sor és 205/205 instruction entry** megmaradt. Az entry headinget is tartalmazhat: 162 step-body entry, nem minden esetben egyetlen látható főzési lépés. Elveszett/hozzáadott/módosított sor, sorrendhiba, title mutation és candidate-selection error: 0 a mentett auditok szerint. B1 56 actual-step mutatóját nem adtuk közvetlenül az entry számlálókhoz.

## Source JSON-LD quality

| Domain | Egyező ingredient | Mennyiségi eltérés | Hiányzó megjegyzés | Csoportcímhiány | Dekorált cím |
|---|---:|---:|---:|---:|---:|
| www.bbcgoodfood.com | 144/144 | 0 | 0 | 5 | 0 |
| www.mindmegette.hu | 97/106 | 0 | 9 | 0 | 10 |
| www.nosalty.hu | 27/42 | 15 | 0 | 0 | 0 |

Összesen 268/292 ingredient tartalmi egyezés. Nosalty: 8 csonkolt tört + 7 hibás 0 előtag = 15 quantity mismatch. Mindmegette: 9 note/jelző hiány, egy note másodlagos súlyadatot is tartalmaz. Good Food: 5 group heading hiány. Észlelt instruction content loss 0; Mindmegette heading/body elkülönítés és 12-es recept egyblokkos instrukciója strukturális különbség.

Korlát: Batch 1 egyes eredeti GT-instrukciói átírtak maradtak. A korrigált auditból a megfigyelt veszteségmentesség állítható, egységes szó szerinti visible-page pontosság minden 28 esetre nem. Ezek a korlátok nem rontják a JSON-LD→extractor adatmegőrzést.

## Parser quality

**Supported-input accuracy: 191/193 = 98,96%. Overall valid-input success: 191/268 = 71,27%.** A 24 source-error sor mindkettőből kizárt. A 2 supported parserhiba a 06-os recept „1 közepes db …” soraiban: a db a névben marad.

- Quantity accuracy: 251/253 = 99,21%; 15 nem értékelhető szemantikai mennyiség kimarad. Ez a parser által kapott inputhoz mért érték, nem a visible page hibás JSON-LD előtti mennyiségeinek hitelesítése.
- Explicit quantity: 223/225 = 99,11%; az accepted missing-quantity 1 db alapérték nincs ebben.
- Supported unit: 193/193 = 100%, a supported darabszámos db konvencióval együtt.
- Szemantikai névpontosság: 193/268 = 72,01%; unsupported egységszöveg névben maradása is eltérés. Nem raw-szövegvesztés.

| Nyelv | Valid | Supported helyes/összes | Overall valid success | Unsupported valid |
|---|---:|---:|---:|---:|
| Magyar | 124 | 104/106 = 98,11% | 104/124 = 83,87% | 18 |
| Angol | 144 | 87/87 = 100% | 87/144 = 60,42% | 57 |

## Unsupported input

79 sor / 22 recept érintett, ebből 75 valid source input és 4 source-error átfedés. Magyar: 22 összes / 18 valid; angol: 57/57.

| Kategória | Összes sor | Jelleg |
|---|---:|---|
| SIMPLE_ALIAS_CANDIDATE | 34 | tbsp/tsp, magyar kanálmegnevezések; lehetséges szabály, nem automatikus engedély |
| QUANTITY_GRAMMAR | 11 | range, 2 x 400g, half-a-jar, alternatív/compound mennyiségek |
| SEMANTIC_DECISION | 34 | fej/gerezd/cloves, csipet/pinch, bunch, handful, rashers/stick |

Gyakori pontos címkék: tbsp 23, fej 6, cloves 6, gerezd 5, tsp 5. A részletes kifejezéslista a JSON-ban. A kategorizálás triage, nem production aliasterv; egy szó jelentése kontextusfüggő (cloves lehet szegfűszeg is).

## Silent fallback — kiemelt release-kockázat

**56 sor / 21 recept.** Definíció: valid source + unsupported + production warning nélkül pozitív mennyiség/db output. Magyar: 16 sor/10 recept; angol: 40 sor/11 recept. Domain: Mindmegette 14/8, Nosalty 2/2, Good Food 40/11 (sor/recept).

Példa: „2 tbsp …” → quantity 2, canonical unit db, név „tbsp …”, warning üres. A felhasználó érvényes adatnak vélheti, majd scaling/shopping is ezt használhatja. A production warningok és a kézi benchmark-audit POC warningjai különböznek; a POC jelzései nem működő runtime felismerők.

További **12 source-error sor warning nélkül** marad, ezek nem részei az 56 silent unsupported sornak. Pozitív 2.5→2 csonkolást vagy hiányzó megjegyzést a JSON-LD önmagában nem árul el. A rendszer nem ígérhet olyan automatikus forráshitelesítést, amelyet az audit csak visible-page összevetéssel tudott elvégezni.

## End-to-end használhatóság

28 értékelt draft, 2 NO_DRAFT_DUE_TO_ACCESS_BLOCK. Eredeti riportok nyers összege: **1 READY / 14 REVIEW / 13 POOR / 0 BROKEN**, eltérő B1 módszerrel.

Összehasonlítható P5 újraszámlálás mentett annotációkból: **3 READY / 10 REVIEW / 15 POOR / 0 BROKEN**; 106 kötelező művelet, **3,786/recept**; 28 review-only, **1,0/recept**. Az eredeti riportok változatlanok.

| Nyelv | Draft | READY/REVIEW/POOR/BROKEN | Átlag javítás | Átlag review-only |
|---|---:|---|---:|---:|
| Magyar | 15 | 2/7/6/0 | 2,933 | 1,133 |
| Angol | 13 | 1/3/9/0 | 4,769 | 0,846 |

## Piaci döntés

**HUNGARIAN_MARKET_FEASIBILITY: CONDITIONAL.** 15/15 technikai siker és 98,11% supported parserpontosság jó alap. A 24 magyar source-error, 16 silent fallback és 2,933 javítás/recept azonban kizárja a vak, ellenőrzés nélküli import ígéretét. Különösen a Nosalty számainál kötelező az ismert kockázat kezelése; a magyar fókusz nem jelent magyar hibamentességet.

**CURRENT_INTERNATIONAL_FEASIBILITY: FAIL a jelenlegi széles production ajánlatra.** 57/144 unsupported valid sor, 9/13 POOR draft, 4,769 javítás/recept, Food Network access block. Ez nem végleges technológiai elutasítás: ellenőrzött POC folytatható, de általános angol támogatást most nem javaslok.

## Production UX és warning stratégia

Közös „Recept importálása”: a teljes trimelt input pontosan egy érvényes http/https URL → webút; minden más → meglévő text import. Későbbi „Fénykép csatolása” helye tervezhető, képimport most nincs. Mindkét út ugyanabba a szerkeszthető preview/editorba érkezik; explicit Save, nincs autosave.

| Eset | Kötelező viselkedés |
|---|---|
| Invalid quantity | Raw sor megőrzése, mezőjelzés, meglévő mentési validáció; nincs kitalált fallback |
| Unsupported/unknown unit, silent db | Sor alatti jól látható review-jelzés; érintett name/quantity/unit ellenőrzése, nyers input megtekinthető |
| Ambiguous ingredient | Teljes raw intent maradjon, javításig nincs automatikus elfogadás |
| Fetch/403/no Recipe | Rövid magyar üzenet, input megmarad; megszakítás, indokolt retry vagy szöveges beillesztés; nincs bypass |
| Több Recipe | Nincs önkényes választás; választás vagy kezelhető „nem egyértelmű” kimenet |
| Source structure | Meglévő headingek megőrzése; bizonyítható veszteség jelzése. Hiányzó visible heading JSON-LD-ből nem detektálható biztosan |
| Ismert source quantity kockázat | Forráslink + feltűnő mennyiségellenőrzési figyelmeztetés és explicit megerősítés; nincs tippelt javítás |

A szöveges import soronkénti warning UX-ét használjuk. Az általános „ellenőrizd a receptet” notice nem helyettesíti a detektálható unsupported jelölést. Nosalty kezdeti támogatása csak igazolt review-gate mellett; ha ez QA-n nem elég biztonságos, ez a domain maradjon ki az első támogatott körből, és kínáljon text-paste utat.

## Minimális production scope és prioritások

Android-first client-side JSON-LD web adapter for observed Hungarian domains, conservative availability messaging and Nosalty source-risk gate; existing parser + small review/normalization layer + existing editor. No new backend, DOM fallback, AI/OCR, new canonical units or schema migration in initial scope. Validate device/network behavior before release; cloud sync stays unchanged.

### MUST_HAVE_BEFORE_RELEASE

- Shared deterministic URL/text dispatch with editable preview and explicit Save; preserve text import behavior.
- Raw source/provenance and separate warning metadata for audited Hungarian unsupported, ambiguous and silent fallback cases; no fake values or speculative repairs.
- Known source-quality risk handling, especially Nosalty positive truncation; source-link review and no claim of verified quantities.
- Resolve or explicitly flag two observed supported-input name errors: adjective between numeric quantity and db.
- Bounded cancellable HTTP operation: timeout/body/redirect limits, only public http(s) targets, validate redirects, no script execution, no bypass. These are engineering requirements, not capabilities proven by desktop benchmark.
- Fetch/access/multiple-candidate error UX preserves input; no autosave, duplicate-name/account isolation/save validation maintained.
- Android real-device network and end-to-end QA on proposed supported domains; desktop sample does not establish mobile reliability.

### SHOULD_HAVE_SOON

- Monitor user-confirmed failures without logging full recipes or private URLs by default.
- Improve low-risk Hungarian alias/descriptor coverage only after semantic decision and targeted tests.
- Broaden source snapshots and missing-heading tests; keep domain capability expectations explicit.

### LATER_INTERNATIONAL

- tsp/tbsp aliases require deliberate quantity/unit semantics and testing, not just label substitution.
- cloves/rashers/sticks/bunches need semantic decisions; range/multiplier/mixed/compound quantities need separate grammar.
- Additional domains, JS/HTML fallback or backend only if separately justified; no evidence requires AI.
- Photo import remains a future slot only.

## P6 roadmap – terv, nem megkezdett implementáció

- **P6.0** — Plan domain/data boundaries, safe URL handling, source risk policy, DTO and warning provenance; decide exact launch-domain scope.
- **P6.1** — Bounded asynchronous web fetch and JSON-LD candidate data layer; cancellable operation, no JavaScript/DOM fallback.
- **P6.2** — Exact display normalization and lossless instructions; conservative unsupported/silent-risk warning layer, raw text retained.
- **P6.3** — One Recept importálása field: trimmed entire input consisting of one valid http/https URL takes web path, otherwise existing text path. No photo implementation.
- **P6.4** — Reuse editable preview/editor; review quantities, preserve spices-empty import rule, explicit Save and existing validation/duplicate/account policies.
- **P6.5** — Hungarian access/error UX, no-result/multiple candidate/cancel/retry cases, intact user input and source-link checks.
- **P6.6** — Offline fixtures plus network-layer tests, regression and user-run Android acceptance; test non-silent unsupported warnings and known source-risk scenarios.
- **P6.7** — Release gate: demonstrated warnings, source limitation messaging, mobile success, no data-loss/autosave, privacy/logging review and supported-domain disclosure.

## Végső kapu

**TECHNICAL GO YES**: a determinisztikus JSON-LD irány indokolt, saját backend/AI/DOM fallback szükségességét a minta nem bizonyítja. **HUNGARIAN PRODUCTION GO CONDITIONAL**: a MUST-HAVE UX, source-risk és mobil QA feltételekkel. **CURRENT INTERNATIONAL GO NO**: széles angol támogatás most túl sok kézi javítást és csendes hibát hozna.

A production integráció **tervezését nem blokkolja** semmi. Az élesítést a fenti feltételek blokkolják; a desktop benchmark nem igazolja a mobil hálózati stabilitást. P6 csak külön jóváhagyással kezdhető.

## Bizonyítékok

Az összesítő JSON tartalmazza a felhasznált riportok hashét, domain/nyelvi számlálókat, soronkénti silent-fallback bizonyítékot és az eredeti/egységesített recipe-verdict mappinget. Korábbi riportot nem írtunk felül.

- [p1_batch_01-10.json](p1_batch_01-10.json)
- [p2_5_source_truth_audit.json](p2_5_source_truth_audit.json)
- [p2_corrected_batch_01-10.json](p2_corrected_batch_01-10.json)
- [p3_parser_batch_01-10.json](p3_parser_batch_01-10.json)
- [p4_e2e_batch_01-10.json](p4_e2e_batch_01-10.json)
- [b2_1_batch_11-20.json](b2_1_batch_11-20.json)
- [b2_2_content_source_quality.json](b2_2_content_source_quality.json)
- [b2_3_parser_batch_11-20.json](b2_3_parser_batch_11-20.json)
- [b2_4_e2e_batch_11-20.json](b2_4_e2e_batch_11-20.json)
- [b3_1_batch_21-30.json](b3_1_batch_21-30.json)
- [b3_2_content_source_quality.json](b3_2_content_source_quality.json)
- [b3_3_parser_batch_21-28.json](b3_3_parser_batch_21-28.json)
- [b3_4_e2e_batch_21-28.json](b3_4_e2e_batch_21-28.json)

## Ellenőrzések

- Riportkonzisztencia, forrásriport-hash, source/access/parser nevezők: PASS.
- POC tesztek: 62/62 PASS.
- POC dart analyze: tiszta.
- Production flutter analyze --no-pub: tiszta.
- Git diff-check, az új riportokra is: PASS.
- Csak ez a két P5 riport jött létre. Production/extractor/parser és korábbi riportok változatlanok. P6 nem indult, nincs commit/push.
