# Functions runtime identity split

Dátum: 2026-10-13. LOCAL ONLY. Verdict: role-based source wiring kész; production deploy nem történt.

## Ellenőrzött hívási utak és végleges hozzárendelés

| Export | Identity | Firestore Admin | Secret* | Play API | Auth delete | Trigger |
|---|---|---|---|---|---|---|
| prepareProPurchase | CORE | read/write | igen | nem | nem | v2 callable |
| getEntitlementProof | CORE | read | igen | nem | nem | v2 callable |
| beginAccountDeletion | CORE | read/write | igen | nem | nem | v2 callable |
| authUserDeleted | CORE | read/write | igen | nem | nem | v1 Auth onDelete |
| verifyProPurchase | PLAY | read/write | igen | igen | nem | v2 callable |
| playRtdn | PLAY | read/write | igen | igen | nem | v2 Pub/Sub |
| billingMaintenance | PLAY | read/write | igen | igen | IGEN | v2 Scheduler |
| finalizeAccountDeletion | DELETION | read/write | igen | nem | IGEN | v2 callable |

* A jelenlegi közös lazy composition minden szolgáltatás inicializálásakor betölti a KUKTAM_BINDING_KEYS secretet. A proof/deletion utak saját művelete nem mind használ HMAC-ot, de a jelenlegi graph miatt mindhárom identitynek kell secret access. Ezt ebben az identity-only feladatban nem refaktoráltuk.

Bizonyíték a forrásból:
- transport/monetization.ts: prepare lifecycle inicializálás és binding; proof Firestore-read; verify PurchaseVerifier.
- runtime/composition.ts: verify siker után PurchaseAcknowledger; RTDN real Play/voided adapterek; Maintenance ugyanazokat és AccountDeletionService-t kapja.
- jobs/maintenance.ts deletion ága → AccountDeletionService.resume → LifecycleStore Auth-claim → FirebaseAdminAuthDeletionAdapter.deleteUser. A PLAY identity ezért Auth-delete permissiont is igényel.
- accounts/deletion-gateway.ts begin csak beginAccountDeletion; finalize ellenőrzi a contentet, majd resume.
- accounts/account-deletion.ts handleAuthUserDeleted → beginDeletion(uid,true). lifecycle-store.ts az authGone állapotot megőrzi; az AUTH szakasz authGone esetén DONE-ra lép Auth API-hívás nélkül. Ezért a trusted fallback CORE maradhat. A replay nem indít új Auth-törlést.
- adapters/firebase-auth.ts egyetlen Admin deleteUser hívást használ; a telepített Admin SDK deleteAccount implementációja közvetlen accounts:delete REST hívás, nem előzetes getUser/listUsers.
- A közös graph Play/Auth kliensobjektumokat is létrehoz; az objektum létrehozása nem API-hívás és nem igényel Play/Auth jogosultságot. Csak a tényleges fenti műveleti utak igénylik ezeket.

Nem találtunk konfliktust a kért grouping és a tényleges hívási utak között.

## Pontos helyi változás

- functions/src/runtime/config.ts: a régi identityParameter helyett coreIdentityParameter, playIdentityParameter, deletionIdentityParameter.
- functions/src/index.ts: három defineString deklaráció DEFAULT NÉLKÜL; minden export explicit serviceAccount kötést kap a fenti táblázat szerint. A közös options objektumnak nincs identity fallbackje.
- functions/test/runtime.test.ts: exportonkénti identity/manifest és változatlan runtime options teszt; valódi helyi Firebase CLI resolveParams hiányzó érték/fallback teszt.
- FUNCTIONS_RUNTIME_IDENTITY_SPLIT_REPORT.md: ez a riport.

Paraméterek:
- KUKTAM_CORE_RUNTIME_SERVICE_ACCOUNT
- KUKTAM_PLAY_RUNTIME_SERVICE_ACCOUNT
- KUKTAM_DELETION_RUNTIME_SERVICE_ACCOUNT

Nincs hardcoded production email, default identity, JSON private key vagy új dependency. A régi KUKTAM_RUNTIME_SERVICE_ACCOUNT nem használható helyettesítőként.

Fail closed: hiányzó paraméterértékkel a nem interaktív CLI feloldás hibával leáll. Interaktív CLI esetén explicit értéket kér; nincs automatikus default account. A root import ettől függetlenül értékek és live infrastruktúra nélkül működik. A későbbi konfigurációban három külön, valós SA email szükséges; a kód nem hoz létre identityt és nem ellenőrzi cloudban annak létezését. A paraméterek önmagukban nem akadályozzák meg, hogy egy operátor ugyanazt az emailt adja meg több szerephez: a későbbi IAM/deploy review ellenőrizze a különbözőségüket.

Változatlan: region europe-west1, Node22, timeouts, maxInstances, concurrency, App Check-beállítás, topic, schedule, callable DTO, HMAC, lifecycle/schema, deletion barrier, production composition és összes üzleti logika. Flutter, firebase.json és firestore.rules érintetlen ebben a feladatban.

## Jövőbeli IAM-mátrix – NEM VÉGREHAJTVA

| Identity | Firestore | KUKTAM_BINDING_KEYS | Play Console | Firebase Auth delete | Pub/Sub/Scheduler API runtime-jog |
|---|---|---|---|---|---|
| CORE | required | required | not required | not required | not required |
| PLAY | required | required | required | required (maintenance) | not required a handler kódjához |
| DELETION | required | required | not required | required | not required |

