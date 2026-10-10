# N4B.8 – backend closure audit

Dátum: 2026-10-08. Hatókör: N1–N4B.7 helyi backend, fake adapterek,
`demo-kuktam-local` Firestore emulator. Ez nem production release-engedély.
Eredmény: **READY FOR N5 (helyi fejlesztés)**. Nincs ismert nyitott P0/P1
backend correctness blokkoló. N5 nem indult el.

## Product és domain contract

Free: korlátlan kézi recept/shopping CRUD, keresés, cloud sync, reklám nélkül.
Pro: recept/shopping szöveges import, scaling, scaled shopping, Mit főzzek;
image import minden entitlement mellett unavailable. Nincs limit, counter,
slot, subscription vagy kliensoldali `isPro` source of truth.
Grantok: PLAY_PURCHASE / PROMO / ADMIN / TEST, OR; start inclusive, expiry
exclusive; revoked/inactive nem ad hozzáférést. Unknown/checking nem Free.
N1 immutable domain nem végez IO-t, és továbbra sincs a jelenlegi UI-ra kötve.

## Audit findings és javítások

| Súly | Megállapítás | Lezárás |
|---|---|---|
| P1 | Ack completion lejárt lease mellett, takeover nélkül is commitolhatott | Lejárat újraellenőrzése a közös tranzakcióban; előtte/pontosan/utána teszt |
| P1 | A régi account marker advance inaktív account mellett aktív effective snapshotot hagyott | Átkötés LifecycleStore-ra; marker + effective inaktiválás atomikus, replay revision-stabil |
| P1 | Auth cleanup megelőzhette a kliens tartalomtörlését | AUTH claim előtt root/recipes/shopping ürességellenőrzés; tartalom megmarad és retry lehetséges |
| P1 | Törlés közben új kliensadat visszakerülhetett a kiürített collectionbe | LOCAL rules create/update tiltás DELETING/DELETED markerre; read/delete megmarad |
| P1 | Cleanup sérült grantot/inboxot/ack rekordot, illetve hibás token/binding identitást is vakon törölhetett | Strict parse/identity ellenőrzés a törlési tranzakcióban, hibás rekord megmarad |
| P2 | Budget elfogyásakor későbbi maintenance kategóriák éhezhettek | Visszaadott/bemeneti nextCategory + meglévő dokumentumcursor; körbefordulás |
| P2 | Millis összehasonlítás elveszíthette az időbélyeg finomabb pontosságát | Exact compareTime lease/due/schema határokon; millis retry és grant boundary felfelé kerekítve |
| P3 | Régi tesztek törlés után aktív effective snapshotot vártak | Elvárások az elfogadott azonnali inaktiváláshoz igazítva; a grant maga nem kerül hamis Play revoke állapotba |

A tiszta domain nanomásodperces határokat tesztel. A tárolt Firestore-időbélyeg
mikromásodperces pontosságú; emulator teszt ehhez illeszkedik. A millis policy
kerekítése legfeljebb 1 ms késést enged, korai expiry/retry-t nem.

## Writer map / trust boundary

| Writer | Hívó | Írás és védelem |
|---|---|---|
| LifecycleStore.commit | PurchaseVerifier; RTDN/maintenance ezután | Auth UID, backend package/product, friss adapteradat, registry owner, account generation + lifecycleRevision; ledger/grant/effective egy TX |
| LifecycleStore.commitVoided | PurchaseRevoker | Friss autoritatív negatív bizonyíték, owner + két revision fence; csak token-specifikus PLAY grant; ack invalidálás ugyanabban a TX-ben |
| LifecycleStore.claimAck/completeAck | PurchaseAcknowledger | Durable grant/effective, ACTIVE marker, generation/revision, lease ID/expiry, recoveryGeneration; külső ack TX-en kívül |
| LifecycleStore.recordCheck/recomputeGrants | Maintenance | Account/revision és opcionális maintenance lease guard; operational timestamp nem lifecycle változás |
| LifecycleStore.advanceAccountMarker/beginDeletion | AccountLifecycleStore / AccountDeletionService | Monoton marker, azonnali inactive effective; nincs account reactivation |
| LifecycleStore.deletionStep/completeDeletionAuth | Deletion service / maintenance | Operation/generation/stage, Auth lease/expiry; lapozott cleanup, token/binding tombstone; külső Auth hívás TX-en kívül |
| AccountLifecycleStore.initializeActive/register/tombstone | Megbízható backend caller | Csak marker/registry; non-ACTIVE account nem regisztrálható újra |
| RtdnInboxStore | RTDN processor / maintenance | Csak inbox technikai állapot, source+message dedupe, lease, attempts, transient token |
| MaintenanceStore | Maintenance | Csak technikai work/checkpoint/lease; nincs közvetlen purchase/grant/effective írás |

