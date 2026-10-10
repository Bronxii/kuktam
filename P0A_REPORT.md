# P0A – Read-only production infra audit és biztonságos rollout

Dátum: 2026-10-09. Repo: `C:/Users/gabor/kuktam`. Kizárólag célzott forrásolvasás és publikus hivatalos dokumentáció ellenőrzése történt; egyetlen új fájl ez a riport.

## 1. Verdict és bizonyítékhatár

**READY FOR FIRST PRODUCTION INFRA CHANGE** – kizárólag a lent meghatározott, külön engedélyezendő P0B első checkpointjára; nem Functions/rules/deletion élesítésre.
**Paid production release: BLOCKED.** A live állapot ellenőrzése minden módosítás előfeltétele; eltérés vagy hiányzó jogosultság esetén STOP.
N8 eredményeit referenciaként használjuk: Flutter1096 PASS + külön perf1 PASS, backend110 unit +342 emulator PASS, TS/analyze/debug build sikeres. Ezeket P0A nem futtatta újra.
A munkafa örökölt N1–N8 változásokat tartalmaz; nincs reset, forráskódváltoztatás, upgrade, formatter sweep vagy ismételt dependency/Kotlin audit.

## 2. Repo és live állapot

| Terület | Repo / EXPECTED FROM PREVIOUS AUDIT | Live státusz |
|---|---|---|
| Firebase project | `firebase.json`, `lib/firebase_options.dart`: `kuktam-67768`; Android registration `1:44537266968:android:7fb0027a2a6470ccfc946d` | LIVE STATE NOT VERIFIED |
| Plan / Firestore | Korábban Spark / eur3 | LIVE STATE NOT VERIFIED |
| Auth | Korábban Email/Password + Google; UID-alapú kliens | LIVE STATE NOT VERIFIED |
| Rules | Korábban broad user wildcard; helyben hardened `firestore.rules` | LIVE STATE NOT VERIFIED |
| Functions / App Check | Korábban nincs deployed Function / nincs App Check | LIVE STATE NOT VERIFIED |
| IAM / Play identity | Korábban Admin SDK SA van, külön billing SA nincs | LIVE STATE NOT VERIFIED |
| Play | Merchant korábban hiányzott; access approval/track/product/license tester/RTDN most nem ellenőrzött | LIVE STATE NOT VERIFIED |
| Cloud APIs / secrets / scheduler / topic | Repóból nem bizonyítható meglét vagy hiány | LIVE STATE NOT VERIFIED |

Nem volt rendelkezésre álló hitelesített Firebase/Play connector; élő konzol/CLI-lekérdezést nem végeztem. A repo config nem bizonyít deployed állapotot. P0B elején USER read-only Console-ellenőrzés kell, secretérték megosztása nélkül.

## 3. Komponensenkénti készültség

A = CODE READY: a megnevezett core kész, a teljes feature ettől még nem deployolható. B = ADAPTER/COMPOSITION MISSING. C = INFRA ONLY: az adott konfigurációs elemhez nem kell új üzleti logika.

