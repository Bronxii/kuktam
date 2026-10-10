# N5.3 lezárás – authenticated transport és tartós entitlement cache

Dátum: 2026-10-08

**Verdict: READY FOR N6 – helyi fejlesztési alapként. Nem production-release engedély.**

## Kiindulási audit és scope

A munkakönyvtár C:/Users/gabor/kuktam. A repó már az induláskor nem volt tiszta: az N1–N5.2 entitlement/billing/backend fájlok, a helyi emulator/rules, az analysis_options és a korábbi dependency-módosítások commit nélkül szerepeltek benne. Ezeket megőriztük. Nem történt reset, commit vagy push.

A meglévő N5.1 repository a trusted proof, 30 napos offline grace, óravisszaállítás és UID-izoláció szabályait hordozza. Az N5.2 orchestrator és Android billing adapter már rendelkezésre állt. A backend AccountLifecycleStore, PurchaseVerifier és közös LifecycleStore megmaradt a vásárlási állapot egyetlen írási útjának.

Az app indulási/auth/UI útvonala nincs bekötve a monetizációba. Nincs ProScreen, CTA, feature gate, új éles végpont vagy valós Play adapter.

## Új és módosított fájlok

Új backend:
- functions/src/transport/monetization.ts
- functions/src/transport/callables.ts
- functions/test/transport.test.ts

Backend módosítás:
- functions/scripts/emulator-tests.cjs – új transport teszt bekötése a demo-emulator körbe
- functions/package.json és package-lock.json – firebase-functions runtime dependency

Új kliens:
- lib/monetization/callable_gateways.dart
- lib/monetization/secure_entitlement_storage.dart
- lib/monetization/monetization_coordinator.dart
- test/monetization/integration_test.dart
- test/monetization/callable_adapter_test.dart

Kliens módosítás:
- lib/billing/billing_contracts.dart – purchase preparation contract
- lib/billing/purchase_orchestrator.dart – friss backend binding vásárlás előtt; account-closure kezelés
- lib/entitlements/data/effective_entitlement_dto.dart – kizárólag inaktív, virtuális Free állapotnál revision 0
- lib/entitlements/data/local_entitlement_repository.dart – hiteles account closure azonnali invalidálása
- pubspec.yaml és pubspec.lock

Android:
- android/app/src/main/AndroidManifest.xml
- android/app/src/main/kotlin/com/bronxii/kuktam/MainActivity.kt
- android/app/src/main/res/xml/backup_rules.xml
- android/app/src/main/res/xml/data_extraction_rules.xml

A package-feloldás generált pluginregisztrációt frissített Linuxon, macOS-en és Windowson is. Ezek nem jelentenek új platformtámogatási vállalást; a tartóssági híd Androidra készült.

## Backend transport és Auth boundary

Három vékony művelet készült:

1. prepareProPurchase: üres body, hiteles Auth UID, ACTIVE lifecycle ellenőrzés, meglévő account initialization és binding registry használata; schemaVersion/productId/opaqueAccountId válasz.
2. verifyProPurchase: csak productId és purchaseToken body; fix backend product allowlist; meglévő PurchaseVerifier. Válasz: verified/pending/rejected. Nem ad kliensoldali isPro igazságot.
3. getEntitlementProof: üres body, tranzakciós account lifecycle + effective entitlement olvasás, szerveridővel kiadott proof. Nem ír entitlementet olvasás mellékhatásaként.

A callable factory a runtime által hitelesített request.auth.uid értékét továbbítja. Body UID elutasított. A runtime-neutral handler AuthContextje csak megbízható szerveroldali adapterből származhat; önmagában nem internetes autentikációs végpont.

Nincs globális Admin inicializálás, production projekt kiválasztása vagy deployolható top-level Functions kompozíció. A későbbi composition adja a valós adaptereket és callable options beállításokat.

A hibaválasz csak schemaVersion + strukturált hibakód. SDK exception, nyers token, stack trace és Play response nem kerül ki.

## Binding és Play mapping

A vásárlás előtt a kliens prepareProPurchase műveletet hív. A backend a meglévő HMAC és keyVersion contract alapján állítja elő/regisztrálja az opaque bindinget. Nyers UID, email és név nem kerül Play oldalra; HMAC titok nem kerül a kliensbe.

A jelenlegi v1 binding 46 ASCII karakter. A kliens ezt validálja, majd a meglévő Android adapter launchBillingFlow accountId paraméterébe adja. A telepített in_app_purchase_android natív MethodCallHandlerImpl implementációja ezt BillingFlowParams.Builder.setObfuscatedAccountId értékére képezi. Nem egy másik, hasonló nevű profile mezőt használunk.

Prepare hiba esetén Play UI nem indul. Account DELETING/DELETED vagy tombstoned/conflicting binding esetén nincs új aktiválás és automatikus UID-transfer.

## Trusted proof és idő

A proof mezői: schemaVersion, active, sources, validUntil, revision, verifiedAt, updatedAt, proofIssuedAt. Az időpontok wire formátuma egész epoch-millis.

