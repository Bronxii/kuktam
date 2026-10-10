# E1 – Recipe Export V1

## Verdict

**READY FOR KUKTÁM-TO-KUKTÁM – helyi implementáció és automatizált ellenőrzések alapján.**
Nincs ismert P0/P1. Valós telefonos SAF/provider és célalkalmazás smoke teszt még szükséges;
az alábbi checklist ezt külön kezeli. Kuktám→Kuktám és restore nem indult el.
Az elfogadott E0 döntései maradtak érvényben.

## Implementált tartalom és formátum

- Free export: minden saját, szerveren elmentett recept egy ZIP-ben.
- `Kuktam-receptek-YYYYMMDD-HHmmssZ.zip` → `recipes.json`, `export_info.txt`,
  `receptek/000001-Név.txt` stb. Üres receptkönyv is érvényes export.
- Explicit immutable export-DTO: name, ingredients[name/quantity/unit], spices[name], preparation.
- JSON: format=kuktam.recipes, exportVersion=1, UTC exportedAt, runtime appVersion/appBuild,
  recipes; receptenként textFile kapcsolat. UTF-8, BOM nélkül, 2 space, LF, záró newline.
- JSON a strukturált, veszteségmentes forrás. Sorrendek és preparation sortörések megmaradnak.
  NaN/Infinity az egész exportot kontrollált hibával leállítja.
- TXT: név, Hozzávalók, opcionális Fűszerek/Elkészítés, Kuktám footer.
  Mennyiség: meglévő formattedQuantity; nincs konverzió, új kerekítés vagy parser round-trip.
- export_info: UTC idő, verzió, darabszám, csak-receptek jelleg és a restore hiánya.

## Szerveres adatforrás és session

- Külön export-only port; a RecipeRepository CRUD és normál olvasása változatlan.
- Authból rögzített UID → waitForPendingWrites → teljes recipes kollekció Source.server.
  Nincs filter, orderBy, limit vagy cache fallback. Mindkét hálózati szakasz timeoutja 30 mp.
- Cache/pendingWrites metadata esetén elutasítás. Strict Recipe mapping + DTO validáció
  minden dokumentumra; bármely hibánál nincs ZIP és nincs kihagyott recept.
- Magyar névrendezés a meglévő compareHungarianRecipeNames alapján;
  azonos névnél belső doc ID tie-break, az azonosító nem kerül az exportba.
- Auth streamből latchelt érvénytelenítés: logout, account switch, A→B→A is abort.
  A helyi törlés kezdetén külön jelzés fence-eli az exportot; a deletion flow sorrendje nem változott.
- Fontos awaitok után és Save/Share előtt új ellenőrzés. Elavult build eredménye törlődik.
- Egyidejű buildet controller guard és folyamaton belüli build lock akadályozza;
  route dupla tap ellen is védett. Bezárás után a futó build nem adható át.

## Fájlnevek, ZIP és erőforrások

- Minimum 6 jegyű indexprefix; Unicode/magyar ékezet megmarad.
- Tiltott path/control/bidi karakter → `_`; whitespace összevonás; záró pont/szóköz törlés;
  üres név → Recept. Névrész maximum 120 UTF-8 byte, code-point határon.
- Fix receptek/ relatív könyvtár, nincs felhasználói könyvtár vagy `..` path-komponens.
- archive ZipFileEncoder isolate-ban, közvetlenül app-private cache/export fájlba ír.
  A UI isolate nem végzi a ZIP/JSON/TXT kódolást. A szerver-mapping/rendezés lineáris/n log n munka.
- Nincs mesterséges receptdarab-limit. Snapshot + JSON reprezentáció memóriában van;
  nagyon nagy receptkönyvnél RAM/tárhely gyakorlati korlát. Nem streaming Firestore backup.
- Hibás build saját alkönyvtára takarítódik. Normál képernyőbezárás saját kész artifactot töröl;
  folyamatban levő átadásnál megvárja annak végét. Cleanup best effort, tartalomlog nélkül.
- share_plus Androidon saját cache-másolatot hoz létre. Ezt nem töröljük a chooser visszatérésekor;
  a plugin kezeli saját cache-ének életciklusát. Process kill után app-cache maradvány lehetséges.

## Android Mentés és Megosztás

- Beállítások: Saját adatok exportálása / Összes recept exportálása.
  Készítés → darabszám → külön Mentés és Megosztás. Busy alatt nincs második művelet.
- Mentés: külön kuktam/export_document channel, ACTION_CREATE_DOCUMENT,
  CATEGORY_OPENABLE, application/zip, EXTRA_TITLE. Nincs storage permission/Downloads path.
- A kiválasztott content URI-ra háttérszálon, 64 KiB bufferrel másol;
  siker csak lezárt stream után. Cancel nem hiba; missing URI/write failure/busy kontrollált.
- A chooser eredménye még nem mentési siker. Session váltáskor cancel jel megy a natív oldalra;
  félkész dokumentum törlése best effort. Hibás provider visszautasíthatja a törlést.
- Activity/engine megszakításkor a pending művelet lezárul; nem állítunk helyre félig mentett
  exportot process death után. Új export indítható. Külön saját fájlkezelő nincs.
- Megosztás: meglévő SharePlus + XFile ZIP MIME-mal. Chooser visszatérés nem igazolt mentés;
  a UI a fogadó alkalmazásban való ellenőrzésre kér. Már átadott külső fájl nem vonható vissza.
- Inbound kuktam/text_share, manifest, launchMode és normalizer változatlan.

## Privacy / Free policy

