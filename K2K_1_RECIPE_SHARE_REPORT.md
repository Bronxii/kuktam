# K2K-1 – Strukturált, egyreceptes megosztás

## Verdict

**READY FOR IMAGE AI IMPORT – helyi implementáció és automatizált tesztek alapján.**
Nincs ismert P0/P1. Valós Android provider-/kétkészülékes smoke még hátravan;
a custom MIME megőrzését nem lehet unit tesztből minden célalkalmazásra garantálni.
Image AI fejlesztés nem indult el. Commit/push nem történt.

## 1. Formátum és mezők

- Kiterjesztés: `.kuktamrecipe`.
- MIME: `application/vnd.kuktam.recipe+json`.
- UTF-8, BOM nélkül, pretty JSON, záró newline.
- Envelope: `format: kuktam.recipe`, `version: 1`, `recipe`.
- Recipe allowlist: name, ingredients[{name, quantity, unit}], spices[{name}], preparation.
- A közös E1 `ExportRecipe.toContentJson()` adja a tartalmi mappinget.
  Az E1 `toJson(textFile)` ezt egészíti ki; az export JSON sémája nem változott.
- Nincs doc ID, UID, email, időbélyeg, sender/device/account/cloud path,
  entitlement/billing/grant/purchaseToken/HMAC vagy más backend metadata.
- A saját receptszövegben önként szereplő személyes szöveg nem kerül cenzúrázásra.

## 2. Kimenő megosztás

- Recept részletei → További megosztás menü → **Megosztás Kuktámmal**.
- A meglévő Megosztás ikon továbbra is emberi olvasású szöveget küld.
- Strict validáció → app-private temp könyvtár → egy JSON fájl → SharePlus/XFile/custom MIME.
- Safe filename az E1 közös helperéből: tiltott path/control/bidi karakterek cseréje,
  Unicode megőrzése, 120 UTF-8 byte-os névrész. Nincs külső storage permission.
- Dupla aktiválás ellen busy guard. A megosztás nem ír receptet, nem kér Pro jogosultságot.
- A saját temp artifact a share hívás lezárásakor törlődik. Androidon share_plus külön
  cache-másolatot ad a fogadónak; ahhoz nem nyúlunk. Process kill után cache maradvány lehet.

## 3. Bejövő Android fájl