- verifiedAt: a tárolt effective entitlement ellenőrzési ideje.
- proofIssuedAt: az aktuális hiteles backend olvasás szerverideje.
- A friss proof kiadása nem növeli az entitlement revisiont.
- Azonos effective revision mellett frissebb hiteles proof megújíthatja a grace bizonyítékát; régi proof replay nem tolhatja ki.
- Hiányzó effective dokumentum virtuális Free revision 0. Ez nem kerül Firestore-ba; az első tartós Pro revision 1 értékével nem ütközik.
- Effective dokumentum account lifecycle marker nélkül hibás konzisztenciának számít.
- DELETING/DELETED account nem kap aktív proofot.

A kliens szigorúan validálja a wire választ. A Firestore cache vagy a Billing purchased állapot önmagában nem trusted Pro proof.

## Flutter transport és session lifecycle

FirebaseCallableTransport explicit FirebaseFunctions példányt kap; nincs implicit production singleton. A Firebase SDK intézi az Auth token átadását. Az adapter csak a három ismert műveletet engedi; kérés előtt és válasz után session predicate-et vizsgál. A hívásnak timeoutja van; a hibák biztonságos domain kategóriákra képeződnek.

A MonetizationCoordinator egy entitlement repositoryt és egy purchase orchestratort fog össze. changeSession azonnal invalidálja a korábbi generationt, leválasztja a purchase sessiont és a proof backendjét. Az első indulás megtarthatja az azonos UID cache-ét; logout/accountváltás töröl. Késői prepare/verify/proof eredmény nem aktiválhat másik sessiont.

Az onlineEnabled kapcsoló explicit konstruktorparaméter. Kikapcsolt állapotban nincs transport létrehozás vagy hálózati hívás. A jelenlegi app még nem példányosítja ezt a kompozíciót.

Az Auth host később minden logout/accountváltást azonnal továbbítson changeSession felé, resume eseménynél kérjen újraértékelést. A Firebase SDK belső credential-időzítése mellett a backend binding ellenőrzése is szükséges: más UID ne kaphasson grantot régi tokenből.

## Purchase, restore és already-owned

Purchase: availability → backend prepare → session ellenőrzés → Play UI opaque bindinggel → pending/cancel/purchased → backend verification → friss trusted proof → repository állapot.

Restore: explicit ownership query → backend verification → proof. Nem indít új vásárlást vagy prepare-t. Más UID-ra nincs automatikus transfer. Already-owned ugyanarra a restore/verification mechanizmusra vezet.

A purchase callback nem kapcsol helyi Pro bool-t. Sikeres verification után egy Free proof továbbra is Free marad. Pending nem grantol. Hiteles accountDeleting/accountDeleted hiba prepare vagy verify során is azonnal invalidálja a régi cache-t; nem vár a következő proof-lekérésre.

Nincs kliensoldali acknowledge, consume vagy subscription kezelés. Az acknowledgment a meglévő backend lifecycle feladata.

## Tartós cache és threat model

flutter_secure_storage 11.2.0, Androidon dedikált kuktam_entitlement namespace. Egyetlen titkosított rekord tartalmazza a proofot és az óracheckpointot. Nincs purchase token, HMAC titok vagy lokális önálló isPro jogosultság.

A csomag AndroidKeyStore által védett kulcsokkal és titkosított tárhellyel dolgozik. A cache továbbra sem szerver által aláírt, hordozható bizonyíték. Normál app-sandbox, at-rest adatvédelem és backup-izoláció a cél; rootolt/hookolt app vagy teljes eszköz-snapshot elleni abszolút védelem nem állítható.

A storage strict cache validációt végez, méretkorláttal. Decode/decrypt/read hiba fail-closed. Írási és törlési hiba nem válik új Pro-bizonyítékká.

A plugin SharedPreferences.apply használata miatt külön Android háttérszálas durability barrier várja meg a dedikált preference írások commitját. A csatorna sem tokent, sem cache-adatot nem kap. Hiba esetén strukturált storage failure keletkezik. Teljes lemezhiba esetén fizikai törlés nem garantálható; ezt nem állítjuk.

Backup: a három dedikált preference fájl kizárt a legacy backupból, Android 12+ cloud backupból és device transferből. A többi appadat backup-szabályát nem tiltottuk le globálisan.

Restart: ugyanazon UID érvényes proofja visszatölthető; lejárt grace requiresConnection állapotot ad. Az óracheckpoint és suspiciousClock jelző tartós, így észlelt visszaállítás után restart nem tisztítja ki a gyanút. Igazolt inaktív proof vagy account closure felülírja a cached Pro-t. Backend/network hiba önmagában nem jelent visszavonást.

## Dependency audit

- cloud_functions pontosan 6.3.5: illeszkedik a jelenlegi Firebase csomagvonalhoz.
- flutter_secure_storage ^11.2.0; lock: 11.2.0.
- firebase-functions pontosan 7.4.0 a backendben.
- firebase-admin 14.5.0 változatlan.
- A korábbi Firebase core és transitive verziókat megőriztük; nem vittünk be általános Firebase upgrade-et.
- in_app_purchase_android a korábbi N5.2 dependency, nem új billing megoldás.

