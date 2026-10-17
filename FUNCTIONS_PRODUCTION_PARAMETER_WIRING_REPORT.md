# Functions production parameter wiring

Dátum: 2026-10-13. LOCAL CONFIGURATION + VALIDATION ONLY.
Verdict: a projektspecifikus identity-konfiguráció kész és helyben validált; deploy nem történt.

## Paraméterfájl és verziókezelés

Létrehozva: functions/.env.kuktam-67768 (UTF-8, BOM nélkül).
Pontosan három sor, nincs más paraméter és nincs secret:

```dotenv
KUKTAM_CORE_RUNTIME_SERVICE_ACCOUNT=kuktam-core-runtime@kuktam-67768.iam.gserviceaccount.com
KUKTAM_PLAY_RUNTIME_SERVICE_ACCOUNT=kuktam-play-billing@kuktam-67768.iam.gserviceaccount.com
KUKTAM_DELETION_RUNTIME_SERVICE_ACCOUNT=kuktam-deletion-runtime@kuktam-67768.iam.gserviceaccount.com
```

Előtte a fájl nem létezett, nem volt tracked, és a jelenlegi ignore szabályok nem védték volna. A functions/.gitignore egyetlen konkrét .env.kuktam-67768 szabállyal és magyarázó kommenttel bővült. Most ignored és untracked; git check-ignore -v ezt igazolja. Nincs generic .env vagy új .firebaserc. A service-account címek nem titkok, de a production környezeti fájlt nem szabad véletlenül commitolni; git add -f használata kerülendő.

A firebase.json Functions ignore listájában lévő .env* a deploy source csomagolását szabályozza, NEM Git-ignore. A CLI ettől függetlenül lokálisan betölti a projektspecifikus .env fájlt és feloldja a paramétereket; ezt ténylegesen ellenőriztük.

## Helyileg ellenőrzött exportfeloldás

| Export | Paraméter / identity |
|---|---|
| prepareProPurchase | CORE / kuktam-core-runtime |
| getEntitlementProof | CORE / kuktam-core-runtime |
| beginAccountDeletion | CORE / kuktam-core-runtime |
| authUserDeleted | CORE / kuktam-core-runtime |
| verifyProPurchase | PLAY / kuktam-play-billing |
| playRtdn | PLAY / kuktam-play-billing |
| billingMaintenance | PLAY / kuktam-play-billing |
| finalizeAccountDeletion | DELETION / kuktam-deletion-runtime |

Minden cím suffixe: @kuktam-67768.iam.gserviceaccount.com.
CORE != PLAY, CORE != DELETION, PLAY != DELETION: PASS.
KUKTAM_RUNTIME_SERVICE_ACCOUNT legacy-only konfiguráció: elutasítva, nincs fallback.

A validáció a telepített CLI loadUserEnvs → ParamValue → resolveParams → endpoint serviceAccountEmail CEL resolveString útját használta. Nem csak a szövegfájlt hasonlította össze. Mind a lockolt firebase-tools 15.32.1, mind a tényleges firebase parancs globális 15.24.0 verziója PASS. A szűk két-exportos selector is mindkettőben helyesen oldódik fel.

## Secret contract

A functions/src/index.ts defineSecret(config.hmacSecretName) deklarációt használ; a név KUKTAM_BINDING_KEYS. Mind a nyolc export Secret Manager bindingként kapja. A runtime/composition.ts lazy módon keys.value() → loadBindingKeys értéket tölt be; a secret nem dotenv-paraméter.

A helyi validáció ellenőrizte a secret deklaráció típusát és mind a nyolc export secretEnvironmentVariables mezőjét. Csak string identity-paramétereket adott a CLI resolvernek: a secret resolver nem futott. Secret value-t nem olvastunk, nem másoltunk, nem generáltunk, nem naplóztunk. A user közlése szerint enabled Secret Manager version 1 létezik; ezt production hívással nem ellenőriztük. A Secret Manager numerikus version 1 külön fogalom a JSON-ban elvárt v1 HMAC-verziótól.

## Legbiztonságosabb első Functions deploy jelöltek

Továbbra is prepareProPurchase + getEntitlementProof, mindkettő CORE identity, europe-west1, Node22, v2 callable.
- getEntitlementProof: lifecycle/entitlement olvasás, nem ír, nincs Play/Auth-delete hívás.
- prepareProPurchase: authenticated UID mellett ACTIVE ellenőrzés, lifecycle inicializálás/binding-regisztrálás. Firestore-írást végezhet meghíváskor; nem vásárol, nem grantol Pro-t, nincs Play/Auth-delete hívás.
- Mindkettőnek kell a HMAC secret a közös composition inicializálásához.
- A közös graph más adapterobjektumokat is létrehoz, de ez nem dispatch-el Play/Auth/network műveletet önmagában.
- Nem kerül ki verify, deletion callable/trigger, RTDN vagy maintenance. A Flutter onlineEnabled kapcsoló változatlan.