- Manifest: csak custom MIME; ACTION_VIEW esetén content scheme, ACTION_SEND egy fájl.
- Nincs */*, application/json, application/zip vagy octet-stream regisztráció.
- SEND_MULTIPLE, kép, ZIP, file:// és HTTP URI nem támogatott.
- MainActivity külön `kuktam/recipe_file` typed csatornát használ.
- ACTION_VIEW: intent data; ACTION_SEND: EXTRA_STREAM. ContentResolver.openInputStream,
  nincs URI→filesystem path feloldás, broad/persistent permission vagy hálózati letöltés.
- Háttérszálas olvasás, **262 144 byte / 256 KiB** maximum; túlméretet nem csonkítjuk.
  A normál A1 szöveg limitje 20 000 karakter; itt a JSON többletéhez bőséges külön korlát kell.
- Külön begin/completion esemény az olvasás közbeni accountváltás fencingjéhez.
  A natív váró és a Flutter pending sor is legfeljebb 10 tételes; telítettség látható jelzés.
- Cold: onCreate, egyszeri intent consumption. Warm: onNewIntent ugyanazt a fogadót hívja.
- Recreation: consumed intent nem indul újra; process-local inbox és aktuális Activity weak
  referencia segíti a folyamatban levő olvasás eredményének kézbesítését.
- Process death/tartós inbox recovery nem része V1-nek; ilyen esetben újra meg kell nyitni.

## 4. Strict decode és policy

- Byte limit → strict UTF-8 → korlátos nesting → JSON → exact format és int version.
- Csak V1 támogatott; jövőbeli verzió külön barátságos hiba, nincs best-effort feldolgozás.
- Pontos field set minden objektumszinten; hiányzó/extra mező vagy hibás típus reject.
- Kötelező nem üres name/ingredient name/spice name; preparation lehet üres.
- Quantity finite, pozitív szám; canonical MeasurementUnits.values tagja szükséges.
  Nincs dkg/dl/kk konverzió vagy unitbővítés. Legacy nem canonical adat kontrollált hibát ad.
- Hibás Unicode escape és overflow szám reject. JSON nesting maximum 8; nincs deep-object
  recursion a tényleges decode előtt. A 256 KiB limit mindkét oldalon érvényes.
- Üres legacy spice: **controlled validation error**, filtering helyett. Nem veszítünk el
  csendben adatot és nem írunk át tárolt receptet. A felhasználó előbb javíthatja a receptet.
- Hibák csak ismert emberi kategóriák: rossz formátum/verzió, sérült, túl nagy, nem olvasható,
  megtelt váró, megváltozott fiók. Nincs exception/payload/URI/path dump.

## 5. Editor és mentés

- JSON → validált Recipe (id nélkül) → AddRecipeScreen.initialRecipe.
- Nem megy át RecipeTextParseren, browser normalizeren vagy szöveges preview-n.
- Ez **create** mód: widget.recipe null, nincs sender ID, updateRecipe nem fut.
- Név, hozzávalók, mennyiségek, unitok, fűszerek és preparation szerkeszthetők.
- Structured preparation külső/belső sortöréseit is megőrzi mentéskor;
  a normál kézi/text-import editor korábbi trim viselkedése változatlan.
- Nincs automatikus mentés. Cancel nem ír adatot; az explicit Mentés normál repository create.
- Névütközés: meglévő recipeNameExists → „Már létezik ilyen nevű recept!”;
  nincs overwrite, merge vagy automatikus átnevezés. Átnevezés után menthető.
- A meglévő uniqueness ellenőrzés forrása változatlan; ez nem új backend uniqueness constraint.

## 6. Login, navigation, session

- Login előtt az input csak memóriában vár; a login képernyő jelzi a folytatható receptimportot.
- Bejelentkezés után MainScreen nyitja az editort, csak current route/resumed UI mellett.
- Más modal/editor alatt a további recept vár, nem írja felül a megnyitott draftot.
- Event UUID dedupe, egyszeri take; azonos tartalmú két külön megnyitás két esemény marad.
- Logout/user switch/A→B→A invalidálja a régi account pending és olvasás alatti eseményeit.
- Nyitott editor session-generation ellenőrzése a névellenőrzés előtt és után;
  közvetlen aktuális SDK UID ellenőrzés a késve érkező auth stream előtt is fence-el.
- Helyi account deletion jelzés szintén invalidál. Új user nem mentheti a régi editor draftját.
- Már megindított repository írást nem lehet visszavonni; a UID-s kollekció a hívás kezdetén
  rögzül. Külső appnak átadott fájlt utólag nem lehet visszahívni.

## 7. Provider kompatibilitás

| Provider | Állapot |
|---|---|
| Android Files | Telefonos smoke még nem történt |
| Drive / email | Telefonos smoke még nem történt |
| Messaging file target | Telefonos smoke még nem történt |

Custom MIME elvesztése esetén a Kuktám nem feltétlenül jelenik meg a megnyitók között.
Csak a kiterjesztés átnevezése nem garantál MIME-felismerést. Nincs automatikus
széles intent-filter fallback; a valós smoke után külön döntés szükséges.
A megfelelő MIME önmagában sosem elég: a tartalmat a decoder mindig validálja.

## 8. Fájlok és függőségek

Új:
- lib/sharing/recipe_share_codec.dart
- lib/sharing/recipe_file_share.dart
- lib/sharing/recipe_file_receiver.dart
- android/app/src/main/java/com/bronxii/kuktam/RecipeFileInbox.java
- android/app/src/test/java/com/bronxii/kuktam/RecipeFileInboxTest.java
- test/sharing/recipe_share_codec_test.dart
- test/sharing/recipe_file_receiver_test.dart
- test/sharing/recipe_file_share_test.dart
- K2K_1_RECIPE_SHARE_REPORT.md

Módosított:
- lib/export/domain/recipe_export.dart, recipe_export_formatter.dart (minimális helper reuse)
- lib/recipes/presentation/screens/recipe_details_screen.dart, add_recipe_screen.dart
- lib/home/presentation/screens/main_screen.dart, lib/main.dart
- lib/features/auth/presentation/screens/login_screen.dart, widgets/auth_gate.dart
- android/app/src/main/AndroidManifest.xml
- android/app/src/main/kotlin/com/bronxii/kuktam/MainActivity.kt

**Új dependency/upgrade: nincs.** Backend, rules, Firebase/GCP/Play és monetizáció változatlan.

## 9. Teszteredmények

- Új K2K Flutter tesztek: **42 PASS**, benne formátum/allowlist/roundtrip/filename,
  malformed/version/size/Unicode, FIFO/dedupe, cold/warm bridge, login pending,
  editor prefill/create/cancel/rename, stale account/deletion, outbound tényleges file+MIME.
- Célzott share/export/recipe/auth regresszió: **698 PASS / 1 skipped**,
  utána további 3 boundary teszt a teljes körben.
- Teljes Flutter suite végső kör: **1249 PASS / 1 korábbi skipped**.
- Flutter analyze --no-pub: **CLEAN**.
- Android debug APK: **PASS** (build/app/outputs/flutter-apk/app-debug.apk).
- Native JVM: RecipeFileInbox **PASS** (VIEW/SEND/MIME/scheme, bounded read, read error,
  size boundary, cold/warm/event consumption/queue). Android ContentResolver instrumentált
  teszt nem futott; a natív reader InputStream szerződése tesztelt.
- A1 TextShareInbox native **PASS**; A1/A1.1 Flutter regresszió **PASS**.
- E1 export 43 teszt és ExportCopy/ExportDocumentContract native **PASS**;
  ZIP/JSON/TXT/Save/Share schema és bridge változatlan szerződéssel.
- git diff --check: **PASS**. Nincs raw payload log, text-parser vagy Pro-gate az új fájlútban.
- Meglévő cloud_functions KGP jövőbeli kompatibilitási warning megmaradt, buildet nem blokkol.

## 10. Manuális smoke checklist

1. Saját recept részletei → További megosztás → Megosztás Kuktámmal.
   Share sheet, .kuktamrecipe fájlnév; küldés egy file-capable célba.
2. Android Files: a fájl megnyitása → Kuktám. Editor előtöltött, nincs automatikus mentés.
   Módosíts nevet/hozzávalót → Mentés → új recept; az eredeti változatlan.
3. Cold: Kuktám bezárva → fájl megnyitás → editor egyszer. Warm: futó app → új fájl → egyszer.
4. Editor közben második fájl → első nem íródik felül, cancel/save után következő jelenik meg.
5. Kijelentkezve fájl megnyitása → login folytatási jelzés → login → editor a helyes tartalommal.
6. Ugyanaz a már létező név → Mentés blokkolt → átnevezés után új recept menthető.
7. Cancel → semmi nem mentődik; app tovább használható; nincs spontán újranyitás.
8. Biztonságos tesztfiókkal nyitott import közbeni accountváltás → régi draft nem menthető.
9. Hibás JSON/future version/túlméret custom MIME-mal → érthető elutasítás, nincs crash.
10. Chrome/Jegyzet text Share → Kuktám → továbbra is szöveges import és browser normalizer.
11. E1 export → ZIP → Mentés és Megosztás smoke, ékezetek és darabszám rendben.
12. Külön Android Files, Drive vagy email, és egy messaging target: rögzítsd
    works / does not work / MIME transformed eredménnyel. Ne szélesíts automatikusan filtert.

## 11. Korlátok / readiness

Android V1, egy recept, explicit save, memóriás pending. Nincs tartós inbox, process-death
recovery, iOS, bulk restore, ZIP/recipes.json importer vagy cloud megosztási objektum.
A natív olvasás korlátos méretű háttérmunka; hibás/lassú külső provider késleltetheti.
A telefonos MIME/provider smoke a következő ellenőrzés. Image AI csak külön következő feladat.

KUKTÁM-TO-KUKTÁM V1: IMPLEMENTED
SINGLE RECIPE FORMAT: IMPLEMENTED
STRUCTURED RECIPE IMPORT: IMPLEMENTED
AUTOMATIC SAVE: NONE
BULK RESTORE: NOT IMPLEMENTED
CLOUD SHARE BACKEND: NONE
APP LINKS: NOT IMPLEMENTED
IMAGE AI IMPORT: NOT IMPLEMENTED
FAMILY SHARING: NOT IMPLEMENTED
BACKEND CHANGES: NONE
FIREBASE INFRA CHANGES: NONE
PRODUCTION CHANGES: NONE
MONETIZATION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
