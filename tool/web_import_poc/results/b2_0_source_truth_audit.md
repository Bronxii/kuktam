# B2.0 – source-truth audit, 11–20

B2.0 only. Audit snapshots; no POC extractor, RecipeTextParser, timing or accuracy benchmark. Visible DOM is authoritative. Ingredients retain source wording with layout whitespace collapsed. Full instructions remain in immutable HTML, referenced by selector/index/SHA256, not paraphrased. Future content benchmark must resolve references, not score them as prose. Scope: main recipe only; separate FAQs, comments and standalone notes outside Method/Elkészítés excluded.

```json
{
  "already_correct_files": 0,
  "corrected_files": 10,
  "title_corrections": 0,
  "ingredient_line_edit_operations": 33,
  "instruction_references_corrected": 10,
  "ingredient_group_headings_restored": 1,
  "source_jsonld_difference_observations": 9,
  "unresolved": 0
}
```

| ID | Cím | Hozzávaló előtte/utána | Sorjavítás | Instrukció előtte/utána | JSON-LD eltérés |
|---|---|---|---|---|---|
| 11 | Lecsó | 7/7 | 0 | 4/4 | 1 |
| 12 | Töltött káposzta | 14/14 | 4 | 6/5 | 2 |
| 13 | Klasszikus paprikás krumpli | 9/9 | 0 | 5/3 | 1 |
| 14 | Hagyományos szatmári töltött káposzta | 10/10 | 2 | 6/4 | 3 |
| 15 | Rakott krumpli magyarosan | 8/8 | 0 | 6/1 | 1 |
| 16 | Ultimate spaghetti carbonara recipe | 9/8 | 3 | 6/12 | 0 |
| 17 | Classic Victoria sandwich recipe | 11/11 | 6 | 6/8 | 1 |
| 18 | Chilli con carne recipe | 16/16 | 5 | 6/16 | 0 |
| 19 | Chicken tikka masala | 12/12 | 5 | 6/5 | 0 |
| 20 | Easy classic lasagne | 15/15 | 8 | 6/5 | 0 |

## 11

Forrás: https://www.mindmegette.hu/recept/lecso

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_CORRECT. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- SOURCE_JSONLD_DIFFERENCE: {"field":"title","category":"SOURCE_JSONLD_DIFFERENCE","visible":"Lecsó","json_ld":"Lecsó | Mindmegette.hu","note":"Címdekoráció."}

## 12

Forrás: https://www.mindmegette.hu/recept/toltott-kaposzta

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- replace: `8 db savanyított káposztalevél` → `8 darab savanyított káposztalevél` (GROUND_TRUTH_FIXED).
- replace: `1 db tojás` → `1 darab tojás` (GROUND_TRUTH_FIXED).
- replace: `2 ek olaj` → `2 evőkanál olaj` (GROUND_TRUTH_FIXED).
- replace: `2 ek liszt` → `2 evőkanál liszt` (GROUND_TRUTH_FIXED).
- SOURCE_JSONLD_DIFFERENCE: {"field":"title","category":"SOURCE_JSONLD_DIFFERENCE","visible":"Töltött káposzta","json_ld":"Töltött káposzta | Mindmegette.hu","note":"Címdekoráció."}
- SOURCE_JSONLD_DIFFERENCE: {"field":"instruction_structure_or_text","category":"SOURCE_JSONLD_DIFFERENCE","visible_blocks":5,"json_ld_blocks":1,"note":"Blokkhatár vagy szöveg eltér; nem automatikusan lépésveszteség."}

## 13

Forrás: https://www.mindmegette.hu/recept/klasszikus-paprikas-krumpli

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_CORRECT. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- SOURCE_JSONLD_DIFFERENCE: {"field":"title","category":"SOURCE_JSONLD_DIFFERENCE","visible":"Klasszikus paprikás krumpli","json_ld":"Klasszikus paprikás krumpli | Mindmegette.hu","note":"Címdekoráció."}

## 14

Forrás: https://www.mindmegette.hu/recept/hagyomanyos-szatmari-toltott-kaposzta

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- replace: `1 fej édes káposzta` → `1 fej édes káposzta (1,5 kg)` (GROUND_TRUTH_FIXED).
- replace: `3 dl paradicsomlé` → `3 dl paradicsomlé (házi)` (GROUND_TRUTH_FIXED).
- SOURCE_JSONLD_DIFFERENCE: {"field":"title","category":"SOURCE_JSONLD_DIFFERENCE","visible":"Hagyományos szatmári töltött káposzta","json_ld":"Hagyományos szatmári töltött káposzta | Mindmegette.hu","note":"Címdekoráció."}
- SOURCE_JSONLD_DIFFERENCE: {"field":"ingredient","category":"SOURCE_JSONLD_DIFFERENCE","visible_row":8,"json_ld_row":8,"visible":"1 fej édes káposzta (1,5 kg)","json_ld":"1 fej édes káposzta"}
- SOURCE_JSONLD_DIFFERENCE: {"field":"ingredient","category":"SOURCE_JSONLD_DIFFERENCE","visible_row":9,"json_ld_row":9,"visible":"3 dl paradicsomlé (házi)","json_ld":"3 dl paradicsomlé"}

## 15

