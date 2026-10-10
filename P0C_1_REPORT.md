# P0C.1 – Account deletion sequencing hardening

Dátum: 2026-10-09. Local code only; nincs deploy vagy production bekötés.

## Verdict

**READY FOR P0C.2** a helyi, koordinált deletion contract szintjén. A modern backend Auth-delete kizárólag backend által tartósan igazolt content cleanup után claimelhető. Production aktiválás továbbra sem történt.

## Audit pontosítása és eredeti rés

A P0A megfogalmazását pontosítani kell: a fázis elején a LifecycleStore már végzett közvetlen root/recipes/shopping ürességellenőrzést az Auth-claim előtt. Nem volt teljesen ellenőrizetlen Auth-delete út.
A hiány a tartós, strict verziózott cleanup evidence, a billing cleanup előtti barrier, az explicit finalize/verify művelet és a modern kliens coordination volt. Ezek kerültek most be; a meglévő utolsó Auth-claim ellenőrzés megmaradt.

## Modern sorrend

1. Kliens reauth; későbbi authenticated transport friss tokenjéből szerveroldali recent-auth ellenőrzés.
2. `DeletionGateway.begin`: üres body, UID kizárólag trusted auth-contextből.
3. `beginAccountDeletion`: idempotens ACTIVE→DELETING, generation/fencing és inaktív effective entitlement; cleanup PENDING.
4. Kliens lapozva törli a recipes/shopping dokumentumokat, majd a user rootot.
5. `DeletionGateway.finalize` → `finalizeContent` → `LifecycleStore.verifyDeletionContent`: szerveres ürességellenőrzés, tartós VERIFIED.
6. A közös writer billing cleanupot végez; Auth-claim előtt ismét ellenőrzi a contentet, a markert, generationt és lease-t.
7. Backend Auth adapter, majd DELETED/DONE. Modern kliens nem hív `user.delete()`-et.

## Schema és invariant

- Deletion operation v2: `cleanupState: PENDING | VERIFIED`; a többi operation/stage/lease mező változatlan.
- Strict v1 olvasás normalizál v2-re, cleanup evidence nélkül **PENDING** értékkel. Nincs tömeges migráció; v2 mező v1 dokumentumba csempészve is elutasított.
- Ismeretlen verzió, hiányzó/hibás evidence, extra mező továbbra is hiba. Régi modern AUTH lease evidence nélkül sem claimelhető/complete-elhető.
- Bármely modern deletionStep PENDING állapotban `cleanupIncomplete`; így maintenance/retry/crash takeover nem kerülheti meg a barrierrt, és billing cleanup sem indul túl korán.
- A verify transaction olvassa a markert és operationt; csak DELETING és egyező generation esetén igazolhat. DONE replay idempotens.
- VERIFIED replay nem ír fölöslegesen. Ha az utolsó Auth-claim ellenőrzése mégis tartalmat talál, visszaállítja PENDING-re és törli a claimet.

## Content verification és recovery

Három bounded Admin olvasás: user root get, recipes limit(1), shopping limit(1). Root hiánya önmagában nem elég; a subcollectionöket külön ellenőrizzük. Tranzakciós marker/operation fencing marad.
A jelenlegi app kliensoldali user-owned Firestore tartalma a két collection és root. Az `ingredients` közös katalógus; nem törlendő user content. Entitlement/grant/billing adatok külön backend cleanup alá tartoznak. Jövőbeli user collection hozzáadásakor a törlési contractot is bővíteni kell.
Félbeszakadt kliens: DELETING marad, Auth életben marad, a hardened rules create/update-ot tilt, read/delete-ot enged. Új próbálkozás ugyanazon UID-val reauth→idempotens begin→maradék content cleanup→finalize. Nincs automatikus visszaaktiválás.
Ha a finalize/response megszakad VERIFIED után, maintenance folytathatja a már engedélyezett cleanupot. Ha a kliens soha nem tér vissza PENDING állapotból, a folyamat biztonságosan vár; automatikus user-content purge most nincs.

## Recent-auth és legacy fallback

`deletion-gateway.ts`: trusted Firebase runtime UID + auth_time seconds contract; hiányzó/régi/jövőbeli érték tiltott. Alapértelmezett maximum 5 perc, a policy helper paraméterezhető. Body timestamp/UID nem elfogadott. Finalize már elindított deletion folytatása, továbbra is authenticated saját UID-val.
A runtime wrappernek majd valódi verified request.auth/token.auth_time-ból kell képeznie ezt a contextet, és reauth után friss tokent használnia; ebben a fázisban nincs callable export.
`handleAuthUserDeleted` kizárólag trusted Auth-deletion event út: az Auth már eltűnt, ezért nem hívja újra a delete adaptert. Billing cleanup, inaktív entitlement, tombstone/no-transfer és replay fencing megmarad.
A modern gateway nem exportál fallback metódust, és nem fogad `authGone`/cleanupComplete/UID body-mezőket. Belső Admin kód továbbra is trusted boundary; a fallbackot később sem szabad kliens callable-ként kitenni.
Legacy fallback nem töröl orphan recipes/shopping tartalmat: ha a régi kliens vagy külső Admin Auth-törlés után ilyet hátrahagyott, külön ellenőrzött cleanup/support feladat marad. Ezt nem tekintjük modern Auth-delete engedélynek.

## Flutter coordination

