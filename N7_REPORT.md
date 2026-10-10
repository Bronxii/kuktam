# N7 – Pro feature gates és kontextusos upsell

2026-10-09 — **READY FOR N8** (helyi QA-fázisra; nem production release-jóváhagyás).

## Funkciómátrix – N8 referencia

| Funkció | Free | Pro online / offline grace |
|---|---|---|
| Kézi recept CRUD, megtekintés | Korlátlan | Korlátlan |
| Receptkeresés | Igen | Igen |
| Kézi bevásárlólista CRUD, checkbox, lezárás/másolás | Korlátlan | Korlátlan |
| Cloud sync, profil, auth | Igen | Igen |
| Recept szöveges import | Pro tájékoztató | Igen |
| Bevásárlólista szöveges import | Pro tájékoztató | Igen |
| Receptátszámítás | Pro tájékoztató | Igen |
| Átszámított recept → bevásárlólista | Pro tájékoztató | Igen |
| Mit főzzek? | Pro tájékoztató | Igen |
| Képes/AI import | Nem elérhető | Nem elérhető |

Nincs darabszámlimit, kvóta, slot, usage counter, reklám vagy subscription.

## Belépési audit és védelem

| Funkció | Belépés | Végrehajtási ellenőrzés |
|---|---|---|
| Receptimport | MainScreen importikon → showRecipeImportDialog | Public RecipeImportDialog boundary; parser előtti guard; MainScreen editor-handoff előtti guard és UID-egyezés |
| Shopping import | MainScreen Lista/importikon → showShoppingImportDialog | Public ShoppingImportDialog boundary; feldolgozás és repository-hívás előtt külön guard |
| Átszámítás | RecipeDetailsScreen / Átszámítás | Public RecipeScalingDialog boundary; debounce feldolgozás előtt friss guard |
| Átszámított shopping | RecipeScalingDialog hozzáadás | Külön scaledRecipeToShopping ellenőrzés a tényleges hozzáadás előtt |
| Adagszorzós shopping | RecipeDetailsScreen / Bevásárlólistához adás | Külön belépési, jóváhagyási és repository előtti guard; megnyitó UID ellenőrzése |
| Mit főzzek? | MainScreen NavigationBar, közvetlen WhatToCookScreen | Boundary még a belső screen/repository létrehozása előtt; ingredient action és matcher eredményszámítás előtt ellenőrzés |

A details két async belépése a jogosultságellenőrzés előtti UID-t is ellenőrzi a dialógus megnyitása előtt; accountváltás a két lépés között sem viheti át a régi receptet. Két külön regressziós teszt igazolja.

A code search nem talált további named route-ot, deep-linket vagy más parser/scaler/matcher UI-hívási útvonalat. A tiszta domain parser/scaler/matcher megmaradt UI- és entitlement-függetlennek; az app végrehajtási hívási helyei védettek. A Flutter gate üzleti/UX-szabály, nem manipulált kliens elleni biztonsági határ.

## Közös architektúra

- `FeatureGate` az app által birtokolt N5 entitlement repository aktuális állapotát olvassa a meglévő `ProScope`-ból. A `FeatureAccessScope` csak függőségátadást tesz lehetővé teszthez/route-hoz; nem hoz létre repositoryt.
- A hozzáférési döntés a meglévő `ClientEntitlementState.access(ProFeature)` adapterből, azon keresztül az N1 `FeatureAccessService`-ből jön. Nincs második Pro flag, source-prioritás vagy purchase-flow alapú hozzáférés.
- `request` a prezentációs belépést, `execute` a művelet előtti friss döntést kezeli. A korábbi ALLOWED eredmény nem tárolt engedély.
- `FeatureBoundary` a public konstruktorokat is védi. Free állapotban nem építi fel az import/scaling/matcher belső tartalmát. Az IndexedStackben előre létrejövő Mit főzzek? sem indít ilyenkor saját receptfigyelést vagy matchert.
- `_FeatureSession` UID-val köti a megnyitott belső tartalmat a sessionhöz. Régi callback más UID alatt nem futtathat Pro műveletet. UID-váltáskor a régi tartalom eldobódik.
- Az N5 késői, korábbi sessionből érkező válaszainak fencingje változatlan; a teljes N5 regressziós suite futott.

## Állapotok és UX

