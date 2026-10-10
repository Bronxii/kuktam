# N8 – Free/Pro teljes helyi QA és release-readiness audit

Dátum: 2026-10-09. Repository: `C:/Users/gabor/kuktam`.

## Döntés

**READY TO CLOSE FREE/PRO LOCAL DEVELOPMENT**

**PRODUCTION-INFRA READINESS: READY TO START** – az infrastruktúra következő, külön engedélyezett előkészítési fázisa megkezdhető. Ez NEM production deploy-engedély, és NEM azt jelenti, hogy az éles infrastruktúra már kész.

**Fizetős production release: BLOCKED**, amíg a lent felsorolt valós adapterek, infrastruktúra, account-deletion bekötés és valódi Play/eszközös tesztek hiányoznak. Az auditban nem találtam nyitott, igazolt P0/P1 helyi funkcionális hibát. A sikeres fake/emulator tesztek nem bizonyítanak valódi Play-vásárlást vagy production konfigurációt.

## N8 változtatások és scope

- Új `test/pro/n8_closure_test.dart`: 11 teszt, a meglévő production repository/gate/widget rétegek felhasználásával.
- `lib/entitlements/data/local_entitlement_repository.dart`: elavult „Unwired” fejléc javítása; nincs működésváltozás.
- `lib/monetization/monetization_coordinator.dart`: elavult, appba még nem integrált állapotra utaló komment javítása; az online transport továbbra is alapértelmezetten kikapcsolt.
- Új `N8_REPORT.md` (ez a riport).
- Backend-, dependency-, parser-, feature-, Firebase-schema-, UI-működés- és toolchain-változtatás: nincs N8-ban. A tiszta buildhez `pub get` történt, szándékos package upgrade/install nem.
- A munkafa számos N1–N7 módosítást már tartalmazott. Ezeket megőriztem; a teljes git diff nem N8 saját diffje. Nincs reset, commit vagy push.

## Találatok, súlyosság és release-hatás

| Tétel | Besorolás | Döntés |
|---|---|---|
| Két elavult forráskomment | P3 | Javítva, csak dokumentáció |
| cloud_functions legacy Kotlin Gradle Plugin figyelmeztetés | P2 | Jelenlegi rögzített toolchainen buildel; következő Flutter/toolchain-frissítés előtt koordinált migráció kell |
| Runtime npm audit: 2 moderate találat ugyanazon uuid problémához kötve | P2 | Vizsgált hívás nem az érintett API; nincs vak override/force upgrade |
| Teljes npm audit: további dev-tooling sérülékenységek | P2 jelenlegi, helyi használatban | Elkülönített kockázat, frissítési feladat; nem hallgatjuk el a magas advisory-besorolásokat |
| Tényleges transport, Play API, deployment és deletion coordination nincs élesítve | Production release gate | Ismert fázishatár, nem helyi QA-hibának álcázott kész implementáció |
| Kliensoldali feature gate és secure cache nem védi ki a rootolt/módosított alkalmazást | Architekturális korlát | Backend ledger/entitlement nem kliensírható; lokális kényelmi műveletek abszolút DRM-védelmét nem állítjuk |

## Végleges termék- és access-mátrix

| Funkció | Free | Pro / érvényes offline grace |
|---|---|---|
| Kézi recipe CRUD, megnyitás, keresés | Korlátlan | Korlátlan |
| Kézi shopping CRUD, pipa, másolás, lezárás | Korlátlan | Korlátlan |
| Cloud sync | Elérhető | Elérhető |
| Recipe text import | Közös Pro CTA, művelet nem fut | Meglévő flow |
| Shopping text import | Közös Pro CTA, művelet nem fut | Meglévő flow |
| Scaling | Zárt | Meglévő flow |
| Scaled recipe → shopping | Zárt, alternatív multiplier action is védett | Meglévő flow |
| Mit főzzek? | Zárt, matcher nem indul | Meglévő flow |
| Image/AI import | Unavailable | Unavailable |

Nincs reklám, 15/15 limit, counter, slotmodell vagy recipe/shopping monetizációs backend. A tiszta parser/scaling domain függvények nem kérnek entitlementet: a felhasználó által elérhető belépések és végrehajtási pontok a közös gate-et használják. Új hívási pontoknak is ezt kell követniük.