Audit: nincs parser/RTDN/reconciliation/deletion orchestrator direct purchase writer.
A hash függvények `.update()` hívásai kriptográfiai műveletek, nem adatbázisírások.
A LifecycleStore megbízható backend API, nem publikus callable DTO felület.

## Állapot, revision, replay

- PURCHASED csak hiteles lookup + binding + ACTIVE account után grantolható.
- PENDING nem grantolható/acknowledge-olható. Financial refund, not-found,
  timeout, hibás/ambiguous/config response nem revoke-bizonyíték.
- Autoritatív revoke terminális; késői purchased/ack/retry nem aktiválhatja újra.
- lifecycleRevision: purchase/ack/revoke tartalmi változás. Lease/retry/check idő
  nem növeli. Effective revision: active, validUntil vagy source-set változás;
  PLAY+PROMO → PROMO változásnak számít. Duplicate állapot nem növeli.
- Account generation: ACTIVE → DELETING → DELETED; nincs visszaút.
- Ack recoveryGeneration csak friss re-verification után, totalAttempts megmarad.
- V1 strict reader normalizál, nem tömeges migration; v2 unknown mező/verzió
  fail-closed. Explicit ellenőrzött write adoptálhat v2-t; subdocument nem vész el.

## Concurrency / crash mátrix és bizonyíték

| Események | Elvárt védelem | Meglévő/új tesztcsalád |
|---|---|---|
| Verify ↔ verify / más UID | Egy owner, determinisztikus grant; stale retry | verification, lifecycle-store/integration |
| Verify ↔ revoke | Újabb terminal revision győz | revoke, RTDN, maintenance |
| Verify ↔ DELETING/DELETED | Account generation / marker megakadályozza commitot | lifecycle-integration, deletion |
| Ack claim/external call ↔ revoke/delete | Lease/revision/generation; nincs reactivation | acknowledgment, revoke, deletion |
| Ack expiry / takeover / késői completion | Exact expiry és lease identity | új closure + meglévő ack tesztek |
| RTDN duplicate/out-of-order | Egy inbox lease; fresh lookup; terminal purchase barrier | rtdn |
| Maintenance ↔ live verify/revoke/ack | Work lease a lifecycle TX-ben + revision | maintenance |
| Auth completion ↔ fallback / takeover | Operation/generation/lease; notFound idempotens siker | deletion |
| Barrier/page commit failure | TX all-or-nothing; első maradék oldal újraolvasása | deletion rollback injection |
| Lookup után crash | Új lookup szükséges, nincs cached-payload döntés | rtdn/maintenance |
| Lifecycle commit után inbox/work commit crash | Replay idempotens, lease takeover | rtdn/maintenance |
| Play/Auth siker után local commit crash | Already acknowledged/notFound, nincs dupla grant | acknowledgment/deletion |
| Sérült grant/ledger/inbox/ack/binding | Nincs vak felülírás/törlés, Auth nem indul | új deletion closure |

## Maintenance, időzítés és fairness

A run input/output `cursors` ÉS `nextCategory` értékeit a későbbi transportnak
meg kell őriznie. Dokumentum-ID lapozás: limit, stabil cursor, null wrap;
új, cursor előtti elem a következő körben kerül sorra; törölt cursor is folytatható.
Nem garantálunk véges késést korlátlanul növő, feldolgozási kapacitást meghaladó
backlogra. A bounded ID-scan költsége/latenciája production load alatt mérendő.