Ajánlás:
- Firestore: roles/datastore.user mindhárom runtime-nak, az alkalmazás adatbázisára szűkített IAM-tervvel ahol támogatott. A CORE csoport is ír, ezért nem elég read-only szerep. Admin SDK-t a kliens rules nem korlátozza.
- Secret: roles/secretmanager.secretAccessor kizárólag a KUKTAM_BINDING_KEYS secreten mindhárom runtime-nak; nem project-wide secret access.
- Play: a már létező kuktam-play-billing@kuktam-67768.iam.gserviceaccount.com később a PLAY paraméter értéke lehet. A Play Console alkalmazásszintű purchase/order jogosultság különül el a GCP IAM-től. CORE/DELETION ne kapjon Play access-t.
- Auth: PLAY és DELETION számára egy szűk custom role firebaseauth.users.delete permissionnel elegendő a jelenlegi közvetlen deleteUser művelethez. A hívási út alapján firebaseauth.users.get/list/update/configs.* nem kell. Full Firebase Auth Admin nem indokolt. További support permissiont csak konkrét runtime hiba bizonyítéka alapján adjunk; most nem javaslunk spekulatív bővítést.
- Pub/Sub/Scheduler: a kód nem publikál, nem pullol és nem kezel jobokat, ezért runtime-nak Pub/Sub/Scheduler Admin/Editor nem kell. A trigger delivery/invoker identity és Google service agent jogosultságai külön infrastruktúra-feladatok. A hívó identitynek célservice-szintű run.invoker kellhet; ezt ne keverjük a handler runtime identityjével. Ha később ugyanazt az accountot választjuk trigger identitynek is, az extra jogot explicit, arra a feladatra kell indokolni. Direct Pub/Sub eseményhez az Eventarc dokumentáció szerint eventReceiver szerep nem szükséges.
- A deployoló principal actAs joga külön; runtime accountnak nem kell deploy-admin szerep. Owner/Editor sehol nem javasolt.

Hivatalos referenciák (nyilvános dokumentáció, nem live Firebase hozzáférés):
- https://firebase.google.com/docs/firestore/security/iam
- https://cloud.google.com/run/docs/configuring/services/secrets
- https://docs.cloud.google.com/identity-platform/docs/reference/rest/v1/accounts/delete
- https://docs.cloud.google.com/identity-platform/docs/access-control
- https://docs.cloud.google.com/eventarc/docs/roles-permissions

## Validáció

- npm --prefix functions run build: PASS.
- npm --prefix functions run test:unit: 200 PASS, 0 FAIL; tartalmazza runtime és production-adapter teszteket.
- Új export-mapping teszt: mind a nyolc endpoint saját paramétere, régió/timeout/maxInstances/secret; scheduler concurrency/schedule/retry; RTDN topic/retry.
- Új CLI-resolution teszt: mindhárom értékkel siker; egyenként hiányzó értékek hibája; üres konfiguráció és kizárólag legacy paraméter hibája; nincs secret resolver vagy hálózat.
- Lazy root import meglévő tesztje: hálózat tiltva, nincs credential/Admin-init mellékhatás.
- Első új tesztfutás: 199 PASS / 1 FAIL, kizárólag az SDK undefined scheduler mezői miatt túl szigorú teszt-összehasonlítás. A manifest JSON-reprezentációra javított assertion után 200/200 PASS; production viselkedés nem változott emiatt.
- Teljes backend emulátor/rules/Admin/concurrency/transport/runtime-integráció: 366 PASS, 0 FAIL, 0 skipped; 218,3 másodperc. Unit + emulátor összesen: 566 PASS.
- git diff --check: PASS. A Git LF/CRLF normalizálási figyelmeztetése nem teszt- vagy whitespace-hiba.

Emulátor: functions munkakönyvtárból node scripts/emulator-tests.cjs, a helyi Node és Android Studio JBR bin PATH-ba téve. A meglévő runner törli a credential környezeti változókat, kizárólag demo-kuktam-local projektet, 127.0.0.1:8088 Firestore-t és METADATA_SERVER_DETECTION=none beállítást használ. Nem futott Firebase production parancs, Play API vagy Auth production hívás.

## Hátralévő production lépések – külön engedély után

1. CORE és DELETION valós service account létrehozása, JSON kulcs nélkül; PLAY már létezik a user által közölt állapot szerint.
2. A három eltérő runtime email paraméterérték rögzítése; régi egyparaméteres deploy-beállítás kivezetése. Nem került most .env a repóba.
3. A fenti szűk IAM-terv jóváhagyása és alkalmazása; custom delete role létrehozása külön feladat.
4. KUKTAM_BINDING_KEYS secret létrehozása, stabil versioned kulcs és secret-level access.
5. Külön trigger/invoker/Publisher/Scheduler wiring terv; csak a szükséges infrastruktúra-jogok.
6. Explicit projecttel, kis lépésekben Functions deploy és valós identity smoke. Az emulátorteszt nem bizonyítja a live IAM-kötéseket.

RUNTIME IDENTITIES: SPLIT
CORE IDENTITY PARAM: KUKTAM_CORE_RUNTIME_SERVICE_ACCOUNT
PLAY IDENTITY PARAM: KUKTAM_PLAY_RUNTIME_SERVICE_ACCOUNT
DELETION IDENTITY PARAM: KUKTAM_DELETION_RUNTIME_SERVICE_ACCOUNT
PLAY SERVICE ACCOUNT CREATED IN CLOUD: EXISTING
CORE SERVICE ACCOUNT CREATED IN CLOUD: NO
DELETION SERVICE ACCOUNT CREATED IN CLOUD: NO
IAM CHANGES: NONE
SECRET CHANGES: NONE
FUNCTIONS DEPLOY: NOT PERFORMED
FIREBASE CHANGES: NONE
GOOGLE CLOUD CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
COMMIT: NONE
PUSH: NONE
