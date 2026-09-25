# B3.0 – source-truth audit, 21–30

B3.0 only. Audit snapshots; no POC extractor, RecipeTextParser, timing or accuracy benchmark. Visible DOM is authoritative. Ingredients retain source wording with layout whitespace collapsed. Full instructions remain in immutable HTML, referenced by selector/index/SHA256, not paraphrased. Future content benchmark must resolve references, not score them as prose. Scope: main recipe only; separate FAQs, comments and standalone notes outside Method/Elkészítés excluded.

```json
{
  "already_correct_files": 0,
  "corrected_files": 8,
  "title_corrections": 0,
  "ingredient_line_edit_operations": 38,
  "instruction_references_corrected": 8,
  "ingredient_group_headings_restored": 4,
  "source_jsonld_difference_observations": 4,
  "format_only_ingredient_edits": 1,
  "content_ingredient_edits": 37,
  "instruction_reference_entries": 47,
  "unresolved": 2,
  "total_recipes": 10,
  "audited_recipes": 8
}
```

| ID | Cím | Hozzávaló előtte/utána | Sorjavítás | Instrukció előtte/utána | JSON-LD eltérés |
|---|---|---|---|---|---|
| 21 | Easy chicken curry | 11/11 | 7 | 6/4 | 0 |
| 22 | Easy pancakes | 7/6 | 4 | 5/5 | 0 |
| 23 | Fish pie - in four steps | 13/13 | 5 | 5/4 | 0 |
| 24 | Best ever chocolate brownies recipe | 8/8 | 1 | 6/15 | 0 |
| 25 | Easy apple crumble recipe | 8/8 | 4 | 6/8 | 3 |
| 26 | Tomato soup | 9/9 | 4 | 6/6 | 0 |
| 27 | Real tomato soup | 8/8 | 3 | 6/2 | 0 |
| 28 | Chicken chilli con carne | 17/19 | 10 | 6/3 | 1 |
| 29 | null | 11/11 | 0 | 6/null | 0 |
| 30 | null | 7/7 | 0 | 5/null | 0 |

## 21

Forrás: https://www.bbcgoodfood.com/recipes/easy-chicken-curry

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: [].

- replace: `1 onion` → `1 onion thinly sliced` (GROUND_TRUTH_FIXED).
- replace: `2 garlic cloves` → `2 garlic cloves crushed` (GROUND_TRUTH_FIXED).
- replace: `thumb-sized piece of ginger` → `thumb-sized piece of ginger grated` (GROUND_TRUTH_FIXED).
- replace: `6 boneless skinless chicken thighs` → `6 chicken thighs boneless and skinless` (GROUND_TRUTH_FIXED).
- replace: `3 tbsp medium spice paste` → `3 tbsp medium spice paste (tikka works well)` (GROUND_TRUTH_FIXED).
- replace: `1 small bunch coriander` → `1 small bunch of coriander leaves chopped` (GROUND_TRUTH_FIXED).
- replace: `naan breads or basmati rice` → `naan breads or cooked basmati rice, to serve` (GROUND_TRUTH_FIXED).

## 22

Forrás: https://www.bbcgoodfood.com/recipes/easy-pancakes

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: [].

- remove: `1 tbsp sunflower or vegetable oil` → `—` (GROUND_TRUTH_FIXED).
- replace: `extra oil for frying` → `1 tbsp sunflower or vegetable oil plus a little extra for frying` (GROUND_TRUTH_FIXED).
- replace: `lemon wedges optional` → `lemon wedges to serve (optional)` (GROUND_TRUTH_FIXED).
- replace: `caster sugar optional` → `caster sugar to serve (optional)` (GROUND_TRUTH_FIXED).

## 23

Forrás: https://www.bbcgoodfood.com/recipes/fish-pie-four-steps

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: [].

- replace: `1 small onion` → `1 small onion quartered` (GROUND_TRUTH_FIXED).
- replace: `small bunch parsley` → `small bunch parsley leaves only, chopped` (GROUND_TRUTH_FIXED).
- replace: `pinch nutmeg` → `pinch freshly grated nutmeg` (GROUND_TRUTH_FIXED).
- replace: `1kg floury potatoes` → `1kg floury potato peeled and cut into even-sized chunks` (GROUND_TRUTH_FIXED).
- replace: `50g cheddar` → `50g cheddar grated` (GROUND_TRUTH_FIXED).

## 24

Forrás: https://www.bbcgoodfood.com/recipes/best-ever-chocolate-brownies-recipe

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: [].

- replace: `185g dark chocolate` → `185g best dark chocolate` (GROUND_TRUTH_FIXED).

## 25

Forrás: https://www.bbcgoodfood.com/recipes/best-apple-crumble

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: [].

- replace: `575g Bramley apples` → `575g Bramley apple (3 medium apples), peeled, cored and sliced to 1cm thick` (GROUND_TRUTH_FIXED).
- replace: `1 tbsp rolled oats optional` → `1 tbsp rolled oats` (GROUND_TRUTH_FIXED).
- replace: `1 tbsp demerara sugar optional` → `1 tbsp demerara sugar` (GROUND_TRUTH_FIXED).
- replace: `cream or custard to serve` → `double cream clotted cream or custard, to serve` (GROUND_TRUTH_FIXED).
- SOURCE_JSONLD_DIFFERENCE: {"field":"ingredient_group","category":"SOURCE_JSONLD_DIFFERENCE","visible":"For the filling","json_ld":null,"note":"A lapos recipeIngredient listában nincs csoportcím."}
- SOURCE_JSONLD_DIFFERENCE: {"field":"ingredient_group","category":"SOURCE_JSONLD_DIFFERENCE","visible":"For the crumble","json_ld":null,"note":"A lapos recipeIngredient listában nincs csoportcím."}
- SOURCE_JSONLD_DIFFERENCE: {"field":"ingredient_group","category":"SOURCE_JSONLD_DIFFERENCE","visible":"For the topping (optional)","json_ld":null,"note":"A lapos recipeIngredient listában nincs csoportcím."}

