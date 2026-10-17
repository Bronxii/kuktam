# Firestore production rules wiring – helyi előkészítés

Dátum: 2026-10-13 (Europe/Budapest)
Verdict: a helyi rules target bekötve; production deploy még NEM engedélyezett.

## Pontos változás

Kizárólag a firebase.json kapott új felső szintű blokkot:

```json
"firestore": {
  "rules": "firestore.rules"
}
```

A korábbi Flutter- és Functions-konfiguráció változatlan; ezt JSON strukturális összehasonlítás igazolta a HEAD változathoz. Nincs új indexes, Storage vagy Hosting konfiguráció. A firestore.rules tartalma nem változott. Nem készült .firebaserc vagy implicit default production projekt.

PRODUCTION RULES SOURCE: firestore.rules
A firebase.json és firebase.emulators.json ugyanarra a gyökérbeli fájlra mutat. A rules.test.ts is közvetlenül ezt olvassa. A repository forrásfájl-keresése egyetlen *.rules fájlt talált; nincs alternatív vagy generált Firestore ruleset. Az Android backup_rules.xml nem Firestore-szabályzat.

## Későbbi production parancs – NEM FUTTATVA

Repository gyökeréből, jóváhagyás és a lentiek ellenőrzése UTÁN:

```text
firebase deploy --only firestore:rules --project kuktam-67768
```

Az explicit --project minden production műveletnél kötelező eljárás. A konfiguráció önmagában nem tiltja meg, hogy valaki elhagyja ezt; ezért ne használjunk csupasz firebase deploy parancsot.

Pontos deploy-scope: a kuktam-67768 projekt (default) Firestore adatbázisának rules release-e. Nem Functions, Auth trigger, Scheduler, Pub/Sub, indexes, Storage rules vagy Hosting deploy. A Functions predeploy build sem része ennek a rules-only célnak.

Ellenőrzés: a lockolt firebase-tools 15.32.1 helyi deploy/firestore/prepare.js kódja firestore:rules esetén firestoreIndexes=false, firestoreRules=true értékeket állít be; a deploy.js/release.js külön őrzi az index- és rules-ágat. fsConfig.js ebben az objektumos konfigurációban (default) adatbázist választ.

Fontos CLI-előfeltétel: a prepare ellenőrzi/engedélyezheti a Firestore API-t, és nem létező adatbázisnál létrehozást kezdeményezhet (hiányzó location mellett nam5 alapértékkel). Ezért deploy előtt a Console-ban igazolni kell: HELYES PROJEKT, MEGLÉVŐ (default) DB, eur3. Ha bármelyik eltér vagy létrehozás/API-enable jelenik meg: STOP, ne hagyjuk jóvá. A jelenlegi feladatban ilyen CLI production parancs nem futott.

## Helyi tesztek és ismételhető emulátorparancs

A functions könyvtárból futtatott build:

```text
npm run build
```

PASS. Csak generált functions/lib output; backend forrásmódosítás nincs.

Az emulátoros tesztfutás parancsa:

```text
node node_modules/firebase-tools/lib/bin/firebase.js emulators:exec --only firestore --project demo-kuktam-local --config ../firebase.emulators.json "node --test --test-concurrency=1 lib/test/rules.test.js lib/test/deletion.test.js lib/test/runtime-integration.test.js"
```

Biztonságos futtatási környezet (a mostani futtató ezt állította be):
- GOOGLE_APPLICATION_CREDENTIALS, FIREBASE_TOKEN, FIREBASE_CONFIG, FIRESTORE_EMULATOR_HOST és FIREBASE_AUTH_EMULATOR_HOST törölve a gyermekfolyamatból.
- GCLOUD_PROJECT és GOOGLE_CLOUD_PROJECT = demo-kuktam-local.
- METADATA_SERVER_DETECTION = none; CI = true.
- Node bin és helyi Java bin szerepel a PATH-ban; ezen a gépen JAVA_HOME = C:/Program Files/Android/Android Studio/jbr.
- Az emulators:exec adja át a localhost FIRESTORE_EMULATOR_HOST-ot; a tesztguard csak 127.0.0.1:8088 + demo projekt kombinációt enged.
- Nem használ production projektet, nem importál live adatot; nincs Firebase login/deploy parancs.

Eredmény: 108 PASS, 0 FAIL, 0 skipped (rules + deletion + runtime-integration), 90,6 másodperc. Build PASS; production/emulator target egyezés PASS; korábbi konfiguráció változatlansága PASS. git diff --check: PASS.

Lefedettség: owner/cross-user/anonymous recipe és shopping hozzáférés; backend-only billing/entitlement/lifecycle utak; ACTIVE/DELETING/DELETED; legacy content cleanup; modern cleanup barrier; runtime integráció és dispatcher. Nem full backend vagy Flutter suite, és nem live IAM/Play ellenőrzés.