Pontos JAVASOLT parancs a repository gyökeréből, NEM FUTTATVA:

```text
firebase deploy --only functions:monetization:prepareProPurchase,functions:monetization:getEntitlementProof --project kuktam-67768
```

A monetization codebase explicit. Nem full Functions deploy; nem rules/indexes/Storage/Hosting deploy és nem RTDN/Auth/Scheduler export deploy.

FONTOS: a szűk export-selector nem jelent nulla infrastruktúra-mellékhatást. Az első v2 Functions deploy build artifactot, Cloud Run szolgáltatásokat és kapcsolódó infrastruktúrát hoz létre. A CLI előkészítése szükséges API-kat is engedélyezhet és service identityt generálhat. Ezért a fenti parancs nem tekinthető most feltétel nélkül engedélyezettnek.

## Még ellenőrizendő production előfeltételek – NEM JAVÍTVA

A user által közölt három account, Datastore User, secret-szintű Secret Accessor, két Auth-delete role és enabled secret adott kiindulási állapot; nem végeztünk live megerősítést.

További lehetséges deploy-blokkolók:
- Cloud Functions, Cloud Build, Artifact Registry, Cloud Run, Secret Manager és a CLI v2 előkészítése által érintett Storage/Eventarc/PubSub API-k állapota.
- A CLI codebase discovery a nem kijelölt exportok deklarált API-igényeit is láthatja; ezért Scheduler/API-enable vagy service-agent létrehozás lehetőségét nem szabad kizártnak tekinteni pusztán a két-export selectorból.
- Google-managed Cloud Functions/build/Artifact Registry/Cloud Run és szükség esetén Eventarc/PubSub service agentek megléte és szükséges szerepei. A runtime SA nem azonos a build/deploy/delivery identityvel.
- A tényleges deployoló principal cloudfunctions deploy/build műveleti jogosultságai és iam.serviceAccounts.actAs joga a CORE accounton (pl. Service Account User ezen az accounton, nem indokolatlanul egész projekten).
- CLI-verziótól függően a preflight a default App Engine accounton is tesztelhet actAs-t; váratlan ilyen igénynél külön felülvizsgálat kell, nem automatikus széles IAM-grant.
- Callable elérhetőség IAM policy beállításához szükséges jogosultságok (Functions/Run setIamPolicy); a callable Auth ellenőrzése ettől függetlenül kötelező marad.
- A build identity Artifact Registry/upload/logging hozzáférése; első deploynál repository/build erőforrások szükségesek lehetnek.
- App Check jelenleg nem enforced. Első korlátozott smoke-hoz nem blocker; public enable előtt külön staged ellenőrzés kell.

Nincs bizonyított helyi paraméter-/export-blokkoló. A live deploy-előfeltételek NOT VERIFIED, nem állítjuk róluk, hogy hiányoznak. Nem történt API enable, IAM módosítás vagy automatikus javítás.

## Tesztek és pontos helyi változások

- npm --prefix functions run build: PASS.
- node --test functions/lib/test/runtime.test.js functions/lib/test/production-adapters.test.js: 88 PASS, 0 FAIL.
- Helyi CLI contract ellenőrzés: 15.32.1 PASS és 15.24.0 PASS; három pontos dotenv-érték, három eltérő account, nyolc endpoint, legacy rejection, secret kizárása, két-export selector.
- A contract ellenőrzés alatt http.request, https.request és fetch letiltva; nem hívtuk a deploy preparert, secret resolvert vagy Firebase API-t. A CLI verziók eltérő resolveParams szignatúráját és ParamValue típusát az első ellenőrzési próbák után helyesbítettük; nincs forráskódbeli javítás/upgrade.
- git diff --check: PASS.
- Build közben npm verziófrissítési értesítés jelent meg; frissítés nem történt.

Ebben a feladatban változott: functions/.gitignore; az ignored functions/.env.kuktam-67768 létrejött; ez a riport létrejött. Runtime source, tesztforrás, firebase.json, rules, dependency és Flutter nem változott. Korábbi munkapéldány-változások megőrizve.

PRODUCTION PROJECT: kuktam-67768
CORE PARAM: CONFIGURED
PLAY PARAM: CONFIGURED
DELETION PARAM: CONFIGURED
THREE IDENTITIES DISTINCT: YES
SECRET VALUE COPIED TO ENV: NO
LEGACY IDENTITY FALLBACK: NONE
FIRST DEPLOY CANDIDATES: prepareProPurchase, getEntitlementProof
FIRST DEPLOY COMMAND: firebase deploy --only functions:monetization:prepareProPurchase,functions:monetization:getEntitlementProof --project kuktam-67768
DEPLOY BLOCKERS: nincs helyi blocker; live API/service-agent/build/deployer IAM és CORE actAs előfeltételek NOT VERIFIED
FUNCTIONS DEPLOY: NOT PERFORMED
FIREBASE PRODUCTION CHANGES: NONE
GOOGLE CLOUD CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
COMMIT: NONE
PUSH: NONE