| Komponens | Kategória | Konkrét forrás / hiány |
|---|---|---|
| Verify / ack / revoke / közös writer | A | `functions/src/billing/{verify-purchase,acknowledge-purchase,revoke-purchase,lifecycle-store}.ts` |
| Schema, grant aggregation, fencing, binding registry | A | `models.ts`, `aggregate.ts`, `billing/schema-v2.ts`, `accounts/*` |
| RTDN parser/inbox/processor | A | `billing/rtdn/{notification,inbox-store,processor}.ts`; nem deployed subscriber |
| Maintenance core | A | `jobs/{maintenance,maintenance-store,maintenance-policy}.ts`; bounded run/cursors |
| Deletion billing lifecycle core | A | `accounts/account-deletion.ts`, `accounts/deletion-contract.ts`; tartalmi cleanupot nem végez |
| Callable source | A | `transport/{monetization,callables}.ts`: prepareProPurchase, verifyProPurchase, getEntitlementProof |
| Flutter authenticated transport | A | `lib/monetization/callable_gateways.dart`: FirebaseCallableTransport + gateway/proof parser |
| Helyi rules candidate | A | `firestore.rules`; deploy mapping és live compatibility check még kell |
| Valódi Play lookup / ack / voided lookup+feed | B | Jelenleg interface/fake, nincs Google HTTP/SDK implementáció |
| Functions export/composition | B | Nincs production entrypoint, explicit runtime/main/region/secret/admin inicializálás |
| Deletion callable + Auth adapter/fallback + kliens coordination | B | Source core van; hitelesített begin/resume transport, recent-auth és tartalmi cleanup-barrier hiányzik |
| RTDN runtime adapter + maintenance wrapper | B | CloudEvent→envelope, durable cursor/dispatch állapot és invocation konfiguráció nincs bekötve |
| HMAC rotation | B | `AccountBinding.keyVersion='v1'`; többkulcsos verifikáció még nincs |
| Flutter online composition | B | `lib/main.dart`: onlineEnabled=false, transportFactory tiltott; region/Functions instance bekötés kell |
| Billing plan / API / IAM / Secret provisioning | C | Console/Cloud feladat, külön engedéllyel |
| Play merchant / product / countries / license testers | C | Console feladat; app contract már pontos |
| Topic / scheduler / App Check registration | C | Provisioning; használatukhoz a fenti B-wrapperek/integráció is kell |

## 4. LIVE → TARGET Firestore Rules delta

Production candidate: a gyökérbeli `firestore.rules`. Jelenleg `firebase.emulators.json` hivatkozza; a `firebase.json` csak Flutter-konfigurációt tartalmaz, nincs production rules/functions deploy mapping.
- Régi `/users/{uid}/{document=**}` owner-write megszűnik. Az allow szabályok OR-logikája miatt broad allow mellé írt deny NEM védene entitlementet.
- `users/{uid}/recipes/*`, `shopping/*`: saját read/delete marad; create/update csak hiányzó marker vagy ACTIVE esetén.
- `users/{uid}`: saját get/delete; nincs root list/create/update. Jelenlegi kliens delete-flow ezt használja; egyéb kiadott kliens root/profile használatát live rollout előtt ellenőrizni kell.
- `users/{uid}/entitlements/pro`: saját read, client write deny. `entitlementGrants/*`: client read/write deny.
- `billingPurchases`, `billingAccountBindings`, `accountLifecycle`, `accountDeletions`, `billingMaintenance`, `rtdnInbox`: backend-only; minden más nem felsorolt útvonal deny.
- `ingredients/*`: authenticated read, client write deny. Nincs darabszám/slotlimit vagy cloud-sync Pro gate.
- DELETING/DELETED: az olvasás/törlés marad, új/módosított tartalom tiltott. A marker hiánya megőrzi a régi normál CRUD-ot; offline queue marker után permission-denied lehet.
**Sorrend:** a hardened rules legyen élő és visszaellenőrzött MIELŐTT bármilyen entitlement/grant/marker író endpoint vagy éles vásárlás elérhető.
Rules rollback nem térhet vissza broad user-write-ra, ha már védett adatok vannak. Előre elkészített, továbbra is backend-only monetizációt védő kompatibilitási rules változat kell.

## 5. Functions és runtime

