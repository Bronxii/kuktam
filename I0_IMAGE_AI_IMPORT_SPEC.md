# I0 – Image AI Import audit és implementációs terv

2026-10-11 · I0.1 MULTI-IMAGE AMENDMENT · DESIGN ONLY · READY FOR LOCAL PLANNING; NOT READY FOR LIVE RELEASE.
Az I0.1 az egész specifikációt felülírja a végleges multi-image termékszabályokkal. Az engineering limitek, transportajánlat és provider/árválasztás továbbra is validálandók. Nincs implementáció, API-hívás vagy költés.

## 1. Ellenőrzött jelenlegi architektúra

| Forrás | Megállapítás / reuse |
|---|---|
| lib/recipes/domain/models/recipe.dart | Recipe: name, ingredients(name,double quantity,unit), spices(name), preparation, opcionális id. A konstruktor nem strict validator; null mennyiség nem reprezentálható. |
| recipe_repository.dart | users/UID/recipes; create új doc + createdAt, update updatedAt. Névellenőrzés trim/lowercase, read-then-write; nem globálisan atomikus uniqueness. |
| add_recipe_screen.dart | initialRecipe vagy initialImport; újrecept mód; validateSession a névellenőrzés körül; explicit save. initialRecipe preparation sortöréseit megőrzi. |
| recipe_import_draft.dart | Nullable quantity/rawQuantityText, warning, unprocessedSegments; NINCS spices mező és nullable unit. initialImport ma kiüríti a spices listát. AI-ra változtatás nélkül nem elég. |
| sharing/recipe_share_codec.dart | Strict UTF-8, depth≤8, exact mezők, finite positive quantity/canonical unit, 256 KiB; private _recipe validator. K2K byte-envelope nem AI transport. |
| export/domain/recipe_export.dart | ExportRecipe.toContentJson explicit content allowlist, K2K/E1 reuse. Közösíthető pure content validátor; nem harmadik eltérő recipe mapper kell. |
| MainScreen / RecipeFileReceiver | Structured event → AddRecipeScreen(initialRecipe,validateSession); queue/current route/login pending/generation minták reuse. AI nem text-parser és nem K2K fájlevent. |
| ImportUnitNormalizer | recognize + convert exact alias-konverzió; normalizeForImport további display-kerekítést is végez. AI-hoz az exact konverzió kell. |
| MeasurementUnits | A hét kért egységen túl csomag/üveg/doboz/konzerv is létezik! Az AI V1 hét egységes allowlist külön policy; a meglévő app-listát nem szűkítjük. |
| Policy | Text/shopping-add/K2K/export Free, scaling/Mit főzzek Pro. imageImport ProFeature placeholder mindig unavailable; ProScreen „hamarosan”. Később külön AI-credit capabilityre kell váltani. |
| pubspec / lock | cloud_functions6.3.5, Auth, path_provider2.1.6, share_plus, archive adott. image4.9.1 transitive; nincs image_picker/firebase_storage direct dependency. |
| Android | singleTask, külön text/K2K/SAF bridge. Main manifestben nincs image receive vagy broad storage permission. I0 nem tervez image share receivert. |
| functions/src/index.ts, runtime/* | Lazy composition, v2 callables/RTDN/schedule, izolált v1 Auth fallback; Node22, functions7.4.0/admin14.5.0. Auth/strict DTO/error/fake/lease/idempotency minták reuse. |
| billing / LifecycleStore | Lifetime-only termék, backend ack, revoke, binding/account generation. Nincs credit balance/consume ág. Creditből nem Pro grant készül. |
| Infra | main.dart onlineEnabled:false; P0C_2B_REPORT local-only. Spark/no deployed Functions/parkolt Blaze: USER-REPORTED; LIVE STATE NOT VERIFIED. |

## 2. Végleges V1 termékszabály és UX

**1 recept → 1–5 kép → 1 operationId → 1 közös provider-feldolgozás → 1 strukturált draft.**
MULTI-IMAGE V1; MAX5 végleges hard UI/backend limit. Galéria/screenshot igen, közvetlen kamera nem. Persistent image retention NONE; szükséges átmeneti storage nem tartós galéria.
**N feldolgozásra átadott kép = N AI kredit.** Egyetlen recipe-job szintű reserve/finalize/release; nincs képenként külön recept vagy kliensoldali összefűzés. A provider együtt látja az összes elfogadott képet, a user által jóváhagyott sorrendben.
Login → multi-select → sorszámos thumbnail lista/grid → add/remove/reorder → minden kép local preprocess → költség jóváhagyása → N reserve → operation-bound upload → teljes készlet server validation → egy provider call → egy warningos draft → meglévő editor → explicit Mentés.
Minden képmódosítás újraszámolja a creditCost=images.length értéket. Példa: „5 kép kiválasztva · Feldolgozás költsége: 5 kredit · Egyenleg: 18 kredit” és **[Importálás – 5 kredit]**. Nulla, >5 vagy invalid kép mellett Importálás tiltott; nincs csendes eldobás vagy truncálás.
A megjelenített 1…N sorrend authority; a picker belső sorrendjét nem tekintjük automatikusan megfelelőnek. Drag-reorder mellett fel/le gombok és akadálymentes sorszám. Új választás csak a maradék helyekre; a túl sokat visszaadó providert is UI-validáció állítja meg. Exact duplikált kép figyelmeztetés, user eltávolíthatja; a képszámot/árat nem csökkentjük titokban.
Indításkor a képmanifest és sorrend befagy. Kép hozzáadása/törlése/sorrendváltás már létrejött jobon nem lehetséges; dispatch előtt cancel/release után új operation. A jóváhagyott és backend által elfogadott készletnek egyeznie kell.
Nincs automatikus mentés, RecipeTextParser roundtrip, webfetch, OCR-only, ML Kit vagy multi-recipe import. A már feldolgozott valid job cancelje nem ad vissza creditet.
Android multi-select Photo Picker preferált; I1 ellenőrzi a lockolt AndroidX API-t és valódi maximum viselkedését. Fallback SAF ACTION_OPEN_DOCUMENT többválasztással, Dart oldali hard5 ellenőrzéssel. Nincs broad storage permission vagy image/* manifest handler. [Korábban ellenőrzött Android Photo Picker dokumentáció](https://developer.android.com/training/data-storage/shared/photo-picker).
Külön image channel, meglévő text/K2K út érintetlen. image4.9.1 direct dependency jelölt azonos lockolt verzióval; picker plugin csak bizonyított szükség esetén. I0.1 dependencyt nem módosít.

## 3. Per-image és összesített preprocessing – engineering javaslat

Végleges képszám:1–5; az alábbi byte/pixel értékek benchmarkkal és transportprototípussal validálandók:
- JPEG/PNG input; HEIC/WebP/GIF/PDF kontrollált unsupported. Minden kép külön validálódik, nincs csendes frame/oldalválasztás.
- Eredeti kép≤20 MiB,≤24 MP, oldal≤12000px; összes input≤100 MiB/120 MP. Header/dimension vizsgálat full decode előtt; sérült/decompression-bomb reject.
- Képenként orientation correction → metadata/EXIF/GPS/thumbnail nélküli újrakódolás → max2560px hosszabb oldal,≤6 MP, aspect ratio megtartása, nincs upscale; JPEG quality90/fehér alpha háttér javaslat.
- B változat transporthoz képenként≤3 MiB, összes derivátum≤15 MiB/30 MP. Ezek külön capek, mindegyik teljesítendő. Az A változat ennél alacsonyabb transportcapet igényel (7. fejezet).
- Egyszerre egy full decode/isolate feladat; fájlalapú derivátumok, kis thumbnailek. Nem öt bitmap és öt base64 másolat memóriában. Decode előtt size probe; szerver újra validál.
- **Minden kép kész/valid legyen reservation és providerhívás előtt.** Egy hibás kép az egész indítást blokkolja; user javít/töröl. Nincs részleges készlet-import, nincs local invalid miatti reserve.
- A user sorrendje és stabil clientImageId a preprocess után is megmarad. Túl nagy/olvashatatlan kép nem tömörül titokban használhatatlanra; nincs automatikus screenshot-feldarabolás.
- Server pre-dispatch validation is all-or-nothing; eltérő tényleges bytes/hash/MIME, invalid kép vagy összlimit esetén nulla providerhívás, teljes N release, ha már volt reservation.

## 4. Structured AI schema V1

A példa egy legalább háromképes job egyetlen outputja (imageIndices zero-based). Provider structured output, ha elérhető; backend önálló validáció minden esetben. Minden object additionalProperties:false; minden felsorolt mező required.

```json
{
  "schemaVersion":1,
  "outcome":"recipe",
  "recipe":{
    "name":"Túrós süti",
    "ingredients":[{"name":"túró","quantity":50,"unit":"dkg"}],
    "spices":[{"name":"só"}],
    "preparation":"Keverd össze.\nSüsd meg."
  },
  "warnings":[{"code":"truncatedContent","path":"/recipe/preparation","imageIndices":[2]}]
}
```

Extraction schema, nem persistált canonical Recipe:
- schemaVersion int1; outcome recipe/noRecipe/unreadable/multipleRecipes. Nem recipe outcome-nál recipe=null.
- name string|null max200; preparation string|null max50000; ingredients≤200, spices≤100.
- Ingredient name string|null max300, quantity finite positive number|null (javasolt cap1e9), unit string|null max32. Missing/range/olvashatatlan nem alapértelmezett1/db.
- Spice name string|null max300; mennyiséggel szereplő fűszer ingredient marad, mert RecipeSpice csak nevet tárol. Nem duplikáljuk.
- Warnings≤100, exact code/path/imageIndices: missingTitle,missingQuantity,uncertainQuantity,missingUnit,unknownUnit,unreadableIngredient,unreadableSection,truncatedContent,ambiguousSection,multipleRecipes,overlapUncertain,possibleDuplicate,missingContinuation,orderUncertain,unrelatedImage. imageIndices unique int lista a 0…N−1 tartományból; üres lista job-szintű warningnál. Path≤128 és létező mező/index. Nincs szabad HTML/link/action.
- UTF-8 JSON≤256 KiB, depth≤8; unknown key/type/version, invalid Unicode, NaN/Infinity reject.
- Nincs kalibrálatlannak tekintendő numerikus confidence százalék. Null és field warning kell. Server saját missing/unit/limit warningot is ad; nem bízik a modell warningteljességében.
- Provider/model/prompt/schema version operation metadata, nem Recipe mező. Képindex/evidence csak temporary import adat, nem normál log/persistált recept. A képindex nem kép-URL; a result retrieval nem ad hozzáférést törölt képekhez.

## 5. Normalizálás / hallucination safety

AI raw structured → backend validate → exact normalization → temporary draft; Flutter újra validál. Dart/TS közös golden fixtures, nem szövegparsing.
Canonical AI V1: g,ml,db,kg,l,tk,ek; kk→tk; dkg×10→g; dl×100→ml. ImportUnitNormalizer recognize/convert szemantikája reuse, hét-egységes allowlisttel; nincs normalizeForImport display-kerekítés.
Bögre/csipet/csomag és más nem engedett unit: raw evidence megmarad, canonical=null, user javít. A csomag meglévő domain-tagsága önmagában nem írja felül az AI policyt. Tartományból nem választunk önkényes számot.
Hiányzó cím üres editmező; hiányzó mennyiség/név/unit javítandó, mentés blokkolt. Olvashatatlan sor warning, nem kitalálás. Hiányzó preparation üres + warning, user tudatos elfogadással menthet.
A provider instrukciója: az ordered images[] EGY recept egymást követő/kiegészítő részei. Az összes képet együtt értelmezze, kövesse a sorrendet, illessze össze a hozzávalókat és elkészítést. Kétoldalas és ötrészes recept natív V1 use case.
Átfedő screenshoton azonos sor/mondat/step csak bizonyított szöveg- és környezetegyezéskor szerepeljen egyszer. Külön receptszakaszban jogszerűen ismétlődő „cukor/vaj” nem törölhető névegyezés alapján. Bizonytalan overlap/duplikáció warning, nincs agresszív dedupe vagy mennyiségösszegzés.
Rossz sorrend automatikus javítása nem ígéret; orderUncertain/missingContinuation warning. Levágott első/utolsó rész nem hallucinálható. A user a sorrendet előzetesen ellenőrzi.
Multi-image nem multiple recipes: ha a készlet két külön receptet tartalmaz, outcome=multipleRecipes, recipe=null. Nincs egyik recept önkényes kiválasztása vagy multi-import. Nem recept jellegű közbeékelt kép unrelatedImage warninggal figyelmen kívül hagyható, de a teljes N feldolgozott készletért N credit jár; ha emiatt nem állítható össze recept, unreadable kontrollált outcome.
Díszítőszöveg/reklám/komment kimarad; bizonytalan section warning. Képen lévő utasítás untrusted adat: nincs tool/web/link-végrehajtás. Valid schema sem bizonyít tartalmi pontosságot.

## 6. Editor integráció

Teljes valid content → közös pure RecipeContent mapper → Recipe(id:null) → initialRecipe. K2K envelope/version változatlan.
Hiányos AI-outputot NEM erőltetjük a K2K decoderbe. RecipeImportDraft minimális kompatibilis kiterjesztése spices-re, unit-review/nullable állapotra és warningokra szükséges; initialImport jelenlegi spices.clear/preparation mapping felülvizsgálandó. Text parser régi viselkedése megmarad.
Egy közös editor-prefill adapter, nem harmadik Recipe mapping. Warningösszegzés + érintett mezőjelölés + releváns 1…N képsorszám (a zero-based index UI-konverziója); hiány javítása vagy sor törlése; nincs érvényesnek látszó kitalált default. Metadata nem kerül Recipe-be.
Existing névütközés validation, user átnevez; nincs overwrite/merge. Cancel nem ment. Read-then-create uniqueness concurrency korlát már létezik; az AI ezt nem oldja meg.

## 7. Multi-image transport audit / backend boundary

Öt3 MiB derivátum15 MiB binary; base64 méret4×ceil(bytes/3), itt összesen20 MiB plus JSON/mezők. Az előző4.5 MiB-os requestcap **nem használható** ehhez. Ez aritmetika, nem aktuális platformlimit-állítás; I0.1 nem hívott API-t és nem végzett live quota auditot.

| Változat | Konkrét méret/előny | Hátrány / döntés |
|---|---|---|
| A: egy authenticated callable, images[] inline bytes | Pl.≤768 KiB/kép,≤3 MiB total binary; kb.4 MiB base64 + overhead, saját≤4.5 MiB request. Nincs backend image storage. | 5 részletes oldal 768 KiB-os és total capje ronthatja minőséget; egy retry minden képet újraküld; memória. Csak benchmark és SDK/platform payload teszt után választható. Nem végleges base64 contract. |
| B: privát temporary upload + job references | Javasolt≤3 MiB/kép,≤15 MiB total; kis control request, külön bounded binary uploadok; képminőség és hálózati recovery jobb. | Temporary storage/access/cleanup és upload endpoint kell. **Ajánlott irány**, exact transport még open decision. |
| C: egy authenticated HTTPS multipart stream, tárolás nélkül |≤15 MiB binary + multipart overhead, nincs base64; egy request. | Middleware esetleg bufferel, hosszú mobil kapcsolat, whole-job retry és process crash után nincs kép-recovery; callable helyett explicit token/App Check validáció. SDK/runtime streaming és limit igazolása nélkül nem release-ajánlat. |

B ajánlott design: v2 callable control/status a meglévő cloud_functions klienssel; **authenticated HTTPS binary upload proxy**, amely private temporary storage-ba ír. Nem public/signed bearer download URL, nincs Firebase download token, nincs broad bucket access. Flutter upload API/key nincs providerhez. Direct Storage SDK nem szükséges ehhez a változathoz; dart:io HttpClient használható, pluginigény I4-ben auditálva. Server SDK storage elérhetőség és stream/backpressure külön prototype-kapu.

Control request≤64 KiB, minden mező exact:
```json
{
  "schemaVersion":1,
  "operationId":"UUID",
  "images":[
    {"clientImageId":"UUID","mimeType":"image/jpeg","byteLength":1200000,"sha256":"hex"},
    {"clientImageId":"UUID","mimeType":"image/jpeg","byteLength":1500000,"sha256":"hex"}
  ]
}
```
images1–5, unique clientImageId; array order a jóváhagyott sorrend. UID/model/prompt/creditCost/storagePath/providerURL nem client authority. Hash/length állításokat a backend bytes-ból ellenőrzi. Digest a teljes ordered listát, képidentitást, bytehash-eket és schema verziót köti az operationhöz; sorrendváltoztatás is conflict. N=count, nem kliens által szabadon megadott ár.

1. Minden local kép valid → user jóváhagyja N-t → prepareImageImport: Auth/App Check/ACTIVE/account generation/rate/budget + manifest validation → atomikus N reservation, immutable manifest, server upload slotok és lejárat.
2. Upload: operationId+slotId, auth/session-bound; a proxy kizárólag server által kiosztott objektumkulcsra, deklarált és tényleges per-image/total cap alatt írhat. Nincs client path vagy tetszőleges object read/list. Partial bytes izolált, completed-object atomic promotion; stream hiba cleanup.
3. Minden slot validált MIME/magic/dimension/hash után ready. Azonos slot/azonos bytes retry idempotens; más bytes conflict. Nincs committed slot overwrite; object generation/fingerprint befagyasztása védi a validate→dispatch versenyt.
4. processImageImport({operationId}) csak hiánytalan, expiry előtti N ready slotot sealelhet. acceptedImages.length=N és manifestegyezés kötelező; **nem dolgozhatja fel a valid részhalmazt**, nem terhelhet kevesebbet/többet titokban. Server invalid/hiány esetén no dispatch; javítás új jobbal, régi N release.
5. Egy lease-fenced provider dispatch az ordered images[] készlettel; API I/O tranzakción kívül. Egy output → strict validáció/normalizálás → atomic result+N finalize vagy teljes release. Response≤256 KiB.

getImageImportOperation/balance own UID only; private imageeket státuszválasz nem ad vissza. Minden upload/claim/commit ACTIVE/generation/expiry ellenőrzés. Transient upload retry same slot/op; process retry status, nem automatikus új providerhívás.
Javasolt időkeretek: upload-idle10perc és abszolút30perc; provider60s, process120s, kliens130s, lease150s. Lease vége nem engedély a bizonytalan dispatch megismétlésére. Pontos platform/SDK/request/time limitek I4-ben ellenőrizendők. [Korábbi Firebase quota referencia](https://firebase.google.com/docs/functions/quotas).

Provider abstraction: `extract({images:[{bytes,mimeType,index}],schemaVersion,promptVersion,operationKey,deadline})`. Egy hívásban mind1–5 kép; candidate kizárandó, ha csak képenkénti extraction+merge út lehetséges. Ha provider file-upload API-t igényel, az csak ugyanazon job input-előkészítése, nem N extraction; külön provider-file cleanup feltétel. Preferált inline provider multi-image request szerveroldalról.
Fake és később real adapter; server model/config, Secret Manager secret külön a HMAC-től. Nincs APK-secret, import-time hálózat, UID/email a providernek, tool/web/URL-input vagy raw exception kifelé.

## 8. Privacy / temporary image lifecycle

**PERSISTENT IMAGE RETENTION: NONE – végleges.** B transport esetén kizárólag rövid életű, privát, jobhoz kötött staging; nem receptkép-tár, nem backup/galéria. Eredeti képek a user eszközén; provider csak metadata-stripped derivátumot kap.
- Private temporary bucket/prefix: public access deny, kliens közvetlen read/write/list deny; kizárólag szűk runtime identity. Minden proxyhozzáférés UID/accountGeneration/operation/slot bound. Nincs public image URL vagy tartós download token.
- Local saját derivátumok és thumbnailek cancel/terminal után törlődnek; crash esetén következő appindulás saját-prefix cleanup. Az eredeti képekhez nem nyúlunk. Egy live selection session local previewja maradhat az editor bezárásáig, nem tartós galéria.
- Success: provider válasz után nincs több szükség uploadokra; idempotens delete minden slot+partial objektumra, a result/credit már tartós. Definite failure/cancel pre-dispatch: teljes N release és minden objektum törlése. Cleanup failure nem vált ki új providerhívást vagy második creditsettlementet.
- Upload félbeszakadás: partial cleanup; expired staging job atomikus abort+release N, upload jog azonnali megszűnés. Régi retry nem hozhatja vissza a törölt objektumot; tombstone/expiry és immutable slot fencing.
- Crash/UNKNOWN: operation row tartalmaz imageExpiresAt és cleanupPending; javasolt hard access expiry≤1h a létrehozástól, nem hosszabbítható retryval. Nincs image retry a korlát után; outcome-reconciliation status alapján, kép újraküldése nélkül.
- Bounded maintenance≤5perc cadence, paginált lejárt/pending cleanup; storage lifecycle extra backstop, TTL önmagában nem garantál azonnali törlést. Normál üzemben expiry+egy sweep a cél; cloud outage esetére fizikai törlés exact wall-clock garanciája nem ígérhető. Access az expiry után azonnal deny, retry/backlog-age alert kötelező; release blocker, ha purge-recovery nem igazolt.
- Account deletion: DELETING azonnal tilt új reservation/upload/process/result deliveryt; teljes operation rendezése generation-fenced, temporary slot/partial és draft inventory purge. Fallback/Auth deletion és crash sweep is ugyanazt a cleanupot használja; nincs transfer. In-flight provider valid eredménye a rögzített jobpolicy szerint rendezhető, de nem aktivál accountot és nem adható új UID-nak.
- Provider retention/training/region és esetleges provider file cleanup külön kiválasztási kapu. Kuktám temporary törlés nem bizonyít provider zero-retentiont.
- Validált draft/warning result javasolt≤24h recovery (OPEN), képektől külön. Expired resultot nem szolgálunk ki; bounded purge. Content nélküli credit/idempotency audit retention külön policy.
Nincs raw kép/base64/recipe/AI response/URI normál logban. Törlési metrikák technikai object ID/count/age szintűek; nincs user filename vagy tartalom.

## 9. Session és state machine

Login AI/reservation előtt. UID+lokális session generation+operationId capture; A→B→A új session. Backend ACTIVE/account generation prepare/upload/seal/commit során; más account nem kap eredményt/creditterhelést.
Client: noImages→imagesSelected→preparingImages→readyToImport→reservingCredits→uploading/sending→processing→validating→ready; error/canceled ágak. Előkészítési hiba visszavisz a szerkeszthető képlistához, reserve nélkül. Balance<N vagy készülő/hibás kép tiltja indítást.
Add/remove/reorder még operationindítás előtt invalidálja a korábbi ready manifestet és költségjóváhagyást; creditCost=images.length mindig friss. Reserving után immutable snapshot; új sorrend/kép új job, nem folyamatban lévő payloadmutáció.
Backend: RESERVED/UPLOADING→READY_TO_DISPATCH→DISPATCHING→SUCCEEDED/FAILED_TECHNICAL/REJECTED_CONTENT/UNKNOWN_PROVIDER_OUTCOME. cleanupPending külön operational flag; credit NOT_RESERVED→RESERVED(N)→FINALIZED(N) vagy RELEASED(N), nincs partial settlement.
Background: provider job nem indul újra, editor csak resumed/current route mellett. Logout local képek/result elrejtés; backend a régi UID jobját rendezheti. Account switch purge-öli a lokális pending state-et.
App kill: saját UID-hoz kötött op ID recovery statusra; elkészült result újraauth után elérhető lejáratig. Partial uploadot nem kezdünk automatikusan más accounttal/új képekkel: same-job folytatás csak azonos manifest/bytehash és érvényes slotok mellett; egyébként abort/release és új explicit selection. Nincs tartós cloud image inbox.

## 10. Credit architektúra / Play

Külön backend-only CreditStore: aiCreditAccounts/UID(available,reserved,revision), aiImportOperations/dedupeKey, aiCreditLedger/entryId. Client write deny, saját minimal balance callable. Pro grant/LifecycleStore nem creditwallet.
Integer balance≥0; **N=acceptedImages.length, 1≤N≤5; 1 kép=1 credit végleges.** Prepare a befagyasztott N manifestre atomikusan available−N/reserved+N; dispatch csak ha minden N kép accepted. Valid recipe/noRecipe/unreadable/multipleRecipes: reserved−N + N consumed entry + egy result egy atomic commitban. Definite technical fail: reserved−N/available+N egyszer. Local validation failure előtt nincs reservation; server pre-dispatch fail esetén a már létező teljes N reservation released. Kliens nem ír balance-t és nem kér önkényes refundot.
Pro≠credit. Text/shopping/K2K/export Free; scaling/Mit főzzek Pro; image AI credit. imageImport Pro placeholdert külön capability váltja. Bónusz/kedvezmény nincs véglegesítve. Kupon később csak trusted issuer+idempotens redemption, nem kliens-claimelt mennyiség.
Play: **one-time consumable credit pack**, külön product allowlist/pack→credit mapping. Server verification után tartalomjóváírás, consumable consumption; a consume az acknowledgementet is teljesíti. [Google Play Billing](https://developer.android.com/google/play/billing/integrate).
Trusted lookup/binding/ownership → tokenHash alapján egyetlen durable topup → backend consume tranzakción kívül, lease/retry. Pending nem ad creditet, token replay/consume utáni crash nem topupol újra. Kliens auto-consume/complete nem kell a választott backend ownership mellett.
A jelenlegi lifetime NO CONSUME változatlan. Külön purchase-purpose/schema/consume adapter kell; a Pro-garantáló PurchaseVerifier átconfigolása nem elég. Shared transport/binding/error/fencing minták reuse; lifetime grant writerből nem credit íródik.
Refund/revoke: topup purchase provenance/credit lot megmarad; el nem költött rész visszavonás/zárolás, elköltött rész explicit review/debt-policy döntés. Pro entitlement/mentett receptek nem változnak emiatt. Credit restore backend ledgerből, nem consumed token újragrantolásból.

## 11. Job-szintű idempotency / retry / all-or-nothing credit

Dupla tap: client busy, ugyanaz operationId; backend UID+ID+ordered manifest hash. Egy5 képes job nem foglalhat10 creditet, nem kaphat két provider dispatch-et. Azonos aktív op status/busy, terminal op azonos eredmény. Nincs content-hash alapú örök dedupe két szándékos új próbára.

| Eset | Dispatch / retry | Credit és kép-lifecycle |
|---|---|---|
| Bármely local kép invalid | Nem prepare/upload/provider | Nincs reserve/consumption; user javít/remove |
| Auth/balance/rate/manifest reject prepare-nél | Nem | Nincs reserve |
| Prepare siker, upload hálózati hiba | Same op/slot bounded retry, expiryig | N reserved marad; cancel/expiry release N + cleanup |
| Server bármely képet elutasít, hiányzó slot/total cap | Nincs részhalmaz dispatch | Release N, no consumption, cleanup; javítás új operation |
| Biztos pre-dispatch crash | Lease után same job kontrollált folytatás | Ugyanaz N reserve, feltéve készlet/expiry valid |
| Provider timeout/crash, bizonytalan kimenet | UNKNOWN, nincs vak redispatch | N együtt pending; status ha támogatott; resolution deadline után technical release N/operator review ajánlat |
| Definite backend/provider technical fail, akár csak1 kép feldolgozása hibás | Egész job fail, nincs félrecept | Release N egyszer; Kuktám viseli esetleges részleges providerköltséget |
| Malformed/schema-invalid/truncated technikai válasz | Nincs automatikus repair-model hívás | Release N; nincs partial draft success |
| Valid recipe/noRecipe/unreadable/multipleRecipes | Egy befejezett próbálkozás | **Finalize N**; rossz képminőség/szubjektív elégedetlenség nem automatikus refund |
| Valid részleges recept warningokkal | Egy javítható output | Finalize N; bizonytalan forrástartalom nem technical fail |
| Provider success után local commit/client disconnect | Same op result/status, nem új dispatch | Atomic result+N settle; credit és draft nem duplikálódik |
| Cancel dispatch után | Abort nem garantált | Valid outcome finalize N; technical fail release N; nincs képenkénti settlement |

A provider képenként/tokenenként számlázhat, akár3 képnél már költség merült fel, mielőtt az5 képes job technikailag hibázik. Ez internal cost, nem3-credit user charge: a teljes reservation released. A globális cost budgetből actual/uncertain usage nem tűnik el a usercredit release miatt.
Firestore és provider között nincs közös tranzakció: provider exactly-once nem ígérhető provider-idempotency nélkül. Dispatch marker/network send közti crash is UNKNOWN. Automatikus lease takeover nem indíthat még egy extractiont. Creditsettlement egyszeri; released job late success nem terhelheti vissza N-t. UNKNOWN maximális rendezési ideje/operator policy továbbra engineering döntés, nem új partial-credit modell.

## 12. Abuse / App Check / observability

Max1 active job/user,≤5 kép/job; javasolt3 job-start/perc,20 job/nap ÉS50 submitted image/nap, technical kísérletekkel együtt; upload byte és polling külön rate/quota. Egy manifest nem szerezhet korlátlan új slotot vagy staging időt. Minden fizetős dispatch előtt reservation. Globális napi providerbudget + in-flight worst-cost reservation kell: technikai failure/refund sem okozhat ingyen végtelen API-loopot.
Server token/output cap, modell allowlist, alacsony maxInstances/concurrency, timeout, account/rate/image validation. MaxInstances és budget alert önmagukban nem hard cost cap. UNKNOWN költsége foglalva marad reconciliationig. Globális limit összege user-döntés.
App Check AI production release-kapu ajánlott: configure→monitor belső testen→hibák javítása→nyilvános fizetős AI endpoint enforce. Most nincs beállítva, nincs azonnali globális enforcement. Auth/credit/rate limitet nem helyettesíti.
Log/metrics: recipe jobs, accepted image count, total byte/pixel bucket, outcome, latency/job, provider/model/prompt version, overlap-warning count, N credit finalized/released, provider actual usage, cost/job és cost/image, cleanup backlog age. Nincs raw kép/JSON/recipe/URI/auth/purchase token vagy UID+content dump.

## 13. UI/UX és hibák

Receptek import entry: „Recept képből – AI kredit”; text import külön Free. Import előtt sorszámos képlista, N kép, szükséges N credit, aktuális balance és „Importálás – N kredit”; explicit jóváhagyás, nincs surprise charge. Előre látható: noRecipe/unreadable/multipleRecipes is feldolgozott próba és N credit, technical job failure teljes release. Profilban külön credit balance/vásárlás, nem Pro badge. Nincs credit → hívás előtt kontrollált állapot/csomaglista, nem automatikus vásárlás.
Hibák: nincs internet; túl nagy/nem támogatott/sérült kép; nincs recept; kevés olvasható tartalom; több recept; átmeneti szolgáltatáshiba; nincs credit; account megváltozott; feldolgozás állapota ellenőrzés alatt. Reservation/finalized/released külön látható, raw providerhiba nincs.
Offline AI nem indul, Free appfunkciók a meglévő policy szerint működnek. Későbbi onboarding „Képen van a recepted?” erre az entryre mutathat, a költségelőnézetet nem kerülheti meg; onboardingot most nem készítünk.

## 14. Provider shortlist – előszűrés, nem modellválasztás

- Google Gemini vision/structured-output termékvonal költségtakarékos jelöltje.
- OpenAI multimodális structured-output képes költségtakarékos modelljelölt.
- Anthropic Claude vision képes kisebb/közepes jelölt, schema-megbízhatóság külön mérve.

Konkrét model ID, elérhetőség, ár, image-tokenizálás, retention/régió itt NINCS igazolva; nem állítunk aktuális „legjobb modellt”. **LIVE WEB RESEARCH REQUIRED BEFORE BENCHMARK.** A repo nem tartalmaz hiteles AI rate cardot. Az eredeti I0 csak hivatalos Android/Firebase/Play platformdokumentációt olvasott. I0.1-ben új webkutatás, API-hívás, AI-provider kutatás vagy benchmark nem futott. A shortlisthez multi-image1–5 support, image-count/context limitek és privacy is kötelező előszűrés.

## 15. Multi-image benchmark – recipe-job dataset és költség

A dataset egysége **receptjob**, nem egy kép. Ajánlott15 job/32 kép-előfordulás (átfedés/reorder ugyanazt az assetet is újrahasználhatja). User által kiválasztott, jogszerű, nem érzékeny anyag, job-szintű kézi ground truth; képindex/sorrend és látható átfedés annotálva. Nincs email/arc/GPS/private üzenet. TikTok/web itt csak screenshot-forrás, nincs scraping/webimport.

| Kör | Job | Képszám | Elvárt mérés |
|---|---|---:|---|
| A | 1. Tiszta screenshot | 1 | Egy pontos recept |
| A | 2. Hozzávalók + elkészítés külön | 2 | Cross-image egyesítés |
| A | 3. Hosszú recept három részben | 3 | Teljes sorrend és tartalom |
| A | 4. Hosszú TikTok/web recept öt egymást követő screenshoton | 5 | Maximum V1 job, egy draft |
| A | 5. Részben átfedő screenshotok | 3 | Duplikáció nélkül, jogos ismétlések megőrzése |
| B | 6. Levágott első/utolsó kép | 2 | Missing/truncated warning, nincs találgatás |
| B | 7. Rossz sorrend exploratory | 3 | Order uncertainty; nem ígért automatikus javítás |
| B | 8. Oda nem tartozó kép a setben | 3 | Unrelated warning, nincs recipe-mixing |
| B | 9. Két külön recept képei | 2 | multipleRecipes, nem multi-import |
| B | 10. Gyenge fényű fotó | 1 | Olvashatóság/uncertainty |
| B | 11. Perspektivikus könyvoldal | 1 | Ingredient/unit accuracy |
| B | 12. Két hasábos újságoldal | 1 | Section separation |
| B | 13. Apró betűs kétoldalas recept | 2 | Folytatások és mennyiségek |
| B | 14. Díszített közösségi recept, overlap | 2 | Zaj kizárás, completeness |
| B | 15. Nem recept / nagyon kevés olvasható szöveg | 1 | Kontrollált noRecipe/unreadable |

A kör5 job/14 image;3 modell×5 job=15 provider extraction request,**42 image input**.
B kör10 job/18 image;top2×10 job=20 request,**36 image input**.
Összes maximum35 extraction request,**78 képbemenet modellfuttatásokkal számolva**. Nem78 egyedi asset és nem35 kép. Egységes prompt/schema/preprocess, nincs automatikus retry vagy külön modellenkénti extra tuning. Provider file-upload/API mellékhívások, ha vannak, külön számolandók; nem plusz extraction jobok.
**USD5 hard ceiling javaslat megmarad**, nem költségbecslés vagy mostani spend-engedély. I3 official candidate rate/privacy/5-image support kutatás után input-resolution/detail/image-token + text/output + esetleges file/service költség alapján újraszámolás. Nem lehet requestcount×egy-kép-költséggel tervezni.
Harness minden dispatch előtt a **teljes job** worst-case költségét foglalja; actual+outstanding≤cap. Ismeretlen rate/max-image/token-limit→STOP; timeout költsége foglalt marad. Cap túllépés előtt megáll; user jóváhagyással kisebb közös dataset/kevesebb candidate lehet, de a kötelező5-image/overlap/multipleRecipes eset nem hagyható el csendben. Ha nem fér bele, eredmény INCOMPLETE, nem költségtúllépés.
Kötelező napló: jobcount, total submitted images, image-count histogram, actual provider usage, cost/job, cost/image, latency/job és peak input size. Credit N nem azonos provider dollárköltséggel.

Fő metric továbbra **kézi javítási idő és módosítások száma egy menthető recepthez**, medián/p90, kézi baseline, vakított modellazonosító.
Recepttartalom score100: title5, ingredient name15, quantity25, unit15, spice5, preparation20, section separation5, completeness10. Külön multi-image scorecard: összefűzés helyessége, duplikált sor/lépés száma, omitted overlap/non-overlap tartalom, preparation order, ingredient completeness, cross-image hallucination, wrong-recipe mixing. Ezek nem tűnhetnek el egy átlagpontszámban.
Missing külön guessed-től; uncertainty warning helyessége, schema-valid arány, noRecipe/multipleRecipes kimenet, cost/usable recipe külön mérendő. Candidate kizárandó, ha5 képet nem lát együtt vagy önkényesen félkészletet dolgoz fel.
Release-kapu: contracttests PASS; nincs észrevétlen wrong-recipe mixing/kitalált mennyiség a mintában; javítási idő előny és elfogadható p90/cost user jóváhagyva. 15 job nem statisztikai garancia, zárt real-device QA még kell.

## 16. Production korlátok

A) Most lokálisan elkészíthető: multi-select/reorder/preprocess/cost-preview shell, structured draft/editor/warnings és fake multi-image provider. A teljes credit/backend monetizációt csak I3 benchmark után építjük; egy korai fake cost-label nem wallet implementáció.
B) Parkolt Spark mellett live Functions/Secret/AI end-to-end nincs. I3 helyi, fejlesztő által futtatott capped benchmarkhoz nem kell Firebase deploy vagy kész creditwallet, de provider billing/secret és külön költségengedély igen. Ez nem appból bárkinek elérhető credit nélküli endpoint.
C) Fizetős release EV/business/merchant, külön engedélyezett Blaze/infra, Play consumables/testerek, real purchase/consume/refund QA után.
User-facing AI endpoint nem kapcsolható be működő credit-authority/global cost guard nélkül. Temporary storage esetén private bucket/access/expiry/purge monitor és account deletion inventory is release-kapu. A külön fejlesztői benchmark nem kerül az APK-ba vagy nyilvános szolgáltatásba.

## 17. Frissített implementációs sorrend

**A provider benchmark I3, a teljes transport/backend I4, a credit operation architektúra I5.** Előbb bizonyítjuk az1–5 képes egyrecept-felismerést és költséget, csak utána építünk monetizációs rendszert. I4 real adapter source is lokális/mock marad I5–I8 előtt, nincs user-facing credit nélküli providerút.
Új fájlnevek tervezett helyek. Minden fázis ellenőrzés/STOP; live művelet csak külön user-authorizációval.

| Fázis / cél / várható source | Dependency; backend/Firebase/Play | Teszt/manual | Blocker / production előfeltétel |
|---|---|---|---|
| I1 – MULTI-image picker, add/remove/reorder, sorszám, preprocess, N-credit preview, UI shell; lib/image_import/input/*, Android ImagePickerBridge | image4.9.1 direct jelölt; multi-picker AndroidX audit; B/F/P nincs |0/1/5/6 képek, maradékhely, sorrend, invalid egyik kép, caps/memória; telefon galéria/screenshot/cancel | Per-image/total engineering cap; fake balance, sem reserve sem provider |
| I2 – multi-image request/ordered-manifest, structured output/draft/editor, overlap/missing warnings; image_import/domain/*, RecipeImportDraft/AddRecipeScreen/content validator | Új dep nem feltétlen; B/F/P nincs | index/range/warnings, exact unit, spices/hiány, egy draft; K2K/E1/text regresszió, fake5 kép→editor | Figyelmeztetési UX/schema; nincs AI szövegparser |
| I3 – live provider/rate/privacy research + capped JOB benchmark; tools/image_benchmark/* | SDK csak külön audit; nincs appbackend/Firebase/Play | offline harness dry-run/cost stop, majd külön engedéllyel15 job/max35 dispatch/78 input | Provider multi-image támogatás és USD cap; nincs előzetes wallet kiépítés |
| I4 – nyertes provider adapter + transport prototype; functions/src/ai/adapters/*, uploads/*, runtime injection | Server decoder/storage stream szükséglet audit; B local, F emulator/fake storage, P nincs | Mock provider5 image ordered; byte/pixel/manifest validation, immutable upload/cleanup crash, SDK payload/time/memória | I3 eredmény, A/B/C végső választás; B live storage még nem deploy |
| I5 – N-credit job reservation/finalize/release/idempotency/rates; functions/src/credits/*, ai/job-store | Meglévő Admin/Firestore; B local/F rules-emulator/P nincs |N=1..5 atomic, duplicate5≠10, invalid slot no dispatch, partial provider fail release N, late workers/generation, deletion cleanup | UNKNOWN deadline/global budget/result retention engineering döntés; semmi live |
| I6 – Play consumable topup/consume/refund; credits/purchases/*, billing purpose routing | Billing dep audit; B local/F emulator/P fake | Topup once, pending, consume crash/refund/debt, lifetime no-consume regresszió | Pack ár/méret/refund policy; termékek még nem jönnek létre |
| I7 – teljes UI/auth/upload/status/recovery és credit balance; image_import controller/transport/profile | Control cloud_functions meglévő; B transport kliens dart:io jelölt; nincs live F/P | Cost consent N, dupla tap, reorder freeze, upload resume, logout A→B→A/kill/expired, egyeditor explicit save; device fake | I4/I5/I6 kész, feature switch off |
| I8 – külön jóváhagyott production wiring | Blaze/API/IAM/Secret/Functions; B-nél private staging bucket/rules/cleanup; Play merchant/consumables/tester | Minden módosítás smoke/rollback; bucket deny/no URL, expiry/purge, App Check monitor→AI enforce | EV/business+külön user jóváhagyás, credit/cost guards/privacy/deletion |
| I9 – zárt release QA és enable | Új dep nincs; jóváhagyott B/F/P QA |1/2/3/5 képes valódi jobok, overlap/wrong order/wrong recipe, Play/technical release, crash/outage/purge/full regresszió | Nincs P0/P1, minőség/cost, App Check és transport-limit igazolva |
| I10 – későbbi onboarding és app QA | UI-only ugyanebbe az entrybe; új B/F/P nincs | „Képen van a recepted?”→ordered képlista/N-cost consent; cancel | Külön onboarding scope, most nincs implementáció |

B/F/P = backend/Firebase/Play; emulator/local állapot nem production erőforrás-módosítás. I3 benchmark és I8 live wiring külön engedélyezendő; I0.1 egyiket sem indítja.

## 18. Multi-image tesztstratégia / kockázatok

Unit: images1–5 bounds, ordered manifest hash (sorrend is számít), unique imageId, add/remove költség, N-credit matek, per-image ÉS összes byte/pixel limit, egy invalid kép→no reserve/provider, warning source index/overlap/order/multipleRecipes; DTO/UTF8/NaN/unit precision és draft reuse.
Widget: multi-select,1…5 sorszám, reorder/add/remove,6. kép reject, balance<N tiltás, „Importálás – N kredit”, ready freeze, minden valid→indítás, warning/editor/cancel/explicit save. Free text/shopping/K2K/export és Pro scaling regresszió.
Backend: atomic N reserve/finalize/release,5 kép dupla tapja nem10, slot ownership/immutability/hash/expiry/generation, cross-UID/object path támadás, incomplete/invalid set no dispatch, egy ordered providerhívás/egy result, részleges providertechnical fail teljes N release, valid noRecipe/unreadable/multipleRecipes finalize N, UNKNOWN/late worker, global job+image+cost budget.
Privacy integration: success/failure/cancel/partial upload/crash cleanup, account deletion, expired access deny, sweep-pagination/outage-recovery/alert; nincs public image URL vagy raw log. Testek fake storage/providerrel, unitban nincs hálózat.
Manual:1/2/3/5 kép→egy draft, kétoldalas és öt screenshot, overlap, levágás, wrong-order, unrelated/multipleRecipes; telefon picker/providerlimit, memória/háttér/kill/uploadresume. Később engedélyezett benchmark és Play/topup/consume/refund QA.
Fő kockázatok: multi-image mixing/hallucináció, agresszív overlap dedupe, képvesztés/sorrendhiba, image-token költségnövekedés, kliensmemória/transport buffer, temporary purge outage, bizonytalan provider timeout, új consumable domain, kis benchmark és nem live infra. Mindezek release-checkpointok, nem már igazolt képességek.
Nem cél: több recept importja, képenkénti extraction+client merge, webimport, promptból receptgenerálás, meal planner/nutrition AI, image generation/gallery, social/family/bulk OCR vagy automatikus recipe save/background batch.

## 19. Végleges döntések és valóban nyitott kérdések

**FINAL – nem újranyitandó:** MULTI-IMAGE V1;1–5 kép;1 operation=1 recept/1 draft; galéria/screenshot igen; közvetlen kamera nincs;1 feldolgozott kép=1 kredit; valid recipe/noRecipe/unreadable/multipleRecipes→N finalized; definite technical failure→teljes N release; persistent image retention NONE. Nincs képenkénti részleges user settlement.

Nyitott engineering/árdöntések:
1. Exact per-image/total preprocessing byte/pixel/resolution/compression cap a multi-image benchmark alapján.
2. Exact transport A/B/C; **B ajánlott**, temporary upload/access/expiry/purge validáció és staging retention időablak jóváhagyása.
3. Provider/model, multi-image context/image limits, actual usage/költség/job és kép, provider retention.
4. USD5 benchmark cap jóváhagyása és rate card alapján beleférő futási terv; most nincs spend-engedély.
5. Credit pack ár/méret/expiry, Play refund/debt szabályok; Pro kedvezmény/bónusz nincs véglegesítve.
6. Global dollarbudget/rate, user job/image quotas, UNKNOWN feloldás deadline és operator folyamat. Ez nem változtathatja partial settlementté az N-credit szabályt.
7. App Check rollout/enforcement időpont; monitorozás után, nyilvános fizetős AI előtt ajánlott.
8. Temporary operation **result** retention (24h javaslat), content nélküli ledger/idempotency audit retention.
9. Elfogadható correction-time, latency és költség küszöbök; cleanup célidő/monitoring és provider-data privacy feltételek.

Single/multi választás, maxképszám, kamera,1kép/1credit és tartós képretention nem szerepel többé open questionként.

## 20. Explicit ajánlás

I1 multi-image input/preprocess/cost UI, I2 egy közös javítható draft/editor/warning, majd **I3 kis, dollárplafonos multi-image recipe-job benchmark**. Csak ezután I4 transport/provider és I5 teljes N-credit backend. User-facing éles AI soha nem kap credit/cost guard nélküli utat; a korai benchmark kizárólag engedélyezett fejlesztői mérés.
V1 natívan1–5 képet együtt értelmez, user által rendezett sorrendben, egy receptként; a jóváhagyott N kép költsége N kredit, a settlement egyetlen jobra történik. B temporary private transport ajánlott, exact limitek/transport még igazolandók; tartós képtárolás nincs. Lifetime Pro-tól külön credit domain, meglévő editor explicit mentéssel.
I0.1 kizárólag designfrissítés: nincs következő fázis, forrásmódosítás vagy providerhívás.

IMPLEMENTATION: NOT STARTED
SOURCE CHANGES: NONE
DEPENDENCY CHANGES: NONE
AI API CALLS: NONE
AI COST: ZERO
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PLAY CHANGES: NONE
PRODUCTION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