120 s lease / 30 s IO timeout: megfelelő induló technikai default, konfigurálható.
60 s retry base, exponential equal jitter, 6 h cap; 8 attempt egy recovery kör,
nem végleges Pro-vesztés. Max recovery generation jelenleg 3, utána operator.
Napi active recheck ±20%; unresolved 30 min–1 nap; voided catch-up 6 h,
30 nap technikai lookback (nem retention). Javasolt későbbi invocation: ack/retry,
lease, grant/deletion ~5 perc; unresolved ~30 perc; exhausted recovery ~1 óra.
Scheduler nincs. Trusted purchase completion time hiányában ack deadline nem
vezethető le verifiedAt-ból; production adapter előtt kötelező újravizsgálni.

## Account deletion / privacy / retention

Jövőbeli Flutter sorrend: recent reauth + stabil UID → backend begin barrier →
kliens server-read lapozott recipes/shopping/root delete → backend resume/Auth
finish. Hiba után a marker DELETING marad, a még meglevő adatok olvashatók és
törölhetők. A billing cleanup nem törli helyette a recept/shopping tartalmat.
Az AUTH claim megvárja az ismert adatok hiányát. Local rules addig tiltja az új
create/update-ot, ezért régi/konkurens kliens sem töltheti újra az üres listát.
Az Auth-already-gone fallback nem hív Auth delete-et, és nem tud elveszett Authot
visszaállítani; megmaradó user-content külön meglévő adatkezelési/support feladat.

Ledger tombstone megtartja a tokenHash kulcsot, minimális lifecycle auditot;
eltávolítja raw tokent, boundUid-t, opaque bindinget, ack és purchase work állapotot.
Binding TOMBSTONED megtartja opaque ID/keyVersion-t, nem tart UID-t.
Account marker/operation UID-alapú technikai replay barrier marad; nem anonim adat.
Ehhez lifecycle-alapú szükségességi/compliance felülvizsgálat kell, nem önkényes TTL.
Ismert-owner inbox törlődik; owner nélkül maradó unresolved event nem rendelhető
önkényesen account deletionhöz. Transient token csak technikai retry szükségletig,
terminal eventnél purge; operator hold későbbi célzott döntést igényel.

Nincs console/logger használat a backend source-ban. Publikus service outcome fix
kód és hash; adapter raw exception nem szivárog ki. Belső claim/parsed DTO tartalmazhat
tokent, cursor tartalmazhat UID-t: ezeket nem szabad logolni/Flutternek visszaadni.
HMAC v1 stabil domain-separated server secretből, nem email/név; keyVersion mező
nem jelent kész rotációt. Későbbi rotációhoz régi key-verifikáció és tombstone
megőrzés kell; meglévő v1 azonosító nem írható át automatikusan.

## Local rules és compatibility

Backend-only: billingPurchases (ack alút is), billingAccountBindings,
accountLifecycle, accountDeletions, rtdnInbox, billingMaintenance, user grantok:
client get/list/create/update/delete DENY. Saját effective entitlement read-only.
Ingredients auth read-only. Ismeretlen útvonal deny. Nincs permissive wildcard.
Aktív vagy legacy marker nélküli user recipe/shopping CRUD változatlan.
DELETING/DELETED esetén csak read/delete marad; root továbbra is own get/delete.
Nincs production deploy. A jelenlegi Flutter deletion flow nem lett átírva.

## N5 interface expectations és production gap

N5 helyi fejlesztéshez: UID-scoped entitlement repository, strict effective schema
adapter (active, validUntil, sources, revision, verifiedAt/updatedAt), auth-generation
fenced stream/purchase callback, unknown/checking külön Free, fenti hibakódok.
Play token backend verificationre megy; client purchase callback önmagában nem Pro.
Server acknowledgment a tulajdonos: Flutter completion/restore viselkedést ehhez
kell hangolni. Deleted account más UID-ra restore/transfer automatikusan tilos.