SOURCE EXISTS: három monetizációs callable factory; `AccountDeletionService.beginAccountDeletion`, `resume`, `handleAuthUserDeleted`; `RtdnProcessor.handle/process`; `Maintenance.run`.
PRODUCTION EXPORT MISSING: mindegyiknél. Deletion callable factory sincs; `resume(uid)` trusted belső API, nem tehető közvetlen request-body UID-ra.
REAL ADAPTER MISSING: Play lookup/ack/voided/feed, `AuthUserDeletionApi` Admin-implementáció. CONFIG MISSING: Admin ADC, project/database, region, secret, runtime SA, erőforráskorlátok, deploy mapping.
`functions/package.json`: engines és main hiányzik; firebase-functions7.4.0, firebase-admin14.5.0. TS: ES2022/CommonJS, strict; rootDir='.', outDir='lib', tehát egy későbbi src/index.ts kimenete `lib/src/index.js` lenne.
**Ajánlás: Node22**, jelenleg a Firebase dokumentáció támogatja; ne a lokális Node-verziót tekintsük production runtime-nak. Node24 csak külön CLI/SDK/runtime kompatibilitási döntés után; a Cloud Run támogatás nem automatikusan Firebase-toolchain igazolás. [Runtime](https://firebase.google.com/docs/functions/manage-functions).
Javasolt region: `europe-west1`, az eur3 Firestore közelében; P0B live location read-back után véglegesítendő. Régióváltás később endpoint/trigger migráció, nem sima kapcsoló.
A jövőbeli composition explicit Node/runtime/main/source legyen, ne deployolja a teszteket/fake-eket végpontként; minInstances0, kis maxInstances, bounded timeout/concurrency induláskor.

## 6. Valódi Google Play adapterek

| Adapter | API / illesztés | Kritikus mapping |
|---|---|---|
| PlayPurchaseApi.lookup | Android Publisher v3 `purchases.productsv2.getproductpurchasev2(packageName,token)` → szigorú PlayPurchase DTO | Product line item ellenőrzése; request package/token nem válik response-bizonyítékká; PENDING/PURCHASED/CANCELED, ack, binding, test flag |
| PlayAcknowledgmentApi.acknowledge | `purchases.products.acknowledge(package,product,token)` | Csak durable verified grant után; success/alreadyAcknowledged/transient/config; timeout után friss lookup, nincs client ack vagy consume |
| VoidedPurchaseFeed.list | `purchases.voidedpurchases.list` + lapozás/időablak | Discovery DTO: token+voidedTime, nem közvetlen grant-write |
| VoidedPurchaseApi.lookup | Friss purchase lookup + hiteles tokenhez kötött voided-list bizonyíték | NINCS általános per-token voided GET. A lookup implementáció bounded/paginated keresés vagy hiteles discovery cache + friss ellenőrzés kompozíciót igényel |

Product `kuktam_pro_lifetime`; package `com.bronxii.kuktam`, kliens/backend egyező. API: `androidpublisher.googleapis.com`, OAuth scope `https://www.googleapis.com/auth/androidpublisher`. [API metódusok](https://developers.google.com/android-publisher/api-ref/rest).
Voided list csak visszavont vásárlásokat jelez; refund revoke-opció nélkül nem kerül bele. A 30 napos API-ablakon kívüli hiány nem bizonyít valid purchase-t. Refund-only/unknown/404/config nem automatikus downgrade; a pending-cancel sem korábban aktív grant revoke-ja. Raw response/token nem logolható. [Voided contract](https://developers.google.com/android-publisher/voided-purchases).
A valódi válaszok többtermékes/quantity/partial-refund mezőit konzervatívan kell kezelni; a lifetime termék egy darab, nem consumable. Adapter mapping fixture-tesztek külön P0C feladat, most nem implementáltam.

## 7. IAM, API és secret terv

Az API-t a meglévő `kuktam-67768` projektben javasolt majd engedélyezni; új projekt nem szükséges. Cloud IAM és Play Console jogosultság KÜLÖN rendszer; projektlinkelés már nem előfeltétel. [Hivatalos setup](https://developers.google.com/android-publisher/getting_started).
| Identity / jog | Javasolt minimum és hatókör |
|---|---|
| `kuktam-billing-runtime` (javasolt új SA) | Firestore `roles/datastore.user`, kiválasztott HMAC secret `roles/secretmanager.secretAccessor`; nincs Owner/Editor |
| Play API identity | Kezdetben lehet ugyanaz a billing runtime SA, ADC-vel, JSON private key nélkül. Play Console app-szintű access: financial/orders view + manage orders/subscriptions a Billing API-hoz; nincs release/admin jog |
| `kuktam-deletion-runtime` | Külön SA: Firestore adatírás + lehető legszűkebb custom Firebase Auth user get/delete jog; nincs Play/secret jog. Admin SDK bypass miatt ezt különösen szűken kezeljük |
| RTDN publisher | `google-play-developer-notifications@system.gserviceaccount.com`: `roles/pubsub.publisher` CSAK a kiválasztott topicra |
| RTDN trigger/invoker | Eventarc trigger identity: eventReceiver ahol szükséges és run.invoker csak célra; Pub/Sub service agent managed subscription jogosultságai, ne billing runtime kapjon általános subscriber/admin jogot |
| Scheduler caller | Külön caller SA, OIDC, `roles/run.invoker` csak a maintenance HTTP célra; nincs Firestore/secret/Play jog |
| Deploy/build identity | Elkülönül runtime-tól; cél-SA actAs + szükséges build/deploy jogok, külön IAM diff-review; nem örökölt Editor |

A Firestore IAM adatjog nem collection-szintű rules: runtime SA kompromittálása széles adat-hozzáférés; a feladat-/SA-szétválasztás és minimális kódexport lényeges. Ha a maintenance deletiont dispatchol, hitelesített külön deletion worker hívás ajánlott; ne kapjon automatikusan Auth-delete jogot a teljes billing worker.
Secret-javaslat: `kuktam-account-binding-hmac-v1`, legalább32 cryptographic random byte, explicit numerikus Secret Manager-verzióhoz rögzítve. KeyVersion domain `v1` != Secret Manager fizikai verziószám.
Rotáció előtt multi-key verification kell: új purchase v2-t kaphat, régi v1 binding tovább verifikálható; registry/tombstone nem írható át új tulajdonosra. Régi secret csak igazolt szükségtelenség után vonható ki; vak secret-csere lifetime restore-t törne.

## 8. RTDN, scheduler, App Check

Javasolt topic: `projects/kuktam-67768/topics/kuktam-play-rtdn`; későbbi export `processPlayRtdn`. Play → topic → hitelesített Functions/Eventarc → transport envelope → durable inbox → fresh API → meglévő LifecycleStore.
Runtime source identityt a szerver fixálja, nem a payload; source+messageId dedupe változatlan. Test notification nem ad grantot. [RTDN setup](https://developer.android.com/google/play/billing/getting-ready).
Durable inbox átvétel előtt hiba: delivery retry; durable RETRY/UNRESOLVED után transport siker, további munkát maintenance végez. Malformed kontrollált reject, nem végtelen delivery-loop.
Retry legyen bounded; managed Eventarc subscription DLQ-t ne konfiguráljuk vakon kézzel. Ha választott trigger nem támogat stabil DLQ-kezelést, az inbox operator-state + backlog alert legyen explicit alternatíva; saját push subscription csak indokolt esetben.
Egy 5-perces OIDC Scheduler job elegendő lehet a bounded dispatcherhez: a core nextAt/nextCheckAt dönt; unresolved30perc, exhausted1óra, active1nap±20%, voided6óra nem külön job mindegyikhez.
**Wrapper-hiány:** `Maintenance.run` visszaad cursors/nextCategory értékeket; ezeket tartósan, run-lease/version mellett meg kell őrizni. A category scan és I/O budget nem kezelhető egyszerű stateless cron-hívással. Deletion category külön koordinációs kapu mögött maradjon.
Költségoptimalizálásként a dispatcher kategóriánként ritkább scan-időt is tárolhat; due lease/retry/grant marad5perc. Ez későbbi composition kód, most nincs scheduler. [Scheduler auth](https://docs.cloud.google.com/scheduler/docs/http-target-auth).
App Check: USER Play Integrity registration → ASTRA kliens tokenintegráció → monitor → failure/device/track elemzés → csak később callable enforcement. Régi kliens miatt Firestore/Auth globális enforcement most nem kerülhet előre. Auth továbbra is kötelező. [Monitor](https://firebase.google.com/docs/app-check/monitor-metrics).

## 9. Deletion és legacy kliens – külön release blocker

Jelenlegi kliens `account_deletion_repository.dart`: reauth → server-read recipe/shopping lapok törlése → root törlés → user.delete. A backend core csak billing cleanupot végez, majd AuthUserDeletionApi-t hívhat.
**Lényeges sequencing gap:** beginDeletion után a maintenance.resume önállóan elérheti az AUTH szakaszt; nincs kliens contentCleanupComplete-barrier. Így a tervezett új flow pusztán két callable hozzáadásával NEM biztonságos: túl korai Auth-delete elvághatja a még folyó kliens tartalomtörlését.
P0C/P0H megoldandó: hitelesített, recent `auth_time`-ot ellenőrző begin; DELETING barrier; idempotens content cleanup; szerverrel ellenőrzött cleanup-complete/finalize kapu; csak ezután Auth finish. Ne pusztán kliens bool nyissa az Auth-törlést.
Megszakadt klienshez szerveroldali tartalmi cleanup/recovery út kell, vagy a cleanup befejezéséig explicit várakozó állapot és support; a jelenlegi billing-only fallback önmagában nem törli az orphan recipe/shopping adatot.
Auth fallback source-method kész, trigger/export és Admin adapter hiányzik; runtime/SDK által támogatott Auth deletion triggerre kell kötni, idempotensen. [Auth trigger dokumentáció](https://firebase.google.com/docs/functions/auth-events).
UI: reauth sikertelen → semmi nem indul; begin sikertelen → tartalom nem törlődik; DELETING után megszakítás → folytatás/support, nem automatikus ACTIVE visszaállítás. Account delete nem Play-refund és új UID-ra nincs restore/transfer.
Régi1.0.0: marker nélkül CRUD marad; DELETING markerrel update tiltott, read/delete marad. Új deletion marker csak kész recovery után keletkezzen. A régi kliens közvetlen Auth-delete-jéhez fallback kell a vásárlások bekapcsolása ELŐTT; régi bináris távolról nem javítható.

## 10. Play Console és tesztelés sorrend

USER: meglévő merchant/payments állapot read-only ellenőrzése → ha hiányzik, jogi/üzleti adatokkal setup → jóváhagyás → app monetization.
Utána one-time product `kuktam_pro_lifetime`, buy option, nem subscription; non-consumable/lifetime a kliens/backend nem-consume és grant szemantikája. Price/countries a USER döntése, nincs kitalált ár.
Product ID/package létrehozás előtt kétoldali ellenőrzés; ID-t későbbi átnevezhető mezőként ne kezeljük. Activation csak tesztkész backend és kiválasztott track mellett; product aktiválása nem publikálja magát az új appot.
License tester és internal/closed track tester külön jogosultság; ugyanaz a megfelelő Google account legyen a készüléken/telepítéshez. Test track önmagában nem jelent ingyenes vásárlást.
Tesztkártya: approve/decline, cancel, delayed pending→complete/cancel, already-owned, restore, reinstall, account switch; külön refund/revoke teszt csak későbbi engedéllyel. Nem-license tester valódi pénzes lehet. [Play testing](https://developer.android.com/google/play/billing/test).

## 11. Sorrend, felelős, blast radius és checkpoint

Minden sor KÜLÖN feladat/prompt: change → VERIFY → GO vagy STOP/rollback. USER=Console döntés/végrehajtás; ASTRA=repo/kód/ellenőrzés, cloud deploy csak külön explicit engedéllyel.

| Fázis | Teendő / felelős | Radius | VERIFY és STOP-feltétel |
|---|---|---|---|
| P0A | ASTRA: ez a read-only terv | LOW | Riport elkészült; STOP |
| P0B.0 | USER: live project/plan/region/rules/Auth/Play státusz read-back és rules snapshot | LOW | Eltérő projekt/region/permissions → STOP |
| P0B.1 | USER: Blaze billing összekötés, budget címzett/küszöb megadása | MEDIUM | Csak terv/billing változott, CRUD/Auth működik; nem indul deploy |
| P0B.2 | USER: szükséges API-k egyenként: Functions/Run/Build/Artifact Registry/Secret Manager, később Publisher/PubSub/Eventarc/Scheduler | MEDIUM | API-lista diff, semmi nem szolgál még klienst |
| P0B.3 | USER: SA-k/least-privilege, HMAC secret provisioning | HIGH IAM / MEDIUM secret | Binding policy diff, cél-SA access, nincs exportált kulcs |
| P0C | ASTRA: real adapterek, Functions root, runtime, cursor wrapper, deletion barrier/recovery kód; local célzott QA | LOW local | Valódi API mapping/retry/security contract, deployment előtt review |
| P0D.1 | USER + ASTRA: hardened rules külön deploy-fázis | HIGH | Live read-back +1.0.0 CRUD smoke +entitlement write-denied; hibánál biztonságos rules rollback |
| P0D.2 | USER/engedélyezett deploy: callable/deletion/fallback composition, purchase még disabled | MEDIUM | Auth/no-auth/own UID/error smoke; kész deletion sequencing nélkül worker tiltott |
| P0E | USER: Play SA access, merchant, product/ár/országok, license testers; kis checkpointokban | HIGH pénzügyi/jog / MEDIUM config | App/product/identity egyezés, még nincs vásárlás |
| P0F.1 | USER: RTDN topic/trigger/publisher +Console test notification | MEDIUM | Inbox test outcome, grant változatlan, nincs nyílt endpoint |
| P0F.2 | USER: Scheduler külön, bounded dispatch +riasztások | MEDIUM | Cursor/lease és readcost, nincs spin/korai Auth-delete |
| P0G | ASTRA: App Check kliens +online composition csak internal buildben; USER: track feltöltés | HIGH kliensváltás | Backend/rules/secret/adapter/deletion smoke mind PASS; versionCode emelés |
| P0H | USER: valódi Play license/device QA; ASTRA: redacted eredményértékelés | HIGH tesztállapot | Buy/ack/revoke/restore/deletion/offline/session matrix PASS |
| P0I | USER: staging után fokozatos production rollout, később App Check enforcement | HIGH | Valós hibaarány/backlog/költség alapján GO vagy halt |

Merchant ügyintézés P0C mellett külön engedéllyel előkészíthető, de vásárlás nem indulhat a szabályok/backend/deletion/RTDN/maintenance előtt. Így a deletion integráció nem marad a live monetizáció mögé.

## 12. Rollback, nem visszafordítható pontok

| Elem | Rossz állapot jele | Biztonságos válasz |
|---|---|---|
| Rules | Legacy CRUD denied vagy entitlement self-write | Előre mentett SAFE rules; broad write visszaállítás tilos protected doc mellett |
| Functions/adapters | Auth/config error, wrong binding, false transition | Új vásárlások leállítása; korábbi kompatibilis artifact explicit redeploy; schema/ledger nem resetelhető |
| Flutter onlineEnabled | Purchase/restore/session hibák | Internal rollout STOP; release halt +javító, nagyobb versionCode build. Fordítási bool nem távoli kill switch |
| Play product | Hibás ár/ország/product mapping | Új értékesítés deaktiválható; meglévő entitlement nem törölhető és vásárlás nem vonható automatikusan vissza |
| RTDN | Delivery storm/parser/config hiba | Consumer kontrollált szünet, backlog megőrzés, maintenance catch-up; topic/inbox nem törlendő |
| Scheduler | Költség/spin/deletion/ack hiba | Job pause; ack-deadline mellett operator recovery. Ne állítsuk le egyszerre minden recoveryt élő unacked purchase-nál |
| IAM/secret | Túljogosítás/credential hiba | Csak új hibás binding visszavonása; korábbi secret-verzióra pin, v1 kulcs nem megsemmisítendő |
| Blaze/budget | Váratlan fogyasztás | Új munkák stop/maxInstances cap; ne legyen reflex Spark downgrade, ami éles szolgáltatást állíthat le |

Grant/revoke/account deletion és valódi charge nem „git rollback”. Nem törlünk ügyféladatot/jogos ledger-t helyreállítás címén. Revoke/cache/terminal állapotot egy régi bináris sem írhat felül.
Javasolt külön production server purchase-admission kapcsoló: új vásárlás tiltása úgy, hogy existing proof/ack/restore/recovery megmaradjon; ez még composition-feladat, nem létező távoli onlineEnabled kapcsoló.

## 13. Monitoring, költség, security minimum

Monitor: function error/latency; Play permission/config hiba; verify reject arány kategóriánként; ack oldest age/deadline/exhausted; RTDN RETRY/UNRESOLVED age; deletion stuck; Scheduler failure; Firestore read/write és budget. Token/email/raw Play válasz nélkül.
Költségforrás: Functions/Run compute, Firestore ismételt scan/transaction, PubSub, Scheduler, Secret Manager, build/artifact/log tárolás. Kezdetben minInstances0, kicsi maxInstances, bounded scan, logméret/retention beállítás; költségbecslés csak live konfigurációval.
Budget: USER által meghatározott havi összeg, például50/80/100% tényleges +forecast riasztás. Budget alert NEM spending cap és nem automatikus leállítás.
Security checkpoint: least privilege; Secret Manager-only HMAC; ADC/no JSON key; Auth-context UID; recent-auth deletion; backend-only entitlement/ledger; staged App Check; no client ack/consume/HMAC; tombstone/no transfer; safe redacted log.

## 14. Első tényleges production lépés és hátralévő blokkolók

**P0B.0 read-only read-back után az első ajánlott módosítás: Blaze/billing alap + budget riasztás, kizárólag a kuktam-67768 projekten.** Ha már Blaze, nem váltunk újra; a hiányzó budget/setup a következő külön döntés.
Előfeltétel: USER billing jogosultság, helyes project/account és költségriasztási címzett/küszöb; a terv nem helyettesíti a későbbi engedélyt. Ha billing-account budget előre létrehozható, az előzze meg a kapcsolást; ellenkezőleg közvetlenül utána, új workload nélkül.
VERIFY: plan és billing account read-back; meglévő Firestore helye/adat/rules változatlan; Auth és régi kliens egy nem destruktív olvasás/sync próbája; nincs új Function/job/topic/API automatikus bekötés. Utána STOP.
STOP/rollback feltétel: rossz projekt/billing kapcsolat, nincs riasztási kontroll, váratlan service/config változás vagy régi klienshiba. Ne folytassuk API/IAM/deploy lépésekkel; billing visszaváltás csak hatáselemzés után.
Release előtt marad: live állapot igazolása, valós adapterek, strict response mapping, export/runtime, hardened rules smoke, deletion content-barrier/fallback, HMAC provisioning, RTDN/scheduler wrapper/cursors, merchant/product, App Check integráció és valódi Play/device QA.
P0A lezárva. További változtatás nem indult.

PRODUCTION FIREBASE CHANGES: NONE
GOOGLE CLOUD CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
IAM/API CHANGES: NONE
PRODUCTION DEPLOY: NONE
REAL PLAY PURCHASE TEST: NOT PERFORMED
COMMIT: NONE
PUSH: NONE
