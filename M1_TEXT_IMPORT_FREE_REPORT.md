# M1 – Text imports become Free

Verdict: **READY FOR ANDROID SHARE**

## Változás

A recept és bevásárlólista szöveges importja teljesen Free. A régi belépési
FeatureGate.request, dialog FeatureBoundary és végrehajtási FeatureGate.execute
ellenőrzések kikerültek. A receptimport editorba átadásánál sincs entitlement-
alapú ellenőrzés. A főképernyő importikonjai többé nem viselnek Pro-jelölést.

A két import kikerült a ProFeature enumból és a ProScreen előnylistájából.
Nem maradt név szerint Pro, de valójában Free funkció. A központi hozzáférési
szolgáltatás algoritmusa változatlan: csak a megmaradó ProFeature-ekre vonatkozik.

Pro maradt: receptátszámítás, átszámított recept → shopping, Mit főzzek?.
A képes import továbbra is unavailable; megvalósítása nem változott.
Parser, egységkonverzió, preview szerkesztő, mentési mapping és repository nem változott.

## Entitlement / offline

A textimport dialogok nem importálják a feature gate réteget és nem kérnek online
proofot. Free, Pro online/offline grace, checking, unknown és unavailable állapotban
is feldolgozható az input. Lejárt 30 napos grace sem blokkolja a receptimportot.
A mentés a meglévő repository/sync működését használja; ez nem jelent új offline
adatperzisztencia-garanciát. A normál autentikáció és adat-hozzáférés változatlan.

## Érintett fájlok (M1)

- lib/entitlements/domain/models/pro_feature.dart
- lib/pro/feature_gate.dart
- lib/pro/pro_screen.dart
- lib/home/presentation/screens/main_screen.dart
- lib/recipes/presentation/widgets/recipe_import_dialog.dart
- lib/shopping/presentation/widgets/shopping_import_dialog.dart
- test/entitlements/domain/feature_access_service_test.dart
- test/pro/feature_gate_test.dart
- test/pro/n8_closure_test.dart
- test/pro/pro_ui_test.dart
- test/recipes/recipe_import_dialog_test.dart
- test/shopping/shopping_import_dialog_test.dart
- M1_TEXT_IMPORT_FREE_REPORT.md

A munkafában már meglévő UI-1 fájlváltozásokhoz ez a fázis nem nyúlt.

## Ellenőrzések

- Célzott Flutter: **202 PASS** (test/pro, entitlement domain, két importdialog suite).
- Teljes `flutter test --no-pub`: **1109 PASS / 1 skipped**.
- `flutter analyze --no-pub`: **CLEAN**, no issues found.
- `git diff --check`: **PASS**.
- Backend teszt nem futott: backend változás nincs.

Explicit lefedés: Free főképernyő-importbelépések; minden kliens entitlement státusz
mellett receptfeldolgozás és shopping preview/import; Pro-regresszió; import
végrehajtása jogosultságvesztés után; valódi repository lejárt offline grace mellett.
A teljes recept parser → szerkeszthető editor → explicit mentés teszt most Free-ként fut.
A shopping preview szerkesztés/mentés tesztjei szintén Free-ként futnak.
A régi Pro-import elvárásokat az új policy váltja fel; a megmaradó Pro boundary és
sessionváltás-védelem tesztjei scalinggel továbbra is futnak.

Forráskeresés: nincs recipeTextImport/shoppingTextImport ProFeature-hivatkozás,
nincs importdialog entitlement guard, nincs textimport Pro-marketing a futó UI-ban.
A korábbi fázisriportok történeti dokumentumok; termékpolicyjukat ez a döntés felülírja.

## Manuális ellenőrzőlista (telefon / Android Studio)

1. Free userrel vagy a jelenlegi offline-dev állapotban nyisd meg az appot.
2. Nyisd meg a Receptek fület.
3. Nyisd meg a szöveges importot.
4. Ellenőrizd: nincs Pro popup vagy Pro-jelölés.
5. Illessz be receptszöveget.
6. Feldolgozás után szerkeszd az editorban az importált adatokat.
7. Mentsd a receptet, ellenőrizd az eredményt.
8. Nyisd meg a Shopping/Lista fület.
9. Nyisd meg a szöveges importot.
10. Ellenőrizd: nincs Pro popup.
11. Illessz be listát, szerkeszd a preview-t, hajtsd végre az importot.
12. Ellenőrizd: receptátszámítás és átszámított shopping továbbra is Pro-gated.
13. Ellenőrizd: Mit főzzek? továbbra is Pro-gated.

## Korlátok / következő fázis

Manuális készülékteszt ebben a körben nem történt. Ismert M1 P0/P1 blocker nincs.
A meglévő recept-textimport belépési API gate-független, ezért a későbbi Android
Share szövegátadáshoz használható alap. Intent fogadás és automatikus szövegátadás
még nincs implementálva; ezek külön fázis feladatai.

BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PRODUCTION CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
ANDROID SHARE IMPLEMENTATION: NOT STARTED
IMAGE IMPORT CHANGES: NONE
COMMIT: NONE
PUSH: NONE