Források: https://pub.dev/packages/cloud_functions ; https://pub.dev/packages/flutter_secure_storage . A tényleges Android mappinget és secure-storage működést a telepített, lock szerinti csomagforrásban is ellenőriztük.

## Automatizált bizonyíték

| Ellenőrzés | Eredmény |
|---|---|
| Új N5.3 Flutter adapter/service/cache tesztek | 46 PASS |
| Teljes Flutter suite, benne N1/N5.1/N5.2 regresszió | 949 PASS / 1 skipped |
| Backend unit suite | 110 PASS |
| Rules/Admin/emulator/concurrency teljes suite | 342 PASS |
| Ebből új N5.3 backend transport tesztek | 27 PASS |
| TypeScript build | PASS |
| flutter analyze --no-pub | CLEAN |
| Android debug APK build | PASS |
| git diff --check + untracked fájlok külön ellenőrzése | CLEAN |

A backend összesen 452 sikeres teszt. A Flutter és backend külön tesztkör; az új teszteket nem számoljuk ismét a teljes suite fölé.

A backend tesztek a meglévő fail-closed demo-kuktam-local emulatort és fake Play adaptert használják. Lefedik Auth/body határt, prepare idempotenciát, bindinget, pendinget, más UID tokenjét, törölt accountot, proof időt és malformed adatokat.

A Flutter tesztek a valódi repository/orchestrator/gateway kódot járják be, fake callable transporttal és mock secure-storage platformhatárral. Lefedik buy/restore/already-owned, duplicate esemény, sessionváltás, késői callback, restart/grace/clock rollback, hibás cache, storage failure és hiteles account closure viselkedést. A Firebase Functions adapter külön fake SDK tesztet kapott.

Ez rétegenkénti helyi integrációs bizonyíték. Nem egyetlen, valódi Android → Auth Emulator → Functions Emulator → Firestore Emulator hálózati end-to-end futás, és nem valódi Play purchase teszt. A fizikai KeyStore, reboot, OS backup és device transfer későbbi készüléktesztet igényel.

## Záró writer/source-of-truth/privacy audit

- A transport nem ír közvetlen billing ledgert, PLAY grantot vagy effective entitlementet.
- Verify a meglévő PurchaseVerifier/LifecycleStore útvonalat használja.
- Prepare csak a meglévő account lifecycle és binding registry műveleteket hívja.
- Proof read-only; hiányzó rekordból nem ír Free dokumentumot.
- Nincs új kliens acknowledge/consume.
- Nincs raw token/error/Play response logolás az új rétegben.
- UID nem kliens body alapján hitelesített.
- Recipe/shopping schema, rules permission és normál UI nem változott.

## Maradt kockázatok és production gap matrix

A helyi N5.3 scope-ban nem találtunk nyitott P0/P1 hibát. Ez nem jelenti a ki nem épített production útvonal auditálását.

| Szint / gap | Állapot / teendő |
|---|---|
| P2: cloud_functions Kotlin Gradle Plugin figyelmeztetés | A jelenlegi debug build sikeres. Jövőbeli Flutter upgrade előtt kompatibilis plugin/Firebase verzióváltást külön validálni kell. |
| P2: npm runtime dependency audit | 2 moderate találat, 0 high/critical a --omit=dev körben; gaxios/uuid transitive lánc. Production előtt célzott felülvizsgálat/frissítés szükséges; force audit fix nem futott. |
| P2: valós device storage | Android build és mock határteszt van, fizikai reboot/backup/KeyStore viselkedés nincs igazolva. |
| Release blocker: production Functions kompozíció | Nincs deploy vagy éles endpoint. Későbbi explicit konfiguráció, Auth/App Check/rate-limit döntések szükségesek. |
| Release blocker: valós Play verification | Fake adapter maradt; API/IAM/secret/product/RTDN/scheduler éles bekötés külön infra fázis. |
| Release blocker: valódi purchase/restore | Készülék + Play teszttermék + license tester szükséges később. |
| Korlát: secure cache | Nem root-/snapshot-biztos szerver-aláírás; tartós eszközhiba esetén fizikai törlés nem garantálható. |
| Platformkorlát | A durability host Androidra készült, más platformos release nincs validálva. |
| Auth host integration | A coordinator opt-in; a későbbi composition köteles az auth sessiont és app resume-ot helyesen továbbítani. |

## N6 pontos előfeltételei

A helyi Pro/Profile UI és hozzá tartozó widgettesztek indíthatók az elkészült controller/gateway contractokon, fake/emulator kompozícióval. N6-ban külön kell megtervezni az Auth host bekötést, az egyetlen coordinator tulajdonosát, a státuszok prezentációját és a vásárlás/restore CTA engedélyezését. Éles vásárlás nem engedhető pusztán a READY FOR N6 státusz alapján.

Nem kezdtük el N6-ot. Nincs végleges ProScreen, Profile Pro kártya, purchase/restore CTA vagy feature gate.

PRODUCTION FIREBASE CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
PRODUCTION DEPLOY: NONE
REAL PLAY PURCHASE TEST: NOT PERFORMED
COMMIT: NONE
PUSH: NONE