## Journey, race és regresszió bizonyítékok

| Terület | Helyi bizonyíték / eredmény | Korlát |
|---|---|---|
| Free kézi recept és shopping, keresés | Meglévő recipe/shopping/repository/widget suite és gate-audit PASS; nincs Pro-feltétel az alap CRUD-on | Production cloud sync és készülékes teljes journey nincs futtatva |
| Mind az öt Pro feature | `test/pro/feature_gate_test.dart`: online és offline-grace kompozícióban valódi import/scaling/shopping/matcher; entry és execution guard PASS | Entitlement/Billing forrás fake |
| Checking/unknown | Nem Free, nincs hibás upsell vagy végrehajtás; reaktív állapotváltás PASS | Valódi hálózati időzítés nincs mérve |
| Grace lejárat | N5 boundary/expiry tesztek + új N8 valódi repository → nyitott dialog → pontos 30 nap → action teszt PASS | Nem támaszkodik resume-ra vagy előzetes stream-eseményre |
| Trusted revoke/inactive | Az új bizonyíték felülírja a cached Pro-t; nyitott import is megáll; adat nem törlődik | Éles RTDN nincs |
| Fiókváltás/logout | N5 callback/session fencing; N7 régi draft/action nem kerül B userhez; új N8 valódi repository átmenet PASS | Valódi Google/Firebase account picker külön tesztelendő |
| Startup/cache/restart | UID-egyezés, hibás cache eldobása, storage-failure, cleanup-sorrend, offline restart PASS | Platform secure-storage viselkedés valódi eszközön ellenőrizendő |
| Óra | Pontos határok, monotonic elapsed, rollback latch, restart, kis rollback nem hosszabbít grace-t PASS | Root/OS snapshot tampering nem teljesen kivédhető |
| Purchase | Pending/cancel/error/already-owned/replay/verification delay és egyidejű műveletek fake orchestration + widget PASS | Nincs valódi Play UI/purchase |
| Restore | Backend proof szükséges; más UID nem örököl; restore nem állít lokális Pro boolt PASS | Play account/reinstall/device mátrix manuális |
| Bypass/race | Direct dialog/screen, alternatív scaled shopping, revoke-before-action, logout és új UID PASS | Módosított kliens lokális kódja nem biztonsági határ |
| Deletion | Backend marker/cleanup/tombstone race suite PASS; UI figyelmeztetés PASS | Jelenlegi production kliens delete még nincs a backend koordinátorhoz kötve |
| Import/scaling/matcher regresszió | Teljes régi suite Pro-kompozícióval PASS; keyboard/scroll/unit dropdown is PASS | Nincs új parser-szabály |
| Draft/navigation | Same UID megtartás, más UID eldobás; dupla CTA/tap, route-gate, owned controller megőrzése PASS | Android back/TalkBack kézi próba még kell |

A teljes journey bizonyíték integrált widget/service flow-k és repository fakes összessége; nem egy valós Firebase–Play–Android end-to-end menet. Nincs autosave vagy vásárlástól közvetlen grant. A külön domain tesztek önmagukban nem helyettesítik a widget vagy real-device próbát.

## N8 új tesztmátrix, UI/accessibility

1. Valódi `LocalEntitlementRepository` és execution gate: 30 nap pontosan eltelik stream/resume nélkül; a már látható import action nem futtat parsert, connection üzenetet ad, nem Free upsellt.
2. Trusted inactive proof és account switch eljut a nyitott import gate-ig; a régi session draftja nem használható tovább.
3–11. Viewport `320×568`, `390×844`, `800×1000`, mindegyik `1.0`, `2.0`, `2.5` text scale-lel. ProScreen ready/pending/verifying/support állapot, hosszú lokalizált ár, Profile card és Free gate: nincs render overflow/exception; support szemantika ellenőrizve.

Az új tesztek a meglévő helper/fake tárat használják, nem másolják le a entitlement vagy gate üzleti logikáját. A korábbi N6/N7 tesztek a CTA-k, állapotszövegek, lock badge, dupla megnyitás és accessibility jelölések regresszióját adják. Valódi TalkBack felolvasási sorrendet a widget semantics teszt nem bizonyít.

