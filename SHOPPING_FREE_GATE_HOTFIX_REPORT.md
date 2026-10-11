# Shopping Free Gate Hotfix

## Verdict

READY – a bevásárlólistához adás Free; a receptátszámítás Pro maradt.

## Root cause

A RecipeDetailsScreen normál „Bevásárlólistához adás” gombja tévesen a ProFeature.scaledRecipeToShopping mögött volt. Nemcsak belépéskor, hanem a hozzáadási dialog megerősítésekor és a tényleges írás előtt is Pro-ellenőrzést végzett. Emiatt unknown/offline/unavailable állapotban internetet kért a Pro igazolásához. A RecipeScalingDialog külön shopping-add ellenőrzést is végzett.

## Változás

- Normál recipe → shopping: mindhárom Pro gate eltávolítva.
- Scaling dialog → shopping: külön Pro gate eltávolítva.
- A már elkészült scaling eredmény hozzáadása nem olvassa újra az entitlementet. A pending számítás feldolgozása csak akkor ellenőriz Pro-t, ha tényleges új számítás várakozik.
- A scaledRecipeToShopping kikerült a ProFeature enumból és a feature-gate címleképezésből.
- A Pro benefit listából kikerült az önálló „Átszámított recept → bevásárlólista” sor.
- ShoppingRepository továbbra sem függ entitlementtől. A normál hozzáadás dialogja account-azonosságot ellenőriz az Auth alapján; ez nem monetizációs gate. A felhasználóváltás/logout nem jogosít fel a régi művelet másik accountba mentésére.
- A meglévő shopping szorzó, unit normalizálás, merge/add, validáció és hibaüzenetek működése megmaradt.

## Megmaradt Pro védelem

- RecipeDetailsScreen: az „Átszámítás” entry requestje továbbra is ProFeature.recipeScaling.
- RecipeScalingDialog: a Pro számítási felület FeatureBoundary védelme és a tényleges számítás _processPending ellenőrzése megmaradt.
- Mit főzzek, purchase flow, lifetime modell és pricing változatlan.

## Policy audit

A lib/test keresésben nem maradt scaledRecipeToShopping azonosító vagy a külön Pro shopping benefit. A lib/shopping alatt nincs FeatureGate/ProFeature/entitlement/isPro/requiresPro kontroll. A recept részletképernyő megmaradt FeatureGate hivatkozásai az Átszámítás belépéséhez tartoznak.

## Tesztek

- Célzott pro/shopping/recipes/entitlements suite: **841 PASS / 1 korábbi skipped**.
- Teljes Flutter suite: **1245 PASS / 1 korábbi skipped**.
- Flutter analyze --no-pub: **CLEAN**.
- git diff --check: **PASS**.
- Android build nem futott: nincs Android/native változás ebben a hotfixben.
- Backend suite nem futott: nincs backend változás.

Explicit widget teszt minden ClientEntitlementStatus mellett megnyitja és végrehajtja a normál hozzáadást: free, proOnline, proOfflineGrace, unknown, checking, unavailable. Nincs Pro popup; ugyanaz a 100 g-os tétel jut az add callbackbe. A hálózati/igazolási okból unavailable állapot sem blokkol shopping-addet.

További coverage: entitlement revoke után nyitott normál hozzáadás sikeres; Free scaling továbbra blokkolt; Pro scaling és módosított mennyiségek működnek; elkészült scaled eredmény hozzáadása **0 további entitlement read**; régi/disposed scaling callback nem ír; Auth identity check accountváltás/logout esetén false; meglévő manual shopping, text import, merge, Pro UI/purchase regresszió zöld.

A korábbi 1253 helyett 1245 összes teszt oka: a megszüntetett Pro feature generált tiltási mátrixa kikerült; új Free-policy és session tesztek kerültek be. Nem tesztfájlok önkényes kihagyása.

## Érintett fájlok ebben a hotfixben

- lib/recipes/presentation/screens/recipe_details_screen.dart
- lib/recipes/presentation/widgets/recipe_scaling_dialog.dart
- lib/shopping/data/repositories/shopping_repository.dart
- lib/entitlements/domain/models/pro_feature.dart
- lib/pro/feature_gate.dart
- lib/pro/pro_screen.dart
- test/pro/feature_gate_test.dart
- test/pro/n8_closure_test.dart
- test/recipes/recipe_scaling_dialog_test.dart
- test/shopping/shopping_repository_test.dart
- SHOPPING_FREE_GATE_HOTFIX_REPORT.md

A munkakezdéskor már meglévő K2K változások megmaradtak; a direct-open kódhoz ez a hotfix nem nyúlt.

## Rövid telefonos ellenőrzés / korlát

1. Free vagy jelenlegi offline-dev állapot → normál recept → Bevásárlólistához adás → Hozzáadás: nincs Pro/internet-igazolási popup.
2. Internet nélkül ugyanez: a Pro policy nem blokkol; a tényleges adatírás/szinkron a meglévő Firestore működését követi. A tesztek nem jelentenek fizikai offline cloud-sync mérési eredményt.
3. Free → Átszámítás: továbbra is Pro UX.
4. Pro → Átszámítás → új mennyiség → shopping: helyes mennyiségek, nincs második Pro kérés.
5. Manual shopping és shopping text import változatlan.

NORMAL RECIPE → SHOPPING: FREE
SCALED RESULT → SHOPPING: NO SEPARATE PRO GATE
RECIPE SCALING: PRO
OFFLINE FREE SHOPPING ADD: PASS
UNKNOWN ENTITLEMENT SHOPPING ADD: PASS
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PRODUCTION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
