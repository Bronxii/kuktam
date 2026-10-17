# I1 – Multi-image input / preprocessing / UI shell

2026-10-12

**VERDICT: READY FOR I2 – local implementation and automated validation.**

A telefonos Photo Picker/SAF smoke még felhasználói ellenőrzésre vár. Ez nem AI release és nem production aktiválás.

## Elkészült helyi flow

Receptek fejléc → „Recept képből” → 1–5 kép kiválasztása → automatikus, soros helyi előkészítés → sorszámos előnézet → fel/le rendezés, eltávolítás, hozzáadás → „Importálás – N kredit” → helyi kész állapot.

A képek egyetlen recepthez tartozó listát alkotnak. AI-feldolgozás, tartalomelemzés, editor-prefill és receptmentés I1-ben nincs. Az importgomb után a szöveg kifejezetten jelzi: AI nem indult, kredit nem fogyott, recept nem lett mentve.

## Architektúra és platformhatár

- `ImageImportPickerPort`: kiválasztás és adapter-owned ideiglenes bemenetek felszabadítása.
- `ImagePreparationPort`: helyi előkészítés és saját kimenetek takarítása.
- `ImageCreditPreviewPort`: cserélhető próbaegyenleg; `LocalImageCreditPreview` alapértéke 20, nem widgetenként beégetve.
- `ImageImportController`: sorrend, max 5, állapot, hiba, munkamenet, költség és dupla indítás elleni védelem. Tesztjei fake picker/preparer porttal futnak, Android nélkül.
- `SelectedImportImage`: stabil lokális ID, saját privát bemeneti fájl referencia vagy kontrollált hiba. Nincs content URI a közös rétegben.
- `PreparedImportImage`: ID, privát JPEG referencia, MIME, bytehossz, szélesség/magasság. Az immutable lista pozíciója az ordinal.
- `PreparedImageOperation`: egy UUID v4 csak explicit indításkor; teljes ordered images lista. Nincs UID, provider, prompt, AI-eredmény vagy settlement az image objektumban.
- Állapotok: idle / imagesSelected / preparingImages / readyToImport / processingPlaceholder / error. Nincs hálózati transport vagy base64.
- iOS-hoz picker/file adapter és platform composition szükséges később; a controller, policy, preprocessing és UI közös marad. iOS implementáció most nincs.

## Android picker

Külön `kuktam/image_import` MethodChannel és `ImageImportPicker`; MainActivity csak regisztrál, továbbítja az Activity resultot és felszabadít.

Android 13/API 33+ natív `MediaStore.ACTION_PICK_IMAGES`; több szabad hely esetén `EXTRA_PICK_IMAGES_MAX`, egy helynél single-select. Régebbi Androidon vagy hiányzó Photo Picker Activity esetén SAF `ACTION_OPEN_DOCUMENT`, image/jpeg + image/png szűrővel, többválasztással és local-only kéréssel.