## Ownership, source of truth, tárolás és contract audit

- `main.dart`: egy app-szintű MonetizationCoordinator, AndroidBillingAdapter, SecureEntitlementStorage és clock; auth/session host kezeli a váltást. Nincs route-onként új purchase-stream tulajdonos.
- `onlineEnabled: false`; az aktuális production transport factory tiltott. Nem kapcsoltam be. A lokális normál build ezért nem tekinthető bekötött fizetős kiadásnak.
- `LocalEntitlementRepository.current` a cache/proof időállapotát olvasáskor is újraértékeli; action gate nem csak utolsó stream-emisszióból dönt. Unknown/checking és connection-required nem Free.
- Pro csak trusted backend proofból jöhet. Play purchased callback vagy verify success önmagában nem ad Pro-t. Proof schema/revision/UID ellenőrzés, session generation és late callback eldobás megmaradt.
- Secure cache: UID-hoz kötött entitlement evidence és időadatok; nincs purchase token, teljes Play response, email vagy profiladat. Android backup-kizárás konfiguráció jelen van; a valós platform backup/restore teszt még release-feltétel.
- A cache nem offline ellenőrizhető szerveres aláírás; az eredeti authenticated online proof és OS secure storage a bizalmi alap. 30 nap a bizonyíték grace-e, nem a lifetime vásárlás lejárata; időkorlátos grant korábbi expiry-je elsőbbséget élvez.
- Kliens/backend package és product egyezik: `com.bronxii.kuktam` / `kuktam_pro_lifetime`.
- Callable contractok: `prepareProPurchase`, `verifyProPurchase`, `getEntitlementProof`; backend UID Auth-contextből, binding backend HMAC-ból. Nincs body UID-ba vetett bizalom vagy raw UID Playnek átadása.
- `functions/src/transport/callables.ts` factory, nem éles deployed export/composition. A backend mezők és hibák kliensoldali parserét transport/emulator regresszió is ellenőrzi.
- Android adapter public low-level BillingClient wrapper útvonalat használ; tényleges client acknowledge/consume/completePurchase hívás nincs. Acknowledge a backend lifecycle felelőssége. Nincs consumable flow.
- A vizsgált monetizációs/entitlement/billing/pro kliens és backend forrásban nincs raw-response/token logging. A strukturált hibák nem adnak ki tokent. Külső platform SDK logjai és production log-redaction külön staging ellenőrzést igényelnek.

## Kotlin warning – részletes verdict

A tiszta debug build pontos figyelmeztetése:

```text
WARNING: Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): cloud_functions
Future versions of Flutter will fail to build if your app uses plugins that apply KGP.

Please check the changelogs of these plugins and upgrade to a version that supports Built-in Kotlin.
If no such version exists, report the issue to the plugin. If necessary, here is a guide on filing
an issue against a plugin: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers#report-incompatible-kotlin-gradle-plugin-usage-to-plugin-authors

If you are a plugin author, please migrate your plugin to Built-in Kotlin using this guide: https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
```

A napló az első guide-mondat végén egy formázási záró szóközt is tartalmaz; azt itt whitespace-tisztaság miatt elhagytam, a szöveg változatlan.

| Összetevő | Vizsgált érték |
|---|---|
| Flutter / Dart | 3.44.6 stable / 3.12.2 |
| cloud_functions | 6.3.5, explicit pin |
| AGP / Gradle | 9.0.1 / 9.1.0 |
| Effektív KGP | **2.3.20**, `:app:kgpVersion` taskkal is ellenőrizve |
| JDK | Android Studio JBR 21.0.10+-14961533-b1163.108 |
| Java/Kotlin target | 17 |
| compileSdk / targetSdk / minSdk | 36 / 36 / 24 |
| NDK / build tools | 28.2.13676358 / 36.0.0 |
| Built-in Kotlin / new DSL | `android.builtInKotlin=false`, `android.newDsl=false` |

**Forrás és gyökérok:** Flutter SDK `FlutterPluginUtils.kt`, `detectApplyingKotlinGradlePlugin` konfigurációs ellenőrzése; az `assembleDebug` összesített build alatt jelenik meg. Nem egy `compileKotlin` metadata-verzió hiba. A cloud_functions 6.3.5 Android script AGP>=9 mellett is alkalmazza a `kotlin-android` plugint, ha builtInKotlin=false. A plugin saját fallback buildscriptjében szereplő Kotlin 2.0.0/AGP8.1.4 deklaráció nem az app tényleges feloldott verziója.