- Free: rövid, funkcióspecifikus Material dialog, egyszeri vásárlás/előfizetés nélkül szöveg, Pro megtekintése és Mégse.
- Pro online és offline grace: nincs köztes upsell; normál feature-flow.
- Unknown/checking: ellenőrzési tájékoztatás, nincs vásárlási CTA. Friss entitlement után a boundary azonnal reagál.
- Lejárt/nem elfogadható bizonyíték (`unavailable`): kapcsolat szükséges, nem újravásárlási üzenet. A hitelesség, idő és grace eldöntése az N5 feladata maradt.
- Törlés alatt/törölt account: érthető fiókállapot-üzenet, nincs upsell vagy új Pro művelet.
- Image import: mindig featureUnavailable; nincs új működő képes import vagy vásárlással feloldható ígéret.
- Pro → Free ugyanazon UID-n: a már megnyitott draft rejtve, memóriában megmarad; új Pro művelet nem indulhat. Jogosultság visszatérésekor a draft folytatható. Accountváltás eldobja a draftot. Nincs agresszív automatikus navigáció.
- A már engedélyezetten elindított repository-írást nem próbáljuk visszagörgetni. A guard az új művelet indításának határa; a normál adatírás továbbra is Free művelet.
- Free → Pro után nincs automatikus feature-resume. Visszalépés után a következő tap már az aktuális állapot szerint működik.

Az importikonok és a Mit főzzek? navigáció diszkrét PRO jelzést kapnak csak megbízható Free állapotban, „Pro funkció” semantics címkével. A közös prompt görgethető; kis viewport és kétszeres betűméret tesztelve.

A CTA a meglévő N6 ProScreenre navigál, ugyanazt az app-controller példányt kölcsönzi. Nem vásárol közvetlenül, nem inicializál új Billinget, és route bezáráskor nem dispose-olja a globális szolgáltatást. Navigator-szintű kizárás és egyszer használható promptválasz védi a dupla tapet/dupla popot. A közvetlenül blokkolt képernyő CTA-ja ugyanide vezet.

## Free funkciók és kódaudit

- RecipeRepository, ShoppingRepository, normál save/edit/delete, keresés, sync és Firestore-szabályok nem változtak.
- A kézi recept- és shopping core widgettesztek kifejezetten Free scope-pal futnak: create/edit/delete/search, manuális tételek, checkbox, lista műveletek és hiba/retry változatlanul működnek.
- Csak a már eleve Pro feature-t tesztelő regressziós felületek kaptak Pro fake-et. A vegyes unit-dropdown tesztben kizárólag a shopping-import felület Pro; normál ingredient és shopping-item Free.
- Repository/domain szinten nincs entitlement gate a recept/shopping adatok vagy cloud sync körül.
- Régi 15/15, recipeLimit, shoppingLimit, maxFree, usageCount, quota, webRecipeImport monetizációs maradvány nem került elő az auditált app/backend source-ban.
- A meglévő N6 `isPro` getter csak státusz/prezentációs feladatot lát el; N7 nem használja gate-döntésre. Nincs entitlement-source enum vizsgálat a gate UI-ban.
- A ProScreen listája az öt tényleges gate-tel egyezik. A subscription szövegtalálatok „nincs előfizetés” jelentésűek; a StreamSubscription programkód nem termékmodell.
- Nincs új logolás, tokenkezelés, entitlement-perzisztálás vagy nyers hibaüzenet.

## N7 fájlok

Új:

- `lib/pro/feature_gate.dart`
- `test/pro/feature_gate_test.dart`
- `test/support/feature_access.dart`
- `N7_REPORT.md`

Módosított production:

- `lib/home/presentation/screens/main_screen.dart`
- `lib/recipes/presentation/screens/recipe_details_screen.dart`
- `lib/recipes/presentation/widgets/recipe_import_dialog.dart`
- `lib/recipes/presentation/widgets/recipe_scaling_dialog.dart`
- `lib/shopping/presentation/widgets/shopping_import_dialog.dart`
- `lib/what_to_cook/presentation/screens/what_to_cook_screen.dart`

Módosított regressziós tesztek:

- `test/recipes/recipe_core_test.dart`
- `test/recipes/recipe_extra_qa_test.dart`
- `test/recipes/recipe_import_dialog_test.dart`
- `test/recipes/recipe_scaling_dialog_test.dart`
- `test/recipes/unit_dropdown_scroll_test.dart`
- `test/shopping/shopping_core_qa_test.dart`
- `test/shopping/shopping_import_dialog_test.dart`
- `test/shopping/shopping_repository_test.dart`
- `test/what_to_cook/what_to_cook_screen_test.dart`

