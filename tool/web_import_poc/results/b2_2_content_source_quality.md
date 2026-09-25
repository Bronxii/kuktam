# B2.2 – content/source quality, 11–20

Offline saved snapshots only. B2.0 DOM selectors reused; @VISIBLE resolved, full text checked without republication. Case/whitespace only ingredient comparison, no unit/quantity conversion. Source ingredient alignment manually reviewed. No parser/fetch or source correction. GOOD requires clean title and no structural/content differences; decoration alone is USABLE_WITH_ISSUES. Counts are specific to these frozen snapshots; DOM audit is not a browser rendering test.

## Separate metrics

```json
{
  "technical_extraction_success": {
    "success": 10,
    "total": 10,
    "percent": 100,
    "evidence": "Frozen B2.1 results; not re-fetched"
  },
  "snapshot_stability": {
    "unchanged_recipe_content": 10,
    "technical_html_changes_only": 8,
    "identical_html": 2,
    "changed_recipe_content": 0,
    "format_only_change": 0,
    "unresolved": 0
  },
  "extractor_data_preservation": {
    "lossless_recipes": 10,
    "ingredient_rows": 110,
    "instruction_entries": 70,
    "lost_ingredient_rows": 0,
    "added_ingredient_rows": 0,
    "modified_ingredient_rows": 0,
    "order_errors": 0,
    "lost_instruction_entries": 0,
    "added_instruction_entries": 0,
    "title_mutations": 0,
    "candidate_selection_problems": 0
  },
  "source_quality": {
    "ingredients": {
      "total_visible": 110,
      "total_json_ld": 110,
      "exact_matches": 65,
      "format_only_matches": 43,
      "exact_or_normalized_matches": 108,
      "quantity_differences": 0,
      "unit_differences": 0,
      "missing_notes": 2,
      "missing_rows": 0,
      "extra_rows": 0,
      "order_errors": 0,
      "group_heading_differences": 1,
      "supplementary_quantity_note_omissions": 1,
      "note": "Supplementary 1,5 kg omission counted as MISSING_NOTE, not a second row error; main quantity unchanged."
    },
    "instructions": {
      "complete": 9,
      "structure_only_differences": 1,
      "content_omissions": 0,
      "extra_content": 0,
      "order_errors": 0
    },
    "titles": {
      "clean": 5,
      "decorated": 5,
      "wrong": 0,
      "missing": 0
    }
  },
  "domains": {
    "www.mindmegette.hu": {
      "recipes": 5,
      "source_quality": {
        "GOOD": 0,
        "USABLE_WITH_ISSUES": 5,
        "POOR": 0
      },
      "visible_ingredients": 48,
      "missing_note_rows": 2,
      "group_heading_differences": 0
    },
    "www.bbcgoodfood.com": {
      "recipes": 5,
      "source_quality": {
        "GOOD": 4,
        "USABLE_WITH_ISSUES": 1,
        "POOR": 0
      },
      "visible_ingredients": 62,
      "missing_note_rows": 0,
      "group_heading_differences": 1
    }
  }
}
```

| ID | Source quality | Extractor | Ingredients | Instructions |
|---|---|---|---|---|
| 11 | USABLE_WITH_ISSUES | LOSSLESS | 7 | COMPLETE |
| 12 | USABLE_WITH_ISSUES | LOSSLESS | 14 | COMPLETE_WITH_STRUCTURE_DIFFERENCE |
| 13 | USABLE_WITH_ISSUES | LOSSLESS | 9 | COMPLETE |
| 14 | USABLE_WITH_ISSUES | LOSSLESS | 10 | COMPLETE |
| 15 | USABLE_WITH_ISSUES | LOSSLESS | 8 | COMPLETE |
| 16 | GOOD | LOSSLESS | 8 | COMPLETE |
| 17 | USABLE_WITH_ISSUES | LOSSLESS | 11 | COMPLETE |
| 18 | GOOD | LOSSLESS | 16 | COMPLETE |
| 19 | GOOD | LOSSLESS | 12 | COMPLETE |
| 20 | GOOD | LOSSLESS | 15 | COMPLETE |