**Jelenlegi hatás:** clean → pub get → debug APK build PASS. Nincs észlelt Kotlin metadata mismatch vagy Kotlin-fordítási hiba. Van külön Java deprecated/unchecked figyelmeztetés és Gradle10 jövőbeli deprecation jelzés; ezek sem tették sikertelenné a jelenlegi buildet.

**Frissítési audit:** a lekérdezéskor cloud_functions 6.5.0 az újabb publikált verzió; Dart^3.6/Flutter>=3.27, firebase_core^4.14.0 követelménnyel. A 6.4 eltávolította a plugin helyi AGP/KGP verziómegkötését, de a 6.5.0 tag Android scriptje továbbra is feltételesen alkalmazza a legacy plugint builtInKotlin=false mellett. Ezért a plugin önálló upgrade-je nem garantálja a warning megszüntetését.

A Flutter dokumentáció a built-in módhoz Flutter3.47+-t ír; a 3.44 átmeneti kompatibilitási módja legacy plugineket is támogat. Nem helyes csak true-ra fordítani a kapcsolót a jelenlegi toolchainen. Következő lépés külön Flutter/AGP/plugin migrációs munka, build + teljes regresszió + release AAB ellenőrzéssel; N8-ban sem verziót, sem kapcsolót nem változtattam.

**KOTLIN WARNING VERDICT: P2 / SAFE TO DEFER a most rögzített toolchainen. PRODUCTION BLOCKER: NO, a warning önmagában. SAFE TO SHIP: CONDITION – csak validált, rögzített toolchainnel és a külön release/Play kapuk teljesítése után.** A teljes monetizáció most ettől függetlenül még nem élesíthető.

