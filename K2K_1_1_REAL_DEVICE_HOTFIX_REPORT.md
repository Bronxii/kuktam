# K2K-1.1 – Real-device hotfix

## Verdict

LOCAL HOTFIX READY; PHYSICAL PROVIDER RETEST REQUIRED.
Az AppBar javítva, a fájltársítás szűk fallbackkel bővítve, explicit fájlválasztó elkészült. A Messenger chooser tényleges javulása telefonon még NEM igazolt. Nincs ismert helyi teszthiba.

## Root cause és Android matching

A korábbi VIEW filter kizárólag `application/vnd.kuktam.recipe+json` + `content` kombinációt fogadott. Más MIME esetén nem volt candidate. A telefonos esemény pontos MIME/URI-ja nem áll rendelkezésre: az eltérő MIME valószínű ok, nem rögzített mérési tény.

A manifest URI pathot vizsgál, nem a provider külön DISPLAY_NAME mezőjét. Path szűréshez scheme és host szükséges; egy filter data elemei összeadódnak. Ezért a fallback külön filter. Android 12/API 31-től `pathSuffix`; korábbi rendszereken szűk `pathPattern` változatok. A simple glob nem backtracking regex, ezért külön minták kezelik a több pontot tartalmazó útvonalat. [Hivatalos Android data matching dokumentáció](https://developer.android.com/guide/topics/manifest/data-element).

### Manifest delta

- Custom MIME VIEW/content és SEND változatlan; launcher és text/plain SEND változatlan.
- Külön VIEW/content/host=* fallback: `application/octet-stream` vagy `application/json`, kizárólag `.kuktamrecipe` végű URI path.
- API 31+: suffix; korábbi Android: 1–9 pontot tartalmazó pathra felsorolt szűk minták. Több pont esetén a picker használható.
- Nincs általános JSON, ZIP, binary vagy */* megnyitóregisztráció.
- Generic MIME SEND fallback nincs: az EXTRA_STREAM URI nem alkalmas manifest path szerinti matchingre.
- Opaque URI, pl. content://provider/123, csak DISPLAY_NAME-ban szereplő kiterjesztéssel: generikus MIME esetén továbbra sem candidate. Ezt biztonságosan nem oldja meg egy extension-filter.

## Biztos explicit fallback

Beállítások → **Kuktám recept importálása** → Android ACTION_OPEN_DOCUMENT.
CATEGORY_OPENABLE, egy fájl; MIME-k: custom, octet-stream, JSON. Az intent application/* típusa csak a felhasználó által indított picker kérésében szerepel, nem regisztrált handler. A provider fájlnevének `.kuktamrecipe` végűnek kell lennie.

ContentResolver olvasás, maximum 256 KiB, nincs filesystem-path feloldás, broad storage permission vagy persistent grant. Megszakítás nem hiba; busy, hiányzó URI, olvasási hiba és méret kontrollált. A SAF explicit dokumentumkiválasztást biztosít. [Android SAF dokumentáció](https://developer.android.com/training/data-storage/shared/documents-files).

A byte payload ugyanabba a RecipeShareCodec-ba kerül: strict UTF-8/JSON, exact format=kuktam.recipe, version=1, teljes mező/domain validáció. Ezután meglévő pending queue → újrecept-editor → explicit Mentés. Nincs text-parser roundtrip, automatikus mentés vagy restore. Picker await után session-generation ellenőrzés; accountváltáskor abort.

## AppBar

Egyetlen overflow action (`Recept műveletek`), sorrend:
1. Megosztás Kuktámmal
2. Megosztás szövegként
3. Szerkesztés
4. Törlés

A meglévő megosztás, editor és törlésmegerősítés marad. A cím több helyet kap. Share busy állapotban a menü tiltott.

## Biztonság

A MIME/kiterjesztés csak routing, soha nem hitelesítés. Átnevezett hibás JSON sem importálható. Nincs payload/URI-log, linknyitás, webfetch, dependency, backend vagy monetizációs változás. A text-share és E1 schema változatlan a hotfixben.

## Hotfix fájlok

- android/app/src/main/AndroidManifest.xml
- android/app/src/main/kotlin/com/bronxii/kuktam/MainActivity.kt
- android/app/src/main/kotlin/com/bronxii/kuktam/RecipeDocumentPicker.kt (új)
- android/app/src/main/java/com/bronxii/kuktam/RecipeFileInbox.java
- android/app/src/test/java/com/bronxii/kuktam/RecipeFileInboxTest.java
- lib/sharing/recipe_file_receiver.dart
- lib/settings/settings_screen.dart
- lib/recipes/presentation/screens/recipe_details_screen.dart
- test/sharing/recipe_file_receiver_test.dart
- test/recipes/recipe_core_test.dart
- test/pro/feature_gate_test.dart
- test/auth/auth_qa_test.dart
- K2K_1_1_REAL_DEVICE_HOTFIX_REPORT.md

A munkakezdéskor már voltak K2K-1 módosítások/untracked fájlok. Ezek megmaradtak; a teljes git diff ezért a hotfixnél nagyobb.

## Ellenőrzések

- Célzott sharing/export/recipe/feature/auth regresszió: **766 PASS / 1 skipped**.
- Kiegészített receiver/manifest/picker/editor kör: **16 PASS**.
- Teljes Flutter: **1253 PASS / 1 korábbi skipped**.
- Analyzer: **CLEAN**.
- Android debug APK: **PASS** (`build/app/outputs/flutter-apk/app-debug.apk`).
- Natív Java harness: RecipeFileInbox, TextShareInbox, ExportCopy, ExportDocumentContract: **4 PASS**.
- Diff-check: **PASS**.
- K2K malformed/wrong format/version, login pending, cold/warm event, session fencing, A1/A1.1 és E1 regresszió: PASS a fenti suite-okban.
- Új ellenőrzés: suffixes JSON/octet VIEW elfogadás, random JSON/ZIP/binary/opaque URI elutasítás, SEND regresszió, bounded read; manifest szűkítés; picker cancel/error/busy/session; Settings→editor, nincs automatikus mentés; egy AppBar action + négy menüpont; edit/delete megerősítés.
- A native helper és manifest-struktúra teszt nem fizikai PackageManager/chooser smoke. A SAF provider UI és tényleges Messenger MIME viselkedése manuális retestet igényel.
- Meglévő cloud_functions/Kotlin plugin buildfigyelmeztetés maradt; dependency upgrade nem történt.

## Telefonos smoke checklist

1. Telepítsd az új APK-t. Recept részletei: egy hárompontos menü, négy megfelelő pont; szerkesztés és törlés/Mégse működik.
2. Megosztás Kuktámmal → Messenger → fogadó oldalon fájl tap → keresd a Kuktámot a chooserben.
3. Kuktám kiválasztása → előtöltött editor egyszer; átnevezés/mentés csak kifejezetten; cancel nem ment.
4. Ugyanez Android Filesból, egyszer bezárt appal, egyszer háttérben futó appal.
5. Drive/email, ha elérhető: eredményt külön jegyezd fel (chooser látható / nem látható). A MIME átalakulását mérés nélkül ne tekintsd bizonyítottnak.
6. Ha providerből nincs Kuktám: mentsd a fájlt, Beállítások → Kuktám recept importálása → válaszd ki. Editor megnyílik; picker cancel után app használható.
7. Random .json/.zip/.bin megnyitásánál Kuktám ne jelenjen meg általános handlerként. Hibás JSON .kuktamrecipe-re átnevezve érthető elutasítás legyen.
8. Normál Chrome/Jegyzet text Share → Kuktám: továbbra is szövegimport és browser normalizálás.
9. E1 export → ZIP Mentés/Megosztás továbbra is működjön.

## Korlát / lezárás

A szűk association javítása implementálva; univerzális Messenger/Drive/Files chooser-kompatibilitást nem ígér. Opaque URI + generic MIME esetén az explicit picker a támogatott út. Physical smoke státusz: NOT PERFORMED. A következő lépés a fenti telefonos ellenőrzés; nincs új feature-fázis.

K2K APP BAR UX: FIXED
K2K FILE ASSOCIATION: FIXED
GENERIC JSON HANDLER: NONE
GENERIC */* HANDLER: NONE
A1/A1.1 REGRESSION: PASS
E1 REGRESSION: PASS
BACKEND CHANGES: NONE
PRODUCTION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