## 26

Forrás: https://www.bbcgoodfood.com/recipes/tomato-soup

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: [].

- replace: `1-1.25kg ripe tomatoes` → `1-1.25kg/2lb 4oz-2lb 12oz ripe tomatoes` (GROUND_TRUTH_FIXED).
- replace: `2 tsp tomato purée` → `2 squirts of tomato purée (about 2 tsp)` (GROUND_TRUTH_FIXED).
- replace: `pinch of sugar` → `a good pinch of sugar` (GROUND_TRUTH_FIXED).
- replace: `1.2 litres hot vegetable stock` → `1.2 litres/2 pints hot vegetable stock (made with boiling water and 4 rounded tsp bouillon powder or 2 stock cubes)` (GROUND_TRUTH_FIXED).

## 27

Forrás: https://www.bbcgoodfood.com/recipes/real-tomato-soup

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: [].

- replace: `1 onion` → `1 onion chopped` (GROUND_TRUTH_FIXED).
- replace: `1 garlic clove` → `1 garlic clove finely chopped` (GROUND_TRUTH_FIXED).
- replace: `handful basil leaves` → `handful basil leaf` (GROUND_TRUTH_FIXED).

## 28

Forrás: https://www.bbcgoodfood.com/recipes/chicken-chilli-con-carne

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: [].

- replace: `1 onion` → `1 onion sliced` (GROUND_TRUTH_FIXED).
- replace: `2 mixed peppers` → `2 mixed peppers sliced (use red, yellow or orange peppers)` (GROUND_TRUTH_FIXED).
- replace: `2 large garlic cloves` → `2 large garlic cloves crushed` (GROUND_TRUTH_FIXED).
- replace: `1 small bunch coriander` → `1 small bunch of coriander stalks finely chopped and leaves roughly chopped` (GROUND_TRUTH_FIXED).
- replace: `0.5 tbsp ground coriander` → `½ tbsp ground coriander` (FORMAT_ONLY).
- replace: `4 skinless chicken thighs` → `4 skinless chicken thighs bone-in` (GROUND_TRUTH_FIXED).
- replace: `400g can kidney beans` → `400g can kidney beans drained` (GROUND_TRUTH_FIXED).
- add: `—` → `20g dark chocolate (at least 70% cocoa solids)` (GROUND_TRUTH_FIXED).
- add: `—` → `cooked rice or tortilla chips` (GROUND_TRUTH_FIXED).
- replace: `20g dark chocolate` → `guacamole and soured cream (optional)` (GROUND_TRUTH_FIXED).
- SOURCE_JSONLD_DIFFERENCE: {"field":"ingredient_group","category":"SOURCE_JSONLD_DIFFERENCE","visible":"To serve","json_ld":null,"note":"A lapos recipeIngredient listában nincs csoportcím."}

## 29

Forrás: https://www.foodnetwork.com/recipes/food-network-kitchen/classic-meatloaf-5484735

Cím: UNRESOLVED. Hozzávalók: null. Elkészítés: UNRESOLVED. UNRESOLVED: [Direct HTML fetch HTTP 403 twice (PowerShell and curl). No trustworthy local recipe HTML snapshot. Original ground truth unchanged, not approved for accuracy scoring.].


## 30

Forrás: https://www.foodnetwork.com/recipes/guacamole-recipe2-1956046

Cím: UNRESOLVED. Hozzávalók: null. Elkészítés: UNRESOLVED. UNRESOLVED: [Direct HTML fetch HTTP 403 twice (PowerShell and curl). No trustworthy local recipe HTML snapshot. Original ground truth unchanged, not approved for accuracy scoring.].


## Felhasználási szerződés

Az @VISIBLE sorok nem főzési szövegek. Feloldás: snapshot SHA256 ellenőrzés, CSS selector, nulla alapú index, content mező. A BBC lépéscímkék külön szerepelnek. A group headingek nem hozzávalók. 29–30 nem rendelkezik jóváhagyott receptsnapshottal, pontosságmérésből kizárandó, amíg ez nincs feloldva.

A corpus közös README-jének tömör instrukciókról szóló leírása Batch 3-re már nem érvényes; más batchekhez nem nyúltunk. B3.1 technikai fetch külön engedéllyel indítható; a teljes tízre ground-truth alapú pontosságmérés még nem kész. B3.2 köteles feloldani a snapshotreferenciákat. Nem számoltunk batch accuracy-t.

## Állapot és ellenőrzések

21–28: 8 snapshot / 82 hozzávalósor / 47 feloldható instrukcióreferencia. 38 hozzávaló-editművelet, ebből 1 csak formátum (0.5 → ½), 37 tartalmi vagy sorstruktúra-korrekció; ez nem 38 független hibás receptadat. 8 elkészítési referencia cserélte a korábbi tömörítést; 4 ingredient group heading helyreállítva.

29–30: HTTP 403 mindkét közvetlen klienssel. A webes olvasó korlátozott szövegnézete nem helyettesítette az archivált, feloldható recept-HTML-t; abból nem készült referencia. Az eredeti corpus fájlok változatlanok, nem igazoltak. A mentett 403 response body NEM receptsnapshot.

8/8 snapshot SHA256 rendben; corpus/reference tests PASS; 54/54 POC teszt PASS; POC dart analyze és production flutter analyze --no-pub tiszta. B3.1 nem indult el. A teljes tíz recept ground truth-ja még nem lezárható; a két hiányzó oldal megbízható snapshotja szükséges.