Forrás: https://www.mindmegette.hu/recept/rakott-krumpli-magyarosan

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_CORRECT. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- SOURCE_JSONLD_DIFFERENCE: {"field":"title","category":"SOURCE_JSONLD_DIFFERENCE","visible":"Rakott krumpli magyarosan","json_ld":"Rakott krumpli magyarosan  | Mindmegette.hu","note":"Címdekoráció."}

## 16

Forrás: https://www.bbcgoodfood.com/recipes/ultimate-spaghetti-carbonara-recipe

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- replace: `2 garlic cloves` → `2 plump garlic cloves peeled and left whole` (GROUND_TRUTH_FIXED).
- remove: `sea salt` → `—` (GROUND_TRUTH_FIXED).
- replace: `freshly ground black pepper` → `sea salt and freshly ground black pepper` (GROUND_TRUTH_FIXED).

## 17

Forrás: https://www.bbcgoodfood.com/recipes/classic-victoria-sandwich-recipe

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- replace: `4 eggs` → `4 eggs beaten` (GROUND_TRUTH_FIXED).
- replace: `100g butter` → `100g butter softened` (GROUND_TRUTH_FIXED).
- replace: `140g icing sugar` → `140g icing sugar sifted` (GROUND_TRUTH_FIXED).
- replace: `vanilla extract` → `drop vanilla extract (optional)` (GROUND_TRUTH_FIXED).
- replace: `170g strawberry jam` → `half a 340g jar good-quality strawberry jam` (GROUND_TRUTH_FIXED).
- replace: `icing sugar` → `icing sugar to decorate` (GROUND_TRUTH_FIXED).
- SOURCE_JSONLD_DIFFERENCE: {"field":"ingredient_group","category":"SOURCE_JSONLD_DIFFERENCE","visible":"For the filling","json_ld":null,"note":"A lapos recipeIngredient listában nincs csoportcím."}

## 18

Forrás: https://www.bbcgoodfood.com/recipes/chilli-con-carne-recipe

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- replace: `1 heaped tsp hot chilli powder` → `1 heaped tsp hot chilli powder (or 1 level tbsp if you only have mild)` (GROUND_TRUTH_FIXED).
- replace: `400g can chopped tomatoes` → `400g can Mutti chopped tomatoes` (GROUND_TRUTH_FIXED).
- replace: `0.5 tsp dried marjoram` → `½ tsp dried marjoram` (GROUND_TRUTH_FIXED).
- replace: `1 tsp sugar` → `1 tsp sugar (or add a thumbnail-sized piece of dark chocolate along with the beans instead, see tip)` (GROUND_TRUTH_FIXED).
- replace: `rice to serve` → `plain boiled long grain rice to serve` (GROUND_TRUTH_FIXED).

## 19

Forrás: https://www.bbcgoodfood.com/recipes/chicken-tikka-masala

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- replace: `4 onions` → `4 onions roughly chopped` (GROUND_TRUTH_FIXED).
- replace: `6 tbsp chicken tikka masala paste` → `6 tbsp chicken tikka masala paste (use shop-bought or make your own – see recipe, below)` (GROUND_TRUTH_FIXED).
- replace: `2 red peppers` → `2 red peppers deseeded and cut into chunks` (GROUND_TRUTH_FIXED).
- replace: `8 boneless skinless chicken breasts` → `8 boneless, skinless chicken breasts cut into 2.5cm cubes` (GROUND_TRUTH_FIXED).
- replace: `coriander` → `chopped coriander leaves, to serve` (GROUND_TRUTH_FIXED).

## 20

Forrás: https://www.bbcgoodfood.com/recipes/classic-lasagne

Cím: GROUND_TRUTH_CORRECT. Hozzávalók: GROUND_TRUTH_FIXED. Elkészítés: GROUND_TRUTH_FIXED. UNRESOLVED: nincs.

- replace: `1 onion` → `1 onion finely chopped` (GROUND_TRUTH_FIXED).
- replace: `1 celery stick` → `1 celery stick, finely chopped` (GROUND_TRUTH_FIXED).
- replace: `1 medium carrot` → `1 medium carrot grated` (GROUND_TRUTH_FIXED).
- replace: `2 garlic cloves` → `2 garlic cloves finely chopped` (GROUND_TRUTH_FIXED).
- replace: `500g fresh egg lasagne sheets` → `500g pack fresh egg lasagne sheets` (GROUND_TRUTH_FIXED).
- replace: `125g mozzarella` → `125g ball mozzarella roughly torn` (GROUND_TRUTH_FIXED).
- replace: `50g parmesan` → `50g freshly grated parmesan` (GROUND_TRUTH_FIXED).
- replace: `basil leaves` → `large handful basil leaves torn (optional)` (GROUND_TRUTH_FIXED).

## Felhasználási szerződés

Az @VISIBLE sorok nem főzési szövegek. Feloldás: snapshot SHA256 ellenőrzés, CSS selector, nulla alapú index, content mező. A BBC lépéscímkék külön szerepelnek. A 12-es 5 bekezdését és a 15-ös egybefüggő bekezdését nem bontottuk kitalált lépésekre. A 17-es [For the filling] csoportcím nem hozzávaló.

A corpus közös README-jének tömör instrukciókról szóló leírása Batch 2-re már nem érvényes; más batchekhez nem nyúltunk. B2.1 külön engedéllyel indítható. B2.2 köteles feloldani a snapshotreferenciákat. Nem számoltunk batch accuracy-t.