Nem szükséges AndroidX vagy Flutter picker dependency upgrade. A platform API választása a jelenlegi SDK-val buildelve; [hivatalos MediaStore contract](https://developer.android.com/reference/android/provider/MediaStore). A maximum-extra csak 1-nél nagyobb értéknél használható.

A SAF nem garantál választási darabkorlátot: a visszatérő túlméretes választást a natív és a Dart réteg is teljes egészében elutasítja, érthető hibaüzenettel. Nincs csendes truncálás. A már kiválasztott képek megmaradnak.

Csak content URI olvasás ContentResolverrel; háttérszálon, bounded stream-copy saját cache fájlba. Nem kér storage/camera permissiont; manifest változás és image inbound intent filter nincs. Activity megszakadás kontrollált read hibát ad; a későn elkészült másolatok törlődnek.

## Sorrend és képszám

- 1–5 hard maximum; nulla képpel nincs indítás.
- Látható 1…N sorszám, akadálymentes fel/le és eltávolítás gombok.
- Fel/le a tényleges listát módosítja, az előkészített operation ugyanezt a sorrendet kapja.
- Nincs filename/date alapú rendezés.
- Ugyanaz a kép szándékosan újra kiválasztható: külön item, külön előnézet és kredit. Nincs rejtett tartalom-dedupe; a user eltávolíthatja. Automatikus duplikátum-felismerés I1-ben nincs.
- Az explicit helyi indítás után a lista immutable; új próbához visszalépés/új képernyő szükséges.

## Validálás és előfeldolgozás

Minden képen egymás után, külön Dart isolate végzi a CPU-munkát. A fő isolate fájlreferenciát és kis metadata eredményt kap; nincs öt bitmap vagy base64-lista a UI memóriájában.

1. Nem üres, olvasható, bounded privát bemenet.
2. JPEG/PNG magic; más formátum controlled reject. MIME önmagában nem bizonyíték.
3. Header/dimenzió/pixelkorlát ellenőrzése a teljes pixeldekódolás előtt.
4. PNG ancillary metadata eltávolítása a decoder előtt; APNG reject. Streamelt DEFLATE méretellenőrzés a hibás méretű tömörített tartalom ellen.
5. Tényleges decode; JPEG/PNG EXIF orientation alkalmazása.
6. Aránytartó resize, nincs upscale.
7. Friss RGB canvas, fehér alpha háttér; nem örököl EXIF/GPS/ICC/text/embedded thumbnail adatot.
8. JPEG encode, output-size ellenőrzés és privát temp fájl.

Egyetlen hibás item esetén a teljes job nem indítható. A sorszám mellett megjelenik a hiba; eltávolítás/pótlás után újra előkészíthető. A képek előnézete csak biztonságos előkészítés után jelenik meg. A „Képek előkészítése” gomb újrapróbálásra is használható.

### Központi `ImageImportPolicy` defaultok

| Tulajdonság | Default |
|---|---:|
| Eredeti fájl | legfeljebb 20 MiB/kép |
| Eredeti felbontás | legfeljebb 24 MP, oldalanként 12000 px |
| Kimenet hosszabb oldala | legfeljebb 2560 px |
| Kimenet felbontása | legfeljebb 6 MP |
| JPEG quality | 90 |
| Kimenet fájlmérete | legfeljebb 3 MiB/kép |
| Darabszám | legfeljebb 5, végleges termékszabály |

A képenkénti korlátokból legfeljebb 100 MiB/120 MP eredeti és 15 MiB/30 MP kimenet következik. A memóriahasználat soros; a decoder/resize/canvas átmenetileg több bufferrel dolgozik egyetlen képen. 24 MP telefonos peak-memory/latency mérés még szükséges. Túl nagy kimenetnél nincs csendes agresszív minőségcsökkentés.

**BENCHMARK VALIDATION REQUIRED** – a byte/pixel/quality értékek nem végleges minőségi termékdöntések.

## Temp lifecycle és privacy

- Natív bemenet: app-private cache `kuktam_image_input`, véletlen belső név.
- Dart kimenet: private temp `kuktam_image_prepared/item-*/image.jpg`.
- Remove/back/dispose/session-invalidálás saját fájlokat takarít best-effort; késői picker/preprocess eredmény külön felszabadul.
- Sikertelen előkészítés eltávolítja a félkész jobkönyvtárat. A felhasználó eredeti képét soha nem törli.
- Startup saját-cache sweep: legfeljebb 100 bejegyzés, 24 óránál régebbi orphanok; Dart sweep a feature megnyitásakor is. OS/process crash miatti takarítás nem azonnali törlési garancia, hanem következő indításkori best-effort recovery.
- Nincs upload, HTTP kliens, provider SDK, képlog, URI/path log vagy EXIF log. Az Android rendszerpicker egy külső providerből is adhat olvasható tartalmat; Kuktám nem küld képet külső félnek.
- Nem épült tartós képgaléria vagy képekből process-death utáni job recovery.

## Credit preview és munkamenet

N kép = N kredit; hozzáadás/törlés frissíti, rendezés nem változtatja. A próbaegyenleg jól láthatóan nem valódi egyenleg. Az elégtelen fake egyenleg tesztelt, blokkolja az indítást. Valódi balance mutation/reserve/finalize nincs.

A meglévő `RecipeFileReceiver` identity-only session check/generation/listener használata: authenticated current UID, logout/switch, A→B→A és AccountDeletionSignal invalidálja a jobot. Await utáni ellenőrzések miatt a késői eredmény nem örökíthető más accountnak. Nincs Pro/entitlement ellenőrzés vagy backend authhívás.

A Pro képernyő régi képes-import „hamarosan” benefit eleme eltűnt; a Pro purchase/scaling/Mit főzzek működése változatlan. A külön, eddig is unavailable enum-placeholder nem aktiválódott és az új flow nem használja.

## Érintett fájlok

Újak:
- lib/image_import/image_import_model.dart
- lib/image_import/image_import_controller.dart
- lib/image_import/local_image_preparation.dart
- lib/image_import/android_image_picker.dart
- lib/image_import/image_import_screen.dart
- android/app/src/main/kotlin/com/bronxii/kuktam/ImageImportPicker.kt
- android/app/src/main/java/com/bronxii/kuktam/ImageInputCopy.java
- android/app/src/test/java/com/bronxii/kuktam/ImageInputCopyTest.java
- test/image_import/image_import_controller_test.dart
- test/image_import/image_preparation_test.dart
- test/image_import/image_import_ui_test.dart
- I1_MULTI_IMAGE_INPUT_REPORT.md

Módosult: MainActivity.kt; lib/main.dart; lib/home/presentation/screens/main_screen.dart; lib/pro/pro_screen.dart; test/pro/pro_ui_test.dart; pubspec.yaml; pubspec.lock.

Dependency delta: kizárólag **image 4.9.1 transitive → direct main**, pontosan azonos lockolt verzió/hash; offline pub resolution. Nincs új csomag vagy egyéb upgrade. A korábbi I0 dokumentumokat ez a fázis nem módosította.

## Ellenőrzések

- Új I1 tesztek: **47 PASS** (controller/fake platform, image bytes/isolate/metadata, widget/bridge).
- Célzott I1 + sharing + export + auth + recipes + shopping + Pro: **989 PASS / 1 korábbi skipped**.
- Teljes Flutter: **1292 PASS / 1 korábbi skipped**.
- Flutter analyze --no-pub: **CLEAN**.
- Android debug APK: **PASS**, build/app/outputs/flutter-apk/app-debug.apk.
- Native Java contractok, assertions enabled: **6 tesztprogram PASS** (ImageInputCopy, TextShareInbox, RecipeFileInbox, RecipeDocumentRead, ExportCopy, ExportDocumentContract).
- Git diff --check: **PASS**.
- K2K direct/SAF/outbound, A1/A1.1, E1, editor, auth, shopping-Free és Pro gate regresszió: **PASS az automatizált suite-ban**.
- Backend suite nem futott; backend érintetlen.
- Buildben meglévő cloud_functions Kotlin Gradle Plugin figyelmeztetés; build sikeres, dependencyhez nem nyúltunk emiatt.
- Natív contractok és build nem helyettesítik a tényleges Android picker/device QA-t.

## Telefonos smoke checklist

1. Bejelentkezve Receptek → „Recept képből”; AI-kredit/helyi próba jelzés látható, nincs Pro popup.
2. Válassz egy JPEG/PNG screenshotot; helyes thumbnail és 1 kredit.
3. Új próbában válassz öt képet; sorszámok 1–5, költség 5 kredit. Hatodik ne kerüljön be csendben.
4. Fel/le gombokkal rendezd át; a sorszám követi az új sorrendet, a költség marad 5.
5. Törölj egyet: 5→4 kredit. Adj hozzá egyet: 4→5 kredit.
6. Elforgatott fotó: álló/fekvő és tükrözési irány helyes; átlátszó PNG háttere fehér.
7. Nagy/sérült/nem támogatott kép: érthető, sorszámos hiba; a teljes import blokkolt. Hibás kép eltávolítása után folytatható.
8. „Importálás – N kredit”: egy helyi operation; nincs AI vagy receptmentés, próbaegyenleg nem csökken. Dupla tap nem indít másodikat.
9. Picker cancel és visszalépés: nincs mentés. Újranyitva üres választás.
10. Ha biztonságosan tesztelhető, logout/account switch/fioktorles-jelzés előkészítés közben: régi job megszűnik, másik account nem kapja meg.
11. Próbáld Android 13+ Photo Pickerrel és régebbi Android SAF-fal; a SAF túl sok kiválasztására kontrollált elutasítás szükséges.
12. K2K direct open + Settings import, normál text Share, export Save/Share, AppBar overflow, editor és Free shopping add maradjon működőképes.

## I2 readiness / korlátok

A helyi ordered image foundation kész, az I2 structured draft/editor/warning contract ráépíthető. Nincs AI semantic felismerés, valódi credit balance, network transport, provider vagy I2 draftmódosítás. Kamera és image Share receiver nincs. Picker/low-memory/öt nagy kép telefonos QA és benchmark még szükséges; az iOS platformadapter későbbi munka. Nincs ismert P0/P1 a helyi tesztekkel vizsgált útvonalakon.

MULTI-IMAGE PICKER: IMPLEMENTED
MAX IMAGE COUNT: 5
IMAGE REORDER: IMPLEMENTED
LOCAL PREPROCESSING: IMPLEMENTED
CREDIT COST PREVIEW: IMPLEMENTED
REAL CREDIT BACKEND: NOT IMPLEMENTED
AI EXTRACTION: NOT IMPLEMENTED
AI API CALLS: NONE
AI COST: ZERO
PERSISTENT IMAGE STORAGE: NONE
DIRECT CAMERA: NOT IMPLEMENTED
IOS CORE REWRITE REQUIRED LATER: NO
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PLAY CHANGES: NONE
PRODUCTION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