Új `AccountDeletionGateway`, UID- és evidence-paraméter nélküli begin/finalize contract. `DeletionCompletion` megkülönbözteti completed, cleanupIncomplete, retryRequired, supportRequired eredményeket; a befejezetlen művelet kivétellel tér vissza, nem jelez téves sikert.
Az AccountDeletionRepository opcionálisan fogad gatewayt. Reauth/begin/content-hiba után a későbbi lépések nem indulnak; finalize ismételhető. UID-ellenőrzések és a modern ág auth-session figyelője védik a logout/új belépés közbeni régi munkát.
A backend sikeres Auth-törlésének null session eseménye megengedett; másik aktuális accountnál a completion nem folytathat provider cleanupot.
Gateway nélkül a jelenleg kiadott legacy flow marad, nem hív hiányzó endpointot. `main.dart`, onlineEnabled=false és production composition változatlan. A meglévő dialog retry/warning UX változatlan.
Az első célzott Flutter futás a session-subscription lezárásának awaitje miatt widget timeoutokat jelzett; a listener csak modern ágon él, lemondása nem tartja függőben az UI-t. A javított célzott és teljes suite zöld.

## Érintett fájlok

- `functions/src/accounts/deletion-contract.ts`: v2 strict schema, cleanup outcome.
- `functions/src/accounts/account-deletion.ts`: finalize és barrier outcome továbbítása, fallback contract komment.
- `functions/src/accounts/deletion-gateway.ts` – új: modern transport-neutral surface + recent-auth helper.
- `functions/src/billing/lifecycle-store.ts`: tartós verification, stage/claim/completion barrier.
- `functions/test/deletion-core.test.ts`, `functions/test/deletion.test.ts`: schema/policy/emulator/security/recovery tesztek; korábbi tesztek explicit verify lépése.
- `functions/scripts/emulator-tests.cjs`: opcionális `--deletion` célzott suite; változatlan fail-closed demo project/localhost.
- `lib/features/auth/data/repositories/account_deletion_gateway.dart` – új contract.
- `lib/features/auth/data/repositories/account_deletion_repository.dart`: opcionális koordináció és session fencing.
- `test/auth/account_deletion_coordination_test.dart` – új: 11 teszt.
- `P0C_1_REPORT.md` – ez a riport.

Rules, maintenance core, Play adapterek, UI widgetek és produkciós konfiguráció nem módosultak. A maintenance a közös deletion service-en keresztül örökli az új védelmet.

## Tesztek és security ellenőrzés

| Ellenőrzés | Eredmény |
|---|---|
| TypeScript build | PASS |
| Teljes backend unit | 112 PASS |
| Célzott deletion + maintenance + rules/Admin emulator | 148 PASS |
| Célzott Flutter deletion/coordination/Pro UI | 63 PASS |
| Teljes Flutter suite | 1107 PASS /1 korábbi opt-in skipped |
| Flutter analyze --no-pub | CLEAN |
| Teljes backend emulator/rules/Admin/concurrency/transport regresszió | 351 PASS /0 fail |
| Érintett Dart formatter | Rendezve |
| Tracked + érintett új fájlok whitespace check | CLEAN, CRLF figyelembe véve |

A teljes helyi regresszió is lefutott, nem maradt hátra full suite. A 148 célzott emulatoros és63 célzott Flutter eredmény részhalmaz; nem adandó hozzá újra a teljes suite számaihoz. Ellenőrzési naplók: `C:/Users/gabor/AppData/Local/Temp/kuktam-p0c1-{targeted,flutter-targeted,full-backend,full-flutter,analyze}.log`.

A célzott tesztek lefedik: külön recipes/shopping/root maradék; kezdeti PENDING; üres content evidence nélkül is tilt; párhuzamos idempotens verify; régi v1/expired lease; utólagos tartalom és újraellenőrzés; malformed evidence; generation fencing; maintenance várakozás; fallback/no-transfer; modern body-spoof tiltás; reauth időhatárok.
A meglévő deletion regresszió ellenőrzi az inaktív entitlementet, duplicate begin/worker, grant/ledger tombstone, stale ack/verify, RTDN race, crash és Auth retry eseteket.
Security search: kliens `user.delete()` csak gateway nélküli legacy ágon; backend `deleteUser()` kizárólag a store auth-claim eredménye után. Nincs kliensből megbízható cleanupComplete vagy request-body UID, nincs raw-token logging, nincs új reactivation út. A modern és fallback boundary külön tesztelt.

## Korlátok és P0C.2 előfeltételek

Nincs ismert nyitott P0/P1 a tesztelt modern helyi deletion flow-ban. A garancia a hardened rules és account-marker-t tiszteletben tartó backend writerek mellett érvényes; tetszőleges Admin-konzolos content-visszaírás a külső Auth-hívás alatt nem tehető atomikussá Firestore-tranzakcióval.
Production előtt szükséges: modern gateway valódi authenticated bekötése, recent-auth token mapping, hardened rules deploy-smoke, Auth adapter és megbízható fallback trigger, megfelelő session-aware response mapping, valamint legacy orphan-content üzemeltetési döntés. Most ezek nem készültek el és nem aktiválódtak.
P0C.2 csak külön kijelölt helyi adapter/composition scope-pal induljon; a production account deletion teszt és éles bekötés továbbra is külön engedélyt igényel.

PRODUCTION FIREBASE CHANGES: NONE
GOOGLE CLOUD CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
IAM/API CHANGES: NONE
PRODUCTION DEPLOY: NONE
REAL PLAY PURCHASE TEST: NOT PERFORMED
BLAZE UPGRADE: NOT PERFORMED
COMMIT: NONE
PUSH: NONE