30 nap cache grace: N5 feladata, nincs most implementálva. Az effective verifiedAt
jelenleg nem frissül változatlan semantic replaynél, nem használható önmagában
friss offline igazolásként. N5 trusted online-read/proof contract külön freshness
időpontot igényel; cached Firestore snapshot vagy local clock nem hosszabbíthatja
önmagát. Cache UID-váltáskor eldobandó; verified inactive/revoke felülírja; expiry
és offlineValidUntil közül a korábbi korlát érvényes. Signature/secure storage,
clock rollback és tartós offline UX az N5 helyi contract feladata, nem kész funkció.

Production előtt külön engedélyezett fázis: Blaze/runtime; valódi purchase/ack/voided
adapter és API mapping; Play Developer API, dedikált IAM/service identity; Secret
Manager/HMAC provisioning; Pub/Sub és Play RTDN binding; Functions/callable Auth
transport recent-auth validation; Auth fallback trigger; Scheduler és tartós cursor;
App Check/Play Integrity; merchant/product/license testers; real buy/restore/refund
és delete tesztek; monitoring/operator recovery; local rules deploy és szükség esetén
indexek. Ezek jelenlegi live állapotát ez a helyi audit nem ellenőrizte és nem módosította.

## Maradó korlátok

- P2: malformed rekord safe stop; automatikus schema-repair nincs. Cleanup strukturált
  cleanupRetryRequired, rekord érintetlen, operator javítás kell; bounded scan nem
  helyettesíti production alertet és support runbookot.
- P2: ID-scan és all-grant olvasás költsége; recompute 500 grant fölött fail-closed.
  Nincs új queue/instrumentation. Reconciliation lookbackon túli outage operátori ügy.
- P2: a valós adapter és transport nélküli teszt nem bizonyít Play/provider/network
  kompatibilitást. A source trust boundary-t a későbbi transportnak kell betartania.
- P3: README korábbi fejezetei fázistörténet; ezt a closure contractot kell követni.

## N4B.8 fájlok és ellenőrzés

Módosítva: firestore.rules; functions/src/accounts/account-lifecycle.ts,
account-lifecycle-store.ts; billing/acknowledgment-state.ts, lifecycle-store.ts,
rtdn/inbox-store.ts; jobs/maintenance.ts, maintenance-store.ts; test/lifecycle-core,
lifecycle-integration, deletion, maintenance, rules tesztek; functions/README.md.
Új: functions/N4B-CLOSURE.md. Nincs új dependency, Dart/UI vagy production config módosítás.

Végleges ellenőrzés:
- Backend unit: 110 PASS.
- Rules/Admin/emulator/concurrency: 315 PASS, 0 failed/skipped.
- Összes backend: 425 PASS; N4B.8 hozzáadott teszt: 21 (1 unit + 20 emulator).
- N1 célzott Flutter: 42 PASS (része a teljes Flutter suite-nak).
- Teljes Flutter: 759 PASS / 1 korábban is skipped, 0 failed.
- Egyedi sikeres backend + Flutter tesztek: 1184; N1-et nem számoljuk kétszer.
- TypeScript strict build: PASS; flutter analyze --no-pub: No issues found.
- Tracked diff és mind a 72 untracked fájl whitespace check: PASS.
- A korábbi hibás deletion-elvárások és az emulatorban 1 ns-ra építő fixture-ek
  korrigálása után a teljes backend-kör újra lefutott; nem maradt elrejtett failure.
- Repo továbbra is korábbi, nem commitolt N1–N4B munkát tartalmaz. Az előzetes
  analysis_options.yaml változást megőriztük; nincs commit/push/stage művelet.

**READY FOR N5**: csak helyi Flutter Billing/cache/grace fejlesztéshez, fenti
freshness/auth/ack contracttal és fake backenddel. Éles kiadás továbbra is külön
production-infra, valós adapter- és Play-tesztekhez kötött.

PRODUCTION FIREBASE CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
PRODUCTION DEPLOY: NONE
IAM/API CHANGES: NONE
COMMIT: NONE
PUSH: NONE