- JSON/TXT allowlistből készül, nem raw Firestore map-ből. Teszt szerint nincs exportált doc ID,
  UID, email, timestamp, entitlement, billing, grant, purchaseToken, HMAC vagy lifecycle metadata.
- A felhasználó saját receptszövegében szereplő személyes adat továbbra is recepttartalom.
- Nincs payload/JSON/ZIP/auth adat naplózás; nincs entitlement/billing/Pro ellenőrzés.
- Offline hiba szerveres teljességi feltétel, nem monetizációs korlátozás.

## Függőségek

- archive **4.0.9**, path_provider **2.1.6**: meglévő lockolt tranzitívből direct dependency.
- share_plus és package_info_plus meglévő; XFile a share_plus exportjából.
- Lockban csak a két dependency besorolása változott; nincs verzióupgrade/új plugin.

## Érintett fájlok

Új:
- lib/export/domain/recipe_export.dart, recipe_export_formatter.dart, recipe_export_encoder.dart
- lib/export/data/recipe_export_source.dart, export_file_gateway.dart
- lib/export/presentation/recipe_export_controller.dart, recipe_export_screen.dart
- lib/core/account_deletion_signal.dart
- android/app/src/main/java/com/bronxii/kuktam/ExportCopy.java, ExportDocumentContract.java
- android/app/src/main/kotlin/com/bronxii/kuktam/ExportDocumentWriter.kt
- android/app/src/test/java/com/bronxii/kuktam/ExportCopyTest.java, ExportDocumentContractTest.java
- test/export/export_test.dart, export_bridge_test.dart, export_firestore_contract_test.dart,
  export_ui_recovery_test.dart
- E1_EXPORT_REPORT.md

Módosított:
- lib/settings/settings_screen.dart
- lib/features/auth/data/repositories/account_deletion_repository.dart (csak lokális export fence jelzés)
- android/app/src/main/kotlin/com/bronxii/kuktam/MainActivity.kt (külön outbound channel/result)
- pubspec.yaml, pubspec.lock
- test/auth/account_deletion_test.dart (az új sor miatt szükséges görgetés a gombhoz)

Az E0_EXPORT_SPEC.md már a munka elején untracked volt; nem módosult.

## Ellenőrzések

- Export: **43 PASS** (DTO/ZIP/TXT/filenames, cache/hiba/session atomicity,
  tényleges Source.server port szerződés, controller, Settings UI, retry, SAF és share_plus bridge).
- Célzott export/auth/share/import kör: **161 PASS**; utána bővített export külön 43 PASS.
- Teljes Flutter suite, végső kör: **1207 PASS / 1 korábbi skipped**.
- flutter analyze --no-pub: **CLEAN**.
- Android debug APK: **PASS**; build/app/outputs/flutter-apk/app-debug.apk.
- Native JVM contract: **ExportCopy PASS**, **ExportDocumentContract PASS**, **TextShareInbox PASS**.
  SAF intent/policy, cancel/missing URI/busy, teljes stream-copy és write exception tesztelve.
  Valódi Android DocumentsProvider instrumentált/telefonos teszt nem futott.
- A1/A1.1 Flutter és native regresszió: **PASS**, nincs inbound source változás.
- git diff --check: **PASS**. Backend suite nem futott: nincs backend source változás.
- Meglévő cloud_functions KGP jövőbeli kompatibilitási warning a buildben; build sikeres,
  ehhez nem történt scope-on kívüli dependency/toolchain upgrade.

## Manuális smoke checklist

1. Több recepttel: Beállítások → Saját adatok exportálása → várd meg a kész állapotot.
2. Mentés → Android dokumentumválasztó → válassz helyet → mentés befejeződött jelzés.
3. ZIP PC-n/telefonon: recipes.json + export_info.txt + receptek könyvtár; darabszám helyes.
4. TXT-k olvashatók, ékezetek/sortörések/mennyiségek rendben; JSON textFile utak léteznek.
5. Új export → Megosztás → alkalmas fogadó app; ott ellenőrizd a ZIP megérkezését.
6. Mentés megszakítása → nincs sikerjelzés, új Mentés lehetséges.
7. Internet ki → export → érthető hálózati hiba; nem jön létre hiányos ZIP; online retry működik.
8. Biztonságos tesztfiókkal export közbeni logout/account switch → abort, nincs átadás.
9. Üres receptkönyv → érvényes ZIP, recipes: [].
10. Inbound szöveg Share → Kuktám cold/warm smoke: a megszokott receptimport egyszer nyílik.

## Korlátok / következő lépés

- Egy szerver-snapshotot mentünk; el nem mentett editor draft és más készülék későbbi változása
  nem része. Nincs globális szerkesztési/deletion lock vagy távoli session visszavonási garancia.
- Külső dokumentumszolgáltatók és share targetek viselkedése telefonos smoke-ot igényel.
- Nagyon nagy adatállomány és process kill után cache maradvány ismert V1 korlát.
- E1 lokálisan lezárható; a következő feature külön kérés. Restore nincs implementálva.

RECIPE EXPORT V1: IMPLEMENTED
EXPORT JSON: IMPLEMENTED
EXPORT TXT: IMPLEMENTED
EXPORT ZIP: IMPLEMENTED
ANDROID SAVE: IMPLEMENTED
ANDROID SHARE FILE: IMPLEMENTED
RESTORE: NOT IMPLEMENTED
SHOPPING EXPORT: NOT IMPLEMENTED
KUKTÁM-TO-KUKTÁM: NOT IMPLEMENTED
IMAGE AI IMPORT: NOT IMPLEMENTED
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PRODUCTION CHANGES: NONE
MONETIZATION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