Források: [Flutter app migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers), [Flutter built-in Kotlin](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin), [cloud_functions changelog](https://pub.dev/packages/cloud_functions/changelog), [6.5.0 tagged Android script](https://raw.githubusercontent.com/firebase/flutterfire/cloud_functions-v6.5.0/packages/cloud_functions/cloud_functions/android/build.gradle).

## npm és dependency health

`npm audit --omit=dev`: **2 moderate, 0 high, 0 critical**. A gaxios és uuid csomagjelzés ugyanahhoz az underlying problémához kötődik, nem két független exploit.

- `firebase-admin@14.5.0 → @google-cloud/storage@8.2.0 → gaxios@6.7.1 → uuid@9.0.1`; további storage/google-auth9/gtoken ágak is használják ezt a régi gaxios-t.
- GHSA-w5hq-g745-h8pq / CVE-2026-41907: uuid v3/v5/v6 buffer bounds, érintett <11.1.1, javított 11.1.1. A vizsgált gaxios forrás `uuid.v4()`-et használ argumentum nélkül; saját érintett v3/v5/v6 hívást nem találtam. Ez használati út audit, nem minden jövőbeli SDK-hívás sérülékenységmentességi bizonyítása.
- A frissebb Firestore/Admin auth ágak gaxios7-et használnak. A régi6-os ágnál parent-package koordinált frissítés kell; a uuid major override nem tekinthető automatikusan kompatibilis megoldásnak.

`npm audit` dev eszközökkel együtt: **16 találat: 12 high +4 moderate, 0 critical**. Az összesítés transzitív dependenseket is külön számol. A runtime nézetben nincs high.

| További advisory / ág | Kockázat a jelenlegi használatban |
|---|---|
| @grpc/grpc-js, GHSA-m9gg-hp2v-232j; további GHSA-f596-whhp-79r4 | Firebase web/rules dev ág; az első advisory server-side mTLS getAuthContext körülményhez kötött. A helyi suite nem nyilvános ilyen gRPC szerver |
| @opentelemetry/core GHSA-8988-4f7v-96qf | Firebase-tools/PubSub dev ág, baggage méret erőforrás-kockázat |
| basic-ftp GHSA-c475-qrg2-pj4r | Firebase-tools proxy/get-uri ág, FTP-list parser erőforrás-kockázat |
| braces GHSA-vfj7-8cjw-p6xm | Firebase-tools/chokidar dev ág, rosszindulatú minta DoS |

A high advisory súlyosságot nem minősítjük át „nincs hibává”; a P2 itt a vizsgált, localhostra kötött QA használat prioritása. Nem megbízható inputokat feldolgozó CI/nyilvános szolgáltatás előtt külön tooling-frissítés és új audit szükséges. Az automatikus fix javaslat jelentős major váltásokat/visszalépéseket is tartalmaz; `npm audit fix --force` nem futott.

Runtime forrás: [uuid advisory](https://github.com/advisories/GHSA-w5hq-g745-h8pq). Dev példa: [grpc-js advisory](https://github.com/advisories/GHSA-m9gg-hp2v-232j).

Kliens dependency-leltár: firebase_core4.12.1, firebase_auth6.5.6, cloud_firestore6.7.1, cloud_functions6.3.5, in_app_purchase_android0.5.3, flutter_secure_storage11.2.0. A lekérdezéskor core4.15.0/auth6.7.0/firestore6.10.0/functions6.5.0 újabb elérhető; ez nem tesztelt upgrade-ajánlás. Android billing0.5.3 Flutter>=3.44/Dart^3.12 követelménye illeszkedik a jelenlegi SDK-hoz. Backend admin14.5.0/functions7.4.0, TS5.9.3; rögzített lockokkal dolgoztunk. N8 dependency change: NONE.

## Android build és kihagyott teszt

Tiszta `flutter clean`, `flutter pub get`, `flutter build apk --debug --no-pub`: PASS. APK: `build/app/outputs/flutter-apk/app-debug.apk`. Version1.0.0+1; release-signing szerkezet nem változott, secretet nem írtam ki. Release AAB-t nem építettem és nem töltöttem fel.

Debug APK 16KiB sanity: build-tools zipalign `-c -P 16` PASS; a debug arm64/x86_64 natív könyvtárak ELF LOAD alignmentje legalább0x4000 (libflutter és arm64 validation layer0x10000). Ez nem helyettesíti a végleges release AAB, Play feldolgozás és tényleges 16KiB készülék tesztjét. [Android page-size útmutató](https://developer.android.com/guide/practices/page-sizes).

A teljes suite egyetlen skipje: `test/recipes/recipe_scaling_dialog_test.dart`, `perf: focus and inset sweep do not scale or format`. Szándékos opt-in diagnosztika: `SCALING_PERF`, release-ben kikapcsolt. Külön `--dart-define=SCALING_PERF=true` futtatva **1 PASS**. 3 és60 sor, 15 inset/focus változás: nem fut új scaling/format; épített sorok3 illetve9. Nincs új skip.

## Backend, performance és költség

A közös lifecycle writer, v1/v2 strict parsing, grant OR aggregation, verify/ack/revoke/RTDN/maintenance/deletion concurrency és contract tesztek újrafutottak. N8 nem módosított backend logikát. Az RTDN/inbox/maintenance nem kapott külön purchase-writer utat.

A maintenance bounded: page50, max100,60s run budget,120s lease,30s I/O timeout; injektálható policy. Default aktív recheck naponta±20%, transient5perc, unresolved30perc cap1nap, recovery1óra/max3generáció, maxfail8, voided6óra/30nap technikai lookback. Nincs production scheduler. A deadline csak valódi completion timestampből számítható; hiányzó adatot nem helyettesít verifiedAt.

Cursor/category folytatás és per-item izolálás megakadályozza az egész adatbázis egy körös bejárását. Az ismételt ID-scan/read költség és500grant korlát nagyobb adatmennyiségnél mérendő; nincs production volume/költség benchmark. Később read-count, queue-age, ack-deadline és exhausted state metrikák szükségesek. Nincs magas frekvenciájú UI polling vagy képernyőnként új Billing tulajdonos.

## Lokális kontra valódi bizonyítás

| Állítás | Most bizonyított | Release előtt még kell |
|---|---|---|
| Domain/access/grace/clock | Unit + valódi repository widget | Fizikai clock/resume/reboot |
| ProScreen/pending/restore | Widget + fake platform | Play purchase UI és payment state |
| Auth/session/token ownership | Unit + emulator race | Valódi Firebase és több Play account |
| Rules/backend write ownership | Firestore Emulator, demo project | Deployed rules read-back és smoke |
| Play lookup/ack/refund/RTDN | Fake adapter lifecycle | Hiteles Google API + RTDN integration |
| Deletion/tombstone | Backend emulator core és UI warning | Production delete sequencing + Auth fallback |
| Android build | Clean debug + ELF/zip sanity | Release AAB/signing/Play/16KiB/device |
| Accessibility | Semantics/layout matrix | TalkBack, fizikai billentyűzet/back |

## Production prerequisite mátrix – semmi nem lett bekapcsolva

| Terület | Jelenlegi bizonyíték / hiány | Következő előfeltétel |
|---|---|---|
| Firebase project/Blaze | N8 nem kérdezte le/módosította a live plant | Jogosult read-only ellenőrzés, költség/budget döntés |
| Firestore Rules | Helyi explicit recipe/shopping, entitlement read-only, backend-only deny; emulatortesztelt | Live rules snapshot/diff, régi kliens kompatibilitás, külön deployjóváhagyás; broad user wildcard nem maradhat entitlement mellett |
| Functions | Factory + service core van, éles composition/export/runtime/region nincs készre igazolva | Támogatott Node runtime, region, service account, function resources, min/max instances, timeout és rollout |
| Google Play Developer API | Fake adapter; éles API/IAM nincs vizsgálva/engedélyezve | Valódi purchase/ack/voided adapter és contract tesztek; least-privilege Play access |
| Binding secret | HMAC keyVersion contract van | Secret Manager és rotációs/hozzáférési terv; ne kerüljön repo/clientbe |
| RTDN/PubSub | Parser/inbox/process core van | Topic, publisher/subscriber IAM, endpoint hitelesség, Play Console mapping, dead-letter/monitoring |
| Scheduler | Neutral maintenance core van | Jóváhagyott ütemezés, retry budget, queue-age/deadline riasztás |
| App Check | Enforcement N8-ban nem került be | Play Integrity readiness, tokenek megfigyelése, fokozatos enforcement; Auth ellenőrzést nem helyettesíti |
| Play Console | Live állapotot N8 nem igazolta | Production access/merchant/profile, one-time non-consumable product, buy option, lokalizált ár/ország/aktiválás, license testers és track |
| Flutter online composition | Explicit disabled | Valódi authenticated transport region/options; purchase switch csak kész backend után |
| Account deletion | Kliens: reauth → recipe/shopping/root törlés → user.delete; nincs begin-deletion backend hívás | Backend DELETING barrier a kliens cleanup előtt; idempotens coordination, Auth fallback, retry/support; új UID nincs automatikus restore |
| Privacy/support | UI figyelmeztetés és technikai retention contract | Publikus privacy/deletion/purchase disclosure frissítés, lifecycle adatminimalizálás és jogi retention döntés, support csatorna |
| Monitoring | Strukturált outcomes és bounded retry vannak | Redacted logs, ack közel deadline, API permission, exhausted/unresolved, deletion backlog, költségriasztás |

A jelenlegi 1.0.0 kliensek recipe/shopping útvonalait meg kell őrizni. A DELETING markerhez kötött local write-tiltás szándékos; régi kliens deletion/pending írása csak kontrollált rollout után találkozzon vele. A deployed rules élő állapotát ez a riport nem tanúsítja. Minden szükséges production módosítás külön későbbi feladat, nem N8-ben végrehajtott munka.

## Fizikai Android / valódi Play release checklist

- [ ] Internal/closed trackről telepített, release-signed build; package/product/ár a Console adataival egyezik.
- [ ] Free teljes kézi recept és shopping journey, keresés, két készülékes sync; minden Pro belépés korrekt locked CTA.
- [ ] Buy: cancel, purchased, pending→purchased, product unavailable, Play unavailable, network drop, verification delay/restart; nincs dupla charge/grant.
- [ ] Backend ack működik, kliens nem ack/consume; Play already-owned esetből restore/support.
- [ ] Same UID reinstall és új készülék restore; más Play account + same UID; same Play account + más UID nincs automatikus transfer.
- [ ] Online Pro és offline grace mind az öt feature-rel; lejárat foreground/resume/reboot, trusted revoke után nincs cache-visszaaktiválás.
- [ ] Logout/account switch purchase UI, verify és restore közben; régi draft/callback nem jelenik meg új usernél.
- [ ] Refund-only kontra revoke, RTDN duplikáció/kiesés és maintenance catch-up; PROMO/ADMIN megtartja Pro-t.
- [ ] Account deletion purchase/ack közben; új UID nem restore-olható automatikusan, already-owned support szöveg érthető.
- [ ] Kicsi/nagy készülék, 200–250% betű, TalkBack, vissza gomb/gesztus, billentyűzet, háttér/foreground és activity recreation.
- [ ] Android minimum és aktuális verzió, végleges AAB16KiB/Play pre-launch report; OS secure storage backup/restore.
- [ ] Privacy/Data Safety/support/purchase leírás végleges; nincs még nem létező image-import ígéret.

## Ellenőrzési eredmények

| Ellenőrzés | Eredmény |
|---|---|
| N8 új widget/integrációs tesztek | **11 PASS** |
| Teljes Flutter suite (N1–N7 + N8 + régi app regresszió) | **1096 PASS /1 opt-in skipped** |
| Skipped scaling performance külön engedélyezve | **1 PASS** |
| Backend unit suite | **110 PASS /0 fail** |
| Rules/Admin/emulator/concurrency/transport | **342 PASS /0 fail** |
| TypeScript build | **PASS**, npm test mindkét szakaszában; strict/noUncheckedIndexedAccess/exactOptionalPropertyTypes |
| Flutter analyze --no-pub | **CLEAN** |
| Clean Android debug build | **PASS** |
| KGP verziótask | **PASS**,2.3.20 |
| Dart formatter, N8 három érintett fájl | **CLEAN**, 0 változtatás |
| Teljes lib/test formatter, output=none | **24 korábbi fájlnál eltérés /112 vizsgált**, nem módosítva |
| Tracked/untracked diff-check | **CLEAN**; 110 untracked fájl, 0 whitespace finding; Windows CRLF figyelembe véve |

A teljes formatter ellenőrzés read-only volt (`--output=none`), ezért a „Changed” naplósorok nem jelentenek fájlmódosítást. A 24 korábbi formázási eltérés P3 adósság, nem analyzer/build hiba; N8 nem végez scope-on kívüli tömeges formázást. Git status a lezáráskor 45 short-status sort tartalmaz (az untracked könyvtárakat összevonva), benne a korábban örökölt N1–N7 munkával.

Összes sikeres teszt: **1549** =1096 Flutter +1 külön performance +110 backend unit +342 emulator. A 11 N8 teszt a1096 része, nem számoljuk kétszer. A normál Flutter skip külön futtatva sikeres.

Naplók: `C:/Users/gabor/AppData/Local/Temp/kuktam-n8-{full,closure,perf,backend,analyze,clean,pub,build,kgp,doctor}.log`; npm JSON: `kuktam-n8-npm-runtime.json`, `kuktam-n8-npm-all.json`. A lokális temp naplók nem tartós release artifactok; a riport az ellenőrzött összefoglaló.

## Következő pontos fázis és elfogadott korlátok

N8 lezárása után külön production-infra előkészítési fázis: jogosultságok/live konfiguráció read-only felmérése, valódi Play adapter és Functions composition megtervezése/tesztelése, deletion kliens-backend bekötés, runtime/dependency döntések, release artifact és staged rollout terv. Csak külön felhasználói engedéllyel következhetnek production erőforrás/deploy lépések, majd valódi Play QA.

Nincs valódi vásárlási bizonyíték, production rules/deploy bizonyíték, eszközös accessibility/performance mérés vagy release AAB tanúsítás. Kotlin/tooling warningok és dependency adósság dokumentált; automatikus upgrade nem történt. Ezeket a helyi fejlesztés lezárása nem törli a release checklistből. Image import, sharing és új UI-polish nem indult.

PRODUCTION FIREBASE CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
PRODUCTION DEPLOY: NONE
IAM/API CHANGES: NONE
REAL PLAY PURCHASE TEST: NOT PERFORMED
IMAGE IMPORT: NOT STARTED
COMMIT: NONE
PUSH: NONE