A formatter a módosított, korábban részben formázatlan fájlok behúzását is rendezte. A munkafában már N7 előtt sok N1–N6 változás volt, például main.dart, pubspec/lock, Android config, backend és N6 Pro UI; ezeket N7 nem módosította vagy vonta vissza. N7 nem ad dependencyt, backendváltozást vagy production konfigurációt.

## Ellenőrzések

| Ellenőrzés | Eredmény |
|---|---|
| Új N7 adapter/widget tesztek | **77 PASS** |
| Teljes Flutter suite | **1085 PASS / 1 skipped** |
| N1 feature access; N5.1 entitlement; N5.2 Billing; N5.3 integration | PASS, a teljes suite része |
| N6 Pro/Profile/deletion/purchase UI regresszió | PASS, a teljes suite része |
| Régi import/scaling/scaled-shopping/matcher tesztek Pro-val | PASS |
| Free recipe/shopping core és keyboard/scroll/unit regresszió | PASS |
| `flutter analyze --no-pub` | CLEAN |
| Dart formatter, módosított Dart-fájlok | CLEAN |
| `git diff --check` | CLEAN |
| Új/untracked fájlok whitespace ellenőrzése | CLEAN (Windows CRLF figyelembevételével) |
| Android `build apk --debug --no-pub` | PASS |

Az egy skipped teszt a korábbi, külön instrumentation kapcsolóhoz kötött scaling performance teszt; N7 nem hozott létre új skipet.

Az új tesztek lefedik a teljes feature/status mátrixot, mind az öt kontextust, valódi main/detail entryket, közvetlen konstruktorokat, tényleges Pro online/offline parser/scaling/shopping/matcher flow-t, visszavonást közvetlen végrehajtás előtt, accountváltás/logout régi callbacket, draft megtartás/eldobás szabályt, checking → Free → Pro változást, deletion állapotot, dupla tapet, dupla CTA-t, N6 controller megőrzését, kis viewportot és semantics jelölést. A gate-dialogból nincs purchase-hívás.

APK: `build/app/outputs/flutter-apk/app-debug.apk`.
Ellenőrzési naplók: `%LOCALAPPDATA%/Temp/kuktam-n7-full.log`, `kuktam-n7-new.log`, `kuktam-n7-build.log`.

## Korlátok, kockázatok és N8 átadás

- Ismert nyitott N7 P0/P1: nincs az elvégzett audit és automatizált tesztek alapján.
- P2, korábbi buildfigyelmeztetés: a cloud_functions plugin Kotlin Gradle Plugin használata egy későbbi Flutter-verzión kompatibilitási munkát igényelhet. A jelenlegi debug build sikeres; N7 nem frissít csomagokat.
- Production composition továbbra is `onlineEnabled: false`. Bizonyított Pro/Free állapotok lokális tesztkompozícióban vizsgálva; normál buildben nincs fejlesztői Pro bypass. Ez nem éles monetizációs release.
- Valódi Play-vásárlás, fizikai eszközös teljes journey és production infra nincs tesztelve/élesítve ebben a fázisban.
- Az N5 proof/grace hitelességi és session-szabályai változatlanok. Az N8 teljes offline/resume/órahatár és accountváltási QA ezekkel együtt ellenőrizze a gate-eket.
- A gate nem security boundary; tiszta domain segédek továbbra is önállóan tesztelhetők. Jövőbeli új UI/action hívási helynek is használnia kell a közös guardot.

N8 előfeltételei teljesültek: zöld full suite/analyzer/debug build; fenti végleges feature-mátrix és entry audit; létező fake entitlement/Billing kompozíció; N6 közös ProScreen. N8 következő scope: Free/Pro teljes journey, offline grace/resume, account switch, deletion, purchase/restore UX, gates és release-prep audit production infra bekötése előtt. N8 nem indult el.

PRODUCTION FIREBASE CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
PRODUCTION DEPLOY: NONE
REAL PLAY PURCHASE TEST: NOT PERFORMED
IMAGE IMPORT: NOT STARTED
COMMIT: NONE
PUSH: NONE