## 11

URL: https://www.mindmegette.hu/recept/lecso

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Lecsó","json_ld":"Lecsó | Mindmegette.hu","verdict":"TITLE_DECORATION"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 40 dkg paradicsom | 40 dkg Paradicsom | FORMAT_DIFFERENCE |
| 2 | 80 dkg paprika | 80 dkg Paprika | FORMAT_DIFFERENCE |
| 3 | 2 fej hagyma | 2 fej Hagyma | FORMAT_DIFFERENCE |
| 4 | 5 dkg füstölt szalonna | 5 dkg Füstölt szalonna | FORMAT_DIFFERENCE |
| 5 | 2 ek olaj | 2 ek Olaj | FORMAT_DIFFERENCE |
| 6 | 1 ek pirospaprika | 1 ek Pirospaprika | FORMAT_DIFFERENCE |
| 7 | só | Só | FORMAT_DIFFERENCE |

Groups: []

Instructions: COMPLETE; visible blocks 4, JSON-LD steps 4, extracted entries 8, JSON-LD headings 4. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 4.

Extractor evidence: {"ingredients":{"expected_count":7,"actual_count":7,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 12

URL: https://www.mindmegette.hu/recept/toltott-kaposzta

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Töltött káposzta","json_ld":"Töltött káposzta | Mindmegette.hu","verdict":"TITLE_DECORATION"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 80 dkg savanyú káposzta | 80 dkg savanyú káposzta | MATCH |
| 2 | 8 darab savanyított káposztalevél | 8 darab savanyított káposztalevél | MATCH |
| 3 | 2 fej hagyma | 2 fej Hagyma | FORMAT_DIFFERENCE |
| 4 | 1 gerezd fokhagyma | 1 gerezd Fokhagyma | FORMAT_DIFFERENCE |
| 5 | 5 dkg füstölt szalonna | 5 dkg Füstölt szalonna | FORMAT_DIFFERENCE |
| 6 | 40 dkg darált sertéshús | 40 dkg darált sertéshús | MATCH |
| 7 | 2 kávéskanál édesnemes pirospaprika | 2 kávéskanál édesnemes pirospaprika | MATCH |
| 8 | 8 dkg rizs | 8 dkg Rizs | FORMAT_DIFFERENCE |
| 9 | 1 darab tojás | 1 darab Tojás | FORMAT_DIFFERENCE |
| 10 | 1 csipet őrölt köménymag | 1 csipet őrölt köménymag | MATCH |
| 11 | 1 mokkáskanál majoránna | 1 mokkáskanál Majoránna | FORMAT_DIFFERENCE |
| 12 | 2 evőkanál olaj | 2 evőkanál Olaj | FORMAT_DIFFERENCE |
| 13 | 2 evőkanál liszt | 2 evőkanál Liszt | FORMAT_DIFFERENCE |
| 14 | 2 dl tejföl | 2 dl Tejföl | FORMAT_DIFFERENCE |

Groups: []

Instructions: COMPLETE_WITH_STRUCTURE_DIFFERENCE; visible blocks 5, JSON-LD steps 1, extracted entries 1, JSON-LD headings 0. Five numbered visible paragraphs are one JSON-LD string; full ordered text is equal. Full ordered body comparison: equal. @VISIBLE reference count: 5.

Extractor evidence: {"ingredients":{"expected_count":14,"actual_count":14,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":1,"actual_count":1,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 13

URL: https://www.mindmegette.hu/recept/klasszikus-paprikas-krumpli

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Klasszikus paprikás krumpli","json_ld":"Klasszikus paprikás krumpli | Mindmegette.hu","verdict":"TITLE_DECORATION"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 1 kg burgonya | 1 kg Burgonya | FORMAT_DIFFERENCE |
| 2 | 1 db vöröshagyma | 1 db Vöröshagyma | FORMAT_DIFFERENCE |
| 3 | 15 dkg szárazkolbász | 15 dkg szárazkolbász | MATCH |
| 4 | 4 ek étolaj | 4 ek Étolaj | FORMAT_DIFFERENCE |
| 5 | 2 gerezd fokhagyma | 2 gerezd Fokhagyma | FORMAT_DIFFERENCE |
| 6 | 2 tk pirospaprika | 2 tk Pirospaprika | FORMAT_DIFFERENCE |
| 7 | só | Só | FORMAT_DIFFERENCE |
| 8 | bors | Bors | FORMAT_DIFFERENCE |
| 9 | friss petrezselyem | friss petrezselyem | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 3, JSON-LD steps 3, extracted entries 6, JSON-LD headings 3. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 3.

Extractor evidence: {"ingredients":{"expected_count":9,"actual_count":9,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":6,"actual_count":6,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 14

URL: https://www.mindmegette.hu/recept/hagyomanyos-szatmari-toltott-kaposzta

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Hagyományos szatmári töltött káposzta","json_ld":"Hagyományos szatmári töltött káposzta | Mindmegette.hu","verdict":"TITLE_DECORATION"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 1 kis fej hagyma | 1 kis fej Hagyma | FORMAT_DIFFERENCE |
| 2 | 5 dkg sertészsír | 5 dkg Sertészsír | FORMAT_DIFFERENCE |
| 3 | 50 dkg darált sertéshús | 50 dkg darált sertéshús | MATCH |
| 4 | 25 dkg rizs | 25 dkg Rizs | FORMAT_DIFFERENCE |
| 5 | só | Só | FORMAT_DIFFERENCE |
| 6 | bors | Bors | FORMAT_DIFFERENCE |
| 7 | 1 ek pirospaprika | 1 ek Pirospaprika | FORMAT_DIFFERENCE |
| 8 | 1 fej édes káposzta (1,5 kg) | 1 fej édes káposzta | MISSING_NOTE |
| 9 | 3 dl paradicsomlé (házi) | 3 dl paradicsomlé | MISSING_NOTE |
| 10 | 2 dl tejföl | 2 dl Tejföl | FORMAT_DIFFERENCE |

Groups: []

Instructions: COMPLETE; visible blocks 4, JSON-LD steps 4, extracted entries 8, JSON-LD headings 4. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 4.

Extractor evidence: {"ingredients":{"expected_count":10,"actual_count":10,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 15

URL: https://www.mindmegette.hu/recept/rakott-krumpli-magyarosan

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Rakott krumpli magyarosan","json_ld":"Rakott krumpli magyarosan  | Mindmegette.hu","verdict":"TITLE_DECORATION"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 50 dkg krumpli | 50 dkg Krumpli | FORMAT_DIFFERENCE |
| 2 | 1 fej vöröshagyma | 1 fej Vöröshagyma | FORMAT_DIFFERENCE |
| 3 | 6 db tojás | 6 db Tojás | FORMAT_DIFFERENCE |
| 4 | kolbász | Kolbász | FORMAT_DIFFERENCE |
| 5 | tejföl | Tejföl | FORMAT_DIFFERENCE |
| 6 | szalonna | Szalonna | FORMAT_DIFFERENCE |
| 7 | só | Só | FORMAT_DIFFERENCE |
| 8 | bors | Bors | FORMAT_DIFFERENCE |

Groups: []

Instructions: COMPLETE; visible blocks 1, JSON-LD steps 1, extracted entries 1, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 1.

Extractor evidence: {"ingredients":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":1,"actual_count":1,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 16

URL: https://www.bbcgoodfood.com/recipes/ultimate-spaghetti-carbonara-recipe

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: false.

Title: {"visible":"Ultimate spaghetti carbonara recipe","json_ld":"Ultimate spaghetti carbonara recipe","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 100g pancetta | 100g pancetta | MATCH |
| 2 | 50g pecorino cheese | 50g pecorino cheese | MATCH |
| 3 | 50g parmesan | 50g parmesan | MATCH |
| 4 | 3 large eggs | 3 large eggs | MATCH |
| 5 | 350g spaghetti | 350g spaghetti | MATCH |
| 6 | 2 plump garlic cloves peeled and left whole | 2 plump garlic cloves peeled and left whole | MATCH |
| 7 | 50g unsalted butter | 50g unsalted butter | MATCH |
| 8 | sea salt and freshly ground black pepper | sea salt and freshly ground black pepper | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 12, JSON-LD steps 12, extracted entries 12, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 12.

Extractor evidence: {"ingredients":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":12,"actual_count":12,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 17

URL: https://www.bbcgoodfood.com/recipes/classic-victoria-sandwich-recipe

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Classic Victoria sandwich recipe","json_ld":"Classic Victoria sandwich recipe","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 200g caster sugar | 200g caster sugar | MATCH |
| 2 | 200g softened butter | 200g softened butter | MATCH |
| 3 | 4 eggs beaten | 4 eggs beaten | MATCH |
| 4 | 200g self-raising flour | 200g self-raising flour | MATCH |
| 5 | 1 tsp baking powder | 1 tsp  baking powder | FORMAT_DIFFERENCE |
| 6 | 2 tbsp milk | 2 tbsp milk | MATCH |
| 7 | 100g butter softened | 100g butter softened | MATCH |
| 8 | 140g icing sugar sifted | 140g icing sugar sifted | MATCH |
| 9 | drop vanilla extract (optional) | drop vanilla extract (optional) | MATCH |
| 10 | half a 340g jar good-quality strawberry jam | half a 340g jar good-quality strawberry jam | MATCH |
| 11 | icing sugar to decorate | icing sugar to decorate | MATCH |

Groups: [{"before_row":7,"heading":"For the filling","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null}]

Instructions: COMPLETE; visible blocks 8, JSON-LD steps 8, extracted entries 8, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 8.

Extractor evidence: {"ingredients":{"expected_count":11,"actual_count":11,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 18

URL: https://www.bbcgoodfood.com/recipes/chilli-con-carne-recipe

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Chilli con carne recipe","json_ld":"Chilli con carne recipe","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 1 large onion | 1 large onion | MATCH |
| 2 | 1 red pepper | 1 red pepper | MATCH |
| 3 | 2 garlic cloves | 2 garlic cloves | MATCH |
| 4 | 1 tbsp oil | 1 tbsp oil | MATCH |
| 5 | 1 heaped tsp hot chilli powder (or 1 level tbsp if you only have mild) | 1 heaped tsp hot chilli powder (or 1 level tbsp if you only have mild) | MATCH |
| 6 | 1 tsp paprika | 1 tsp paprika | MATCH |
| 7 | 1 tsp ground cumin | 1 tsp ground cumin | MATCH |
| 8 | 500g lean minced beef | 500g lean minced beef | MATCH |
| 9 | 1 beef stock cube | 1 beef stock cube | MATCH |
| 10 | 400g can Mutti chopped tomatoes | 400g can Mutti chopped tomatoes | MATCH |
| 11 | ½ tsp dried marjoram | ½ tsp dried marjoram | MATCH |
| 12 | 1 tsp sugar (or add a thumbnail-sized piece of dark chocolate along with the beans instead, see tip) | 1 tsp sugar (or add a thumbnail-sized piece of dark chocolate along with the beans instead, see tip) | MATCH |
| 13 | 2 tbsp tomato purée | 2 tbsp tomato purée | MATCH |
| 14 | 410g can red kidney beans | 410g can red kidney beans | MATCH |
| 15 | plain boiled long grain rice to serve | plain boiled long grain rice to serve | MATCH |
| 16 | soured cream to serve | soured cream to serve | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 16, JSON-LD steps 16, extracted entries 16, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 16.

Extractor evidence: {"ingredients":{"expected_count":16,"actual_count":16,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":16,"actual_count":16,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 19

URL: https://www.bbcgoodfood.com/recipes/chicken-tikka-masala

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Chicken tikka masala","json_ld":"Chicken tikka masala","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 4 tbsp vegetable oil | 4 tbsp vegetable oil | MATCH |
| 2 | 25g butter | 25g butter | MATCH |
| 3 | 4 onions roughly chopped | 4 onions roughly chopped | MATCH |
| 4 | 6 tbsp chicken tikka masala paste (use shop-bought or make your own – see recipe, below) | 6 tbsp chicken tikka masala paste (use shop-bought or make your own – see recipe, below) | MATCH |
| 5 | 2 red peppers deseeded and cut into chunks | 2 red peppers deseeded and cut into chunks | MATCH |
| 6 | 8 boneless, skinless chicken breasts cut into 2.5cm cubes | 8 boneless, skinless chicken breasts cut into 2.5cm cubes | MATCH |
| 7 | 2 x 400g cans chopped tomatoes | 2 x 400g cans  chopped tomatoes | FORMAT_DIFFERENCE |
| 8 | 4 tbsp tomato purée | 4 tbsp tomato purée | MATCH |
| 9 | 2-3 tbsp mango chutney | 2-3 tbsp  mango chutney | FORMAT_DIFFERENCE |
| 10 | 150ml double cream | 150ml double cream | MATCH |
| 11 | 150ml natural yogurt | 150ml natural  yogurt | FORMAT_DIFFERENCE |
| 12 | chopped coriander leaves, to serve | chopped  coriander leaves, to serve | FORMAT_DIFFERENCE |

Groups: []

Instructions: COMPLETE; visible blocks 5, JSON-LD steps 5, extracted entries 5, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 5.

Extractor evidence: {"ingredients":{"expected_count":12,"actual_count":12,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":5,"actual_count":5,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 20

URL: https://www.bbcgoodfood.com/recipes/classic-lasagne

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: false.

Title: {"visible":"Easy classic lasagne","json_ld":"Easy classic lasagne","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 1 tbsp olive oil | 1 tbsp olive oil | MATCH |
| 2 | 2 rashers smoked streaky bacon | 2 rashers smoked streaky bacon | MATCH |
| 3 | 1 onion finely chopped | 1 onion finely chopped | MATCH |
| 4 | 1 celery stick, finely chopped | 1 celery stick, finely chopped | MATCH |
| 5 | 1 medium carrot grated | 1 medium carrot grated | MATCH |
| 6 | 2 garlic cloves finely chopped | 2 garlic cloves finely chopped | MATCH |
| 7 | 500g beef mince | 500g beef mince | MATCH |
| 8 | 1 tbsp tomato purée | 1 tbsp tomato purée | MATCH |
| 9 | 2 x 400g cans chopped tomatoes | 2 x 400g cans chopped tomatoes | MATCH |
| 10 | 1 tbsp clear honey | 1 tbsp clear honey | MATCH |
| 11 | 500g pack fresh egg lasagne sheets | 500g pack fresh egg lasagne sheets | MATCH |
| 12 | 400ml crème fraîche | 400ml crème fraîche | MATCH |
| 13 | 125g ball mozzarella roughly torn | 125g ball mozzarella roughly torn | MATCH |
| 14 | 50g freshly grated parmesan | 50g freshly grated parmesan | MATCH |
| 15 | large handful basil leaves torn (optional) | large handful basil leaves torn (optional) | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 5, JSON-LD steps 5, extracted entries 5, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 5.

Extractor evidence: {"ingredients":{"expected_count":15,"actual_count":15,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":5,"actual_count":5,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## Decision

B2.3 can use the preserved B2.1 input, with rows 14/8 and 14/9 marked as source errors and the 17 ingredient-group omission tracked separately. No extractor change is required. RecipeTextParser was not invoked. B2.0 references, snapshots, corpus and production code were not changed. B2.3 not started.