## Live rules mentés – USER, deploy ELŐTT

1. Firebase Console → ellenőrizd a projektazonosítót: kuktam-67768.
2. Firestore Database → ellenőrizd a meglévő (default) adatbázist és eur3 régiót.
3. Rules → a jelenleg publikált ruleset teljes szövegét másold ki. Ne publikálj és ne módosíts semmit.
4. Mentsd helyben UTF-8 fájlba: firestore.rules.production-backup-YYYYMMDD-HHMM.txt. A névben a tényleges mentési idő legyen, időzóna: Europe/Budapest.
5. NE írd felül a repository firestore.rules fájlját. Jegyezd fel külön a projektet/adatbázist és az elérhető release-időt/verziót.
6. Nyisd vissza a mentést: teljes szöveg, minden match blokk és zárójel megvan-e?
7. Ezután külön read-only összehasonlítás: live backup ↔ hardened firestore.rules. Útvonalanként get/list/create/update/delete, user isolation, lifecycle gate, ingredients read, entitlement/backend-only és catchall viselkedés.
8. Ellenőrizzük, használ-e jelenlegi kiadott kliens olyan user-root/nested path írást, amit a candidate tilt; van-e már érzékeny billing/backend adat.
9. Ha a live állapot eltér a korábbi feltételezéstől, újraértékeljük a deltát és a rollbacket. Csak a konkrét összehasonlítás után kérhető külön deploy-jóváhagyás.

## Első rules-only deploy ellenőrzése és rollback döntés

Deploy után, külön jóváhagyott smoke: meglévő saját receptek és shopping olvasása, saját tesztrecept létrehozás/szerkesztés/törlés, shopping add/merge, export szerverolvasás, ingredients keresés. Más felhasználó adataihoz hozzáférés és kliens entitlement/billing írás továbbra is tiltott legyen. Production fióktörlést nem kell valós accounton tesztelni ehhez a smoke-hoz.

GO: a szükséges owner műveletek sikeresek, a tiltott műveletek elutasítottak; nincs új permission-denied regresszió a támogatott utakon.

STOP/korrekció: támogatott recipe/shopping/export műveletet a rules blokkol, váratlan jogosultságot nyit, vagy rossz projekten/adatbázison jelent meg a release. Előbb azonosítsuk, hogy rules hiba-e, ne hálózati/alkalmazáshibára rollbackeljünk.

Preferált javítás: célzott minimális rules-korrekció, helyi teszt, új jóváhagyott rules-only deploy.

A korábbi rules visszaállítása CSAK akkor mérlegelhető átmeneti incidenskezelésként, ha igazoltan még nincs live billing Functions ÉS nincs érzékeny entitlement/grant/binding/backend-only adat a visszanyitott utak alatt, a régi szabály hozzáférése ismert, és a user külön jóváhagyja a biztonsági kompromisszumot. A Functions hiánya önmagában nem bizonyítja az adatok hiányát.

Ha a mentés broad wildcardot tartalmaz és már érzékeny backend adat létezik: NINCS broad rollback. A védelmet meg kell tartani; célzott javítás és szükség esetén az érintett flow szüneteltetése kell.

Jóváhagyott visszaállítás eljárása: Console → kuktam-67768 → Firestore (default) → Rules; a hitelesített timestampes backup teljes tartalma beillesztve; diff ismét ellenőrizve; Publish kizárólag külön jóváhagyással; majd ugyanaz a smoke. A hardened helyi firestore.rules és a backup megmarad, nem írjuk egymásra. A rules rollback nem állít vissza adatokat vagy törölt Auth accountot.

## Fennmaradó blokkolók / kockázatok

- Live rules snapshot és pontos live→candidate delta még nincs.
- A production (default)/eur3 cél és jelenlegi adatok/kiadott kliensek kompatibilitása még nincs live ellenőrizve.
- Deployment nincs jóváhagyva és nem történt meg.
- A korábbi I1/I1.1 munkapéldány-változások megmaradtak; ez a feladat csak firebase.json-t és ezt a riportot változtatta.

FIRESTORE RULES SOURCE: firestore.rules
FIREBASE.JSON RULES TARGET: CONFIGURED
PRODUCTION PROJECT: kuktam-67768
EXPLICIT --project REQUIRED: YES
RULES TESTS: PASS
LIVE RULES SNAPSHOT: NOT YET CAPTURED
RULES DEPLOY: NOT PERFORMED
FUNCTIONS DEPLOY: NOT PERFORMED
FIREBASE CHANGES: NONE
GOOGLE CLOUD CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
COMMIT: NONE
PUSH: NONE
