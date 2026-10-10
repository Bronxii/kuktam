# UI-1 – Recipe editor ingredient row

**Verdict: READY (automatizált ellenőrzés alapján).**

## Probléma és javítás
A korábbi 5:2 név/mennyiség arány és a 76 px-es dropdown túl kevés belső helyet hagyott a feliratnak és a kétbetűs egységeknek.

A közös IngredientRow javítása a létrehozásra és a szerkesztésre is érvényes:
- A Mennyiség label állandóan a kereten látszik; a szükséges szélességet a tényleges betűstílus és szövegméretezés alapján számítjuk.
- Az egységválasztó legalább 84 px széles, szövegméretezéssel növekedhet. A belső vízszintes padding több helyet hagy a kiválasztott egységnek.
- Elegendő hely esetén a név a fennmaradó szélességet kapja, minden mező egy sorban marad.
- Szűk helyen a név külön sorba kerül, alatta a mennyiség/egység/törlés marad egy sorban. Ez megakadályozza, hogy a név használhatatlanul keskeny legyen.
- A név továbbra is egysoros, vízszintesen görgethető/szerkeszthető. A numerikus billentyűzet változatlan.
- A színek, betűstílusok, ikonok, unit-lista, menuMaxHeight, dropdown-scroll, parser és mentés változatlan.
- Import preview nem kapott külön módosítást; az importból megnyíló editor automatikusan ugyanazt a javított sort használja.

## Érintett fájlok
- lib/recipes/presentation/widgets/ingredient_row.dart
- test/recipes/ingredient_row_layout_test.dart (új)
- test/recipes/add_recipe_screen_test.dart (a korábbi egy-soros elvárás igazítása az adaptív layout-hoz; formázás)
- UI_1_RECIPE_EDITOR_REPORT.md

## Tesztek
85 célzott Flutter widget/editor/core teszt PASS:
- ingredient_row_layout_test.dart: 24 eset, 320/360/400 logical px; g/ml/dl/db/kg/l/tk/ek.
- A label nem ellipszizálódik; a zárt dropdown szövegének tényleges szélessége elég a teljes egységhez.
- Hosszú név megmarad, egysoros, a szerkesztő vízszintes görgetése működik; nincs render exception.
- unit_dropdown_scroll_test.dart: meglévő menümagasság és összes unit elérhetősége; 320 px és 400 px / 1.6 szövegméretezés.
- add_recipe_screen_test.dart + recipe_core_test.dart: create/edit, validáció, mentés, import/editor és dirty/back regresszió.

Flutter analyze --no-pub: CLEAN.
Git diff --check és új teszt/riport whitespace ellenőrzés: PASS.
Teljes Flutter suite: nem futott; a kis UI-változáshoz a célzott 85 tesztet futtattam.
Backend teszt: nem futott, backend nem változott.

## Manuális checklist – Android Studio / telefon
1. Nyisd meg az Új recept képernyőt.
2. Ellenőrizd a hozzávalósort normál és keskeny telefonon.
3. A Mennyiség felirat üres és kitöltött mezőnél is teljes legyen.
4. Válaszd az ml egységet: zárva is teljesen látszódjon.
5. dl: a jelenlegi app unit-listájában NINCS; a reusable widget ezt külön teszt-fixture-rel igazolja. A listát a kérésnek megfelelően nem bővítettem.
6. Válaszd a db egységet: zárva is teljesen látszódjon.
7. Gépelj hosszú hozzávalónevet; mozgass kurzort az elejére/végére.
8. Ne legyen overflow vagy egymásra lógó mező; szűk helyen a név a többi mező felett jelenhet meg.
9. Nyiss meg egy meglévő receptet szerkesztésre, és ismételd meg.
10. Mentsd, majd nyisd újra: név, mennyiség és egység helyesen maradjon meg.

## Korlátok
Fizikai telefonos vizuális ellenőrzés nem történt. Extrém szövegnagyítás minden elképzelhető szélességgel nem lett tesztelve. A dl-listatagság külön termék/parser kérdés; itt kizárólag a megjelenítését teszteltük, a támogatott listát nem változtattuk.
Az automatikus approval review egy HEAD-alapú tesztfájl-visszaírást adatvesztési kockázat miatt elutasított; ezt nem hajtottam végre. A jelenlegi fájlokon végzett célzott javításokkal a feladat elkészült.

BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PRODUCTION CHANGES: NONE
MONETIZATION CHANGES: NONE
ANDROID SHARE CHANGES: NONE
COMMIT: NONE
PUSH: NONE
