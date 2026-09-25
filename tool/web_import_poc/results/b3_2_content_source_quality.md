# B3.2 – content/source quality, 11–20

Offline saved snapshots only. B3.0 DOM selectors reused; @VISIBLE resolved, full text checked without republication. Case/whitespace only ingredient comparison, no unit/quantity conversion. Source ingredient alignment manually reviewed. No parser/fetch or source correction. GOOD requires clean title and no structural/content differences; decoration alone is USABLE_WITH_ISSUES. Counts are specific to these frozen snapshots; DOM audit is not a browser rendering test.

## Separate metrics

```json
{
  "technical_extraction_success": {
    "success": 8,
    "total": 10,
    "percent": 80.0,
    "evidence": "Frozen B3.1 results; not re-fetched"
  },
  "snapshot_stability": {
    "unchanged_recipe_content": 8,
    "technical_html_changes_only": 2,
    "identical_html": 6,
    "changed_recipe_content": 0,
    "format_only_change": 0,
    "unresolved": 0
  },
  "extractor_data_preservation": {
    "lossless_recipes": 8,
    "ingredient_rows": 82,
    "instruction_entries": 47,
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
      "total_visible": 82,
      "total_json_ld": 82,
      "exact_matches": 81,
      "format_only_matches": 1,
      "exact_or_normalized_matches": 82,
      "quantity_differences": 0,
      "unit_differences": 0,
      "missing_notes": 0,
      "missing_rows": 0,
      "extra_rows": 0,
      "order_errors": 0,
      "group_heading_differences": 4
    },
    "instructions": {
      "complete": 8,
      "structure_only_differences": 0,
      "content_omissions": 0,
      "extra_content": 0,
      "order_errors": 0
    },
    "titles": {
      "clean": 8,
      "decorated": 0,
      "wrong": 0,
      "missing": 0
    }
  },
  "domains": {
    "www.bbcgoodfood.com": {
      "recipes": 8,
      "source_quality": {
        "GOOD": 6,
        "USABLE_WITH_ISSUES": 2,
        "POOR": 0
      },
      "visible_ingredients": 82,
      "missing_note_rows": 0,
      "group_heading_differences": 4
    }
  }
}
```

| ID | Source quality | Extractor | Ingredients | Instructions |
|---|---|---|---|---|
| 21 | GOOD | LOSSLESS | 11 | COMPLETE |
| 22 | GOOD | LOSSLESS | 6 | COMPLETE |
| 23 | GOOD | LOSSLESS | 13 | COMPLETE |
| 24 | GOOD | LOSSLESS | 8 | COMPLETE |
| 25 | USABLE_WITH_ISSUES | LOSSLESS | 8 | COMPLETE |
| 26 | GOOD | LOSSLESS | 9 | COMPLETE |
| 27 | GOOD | LOSSLESS | 8 | COMPLETE |
| 28 | USABLE_WITH_ISSUES | LOSSLESS | 19 | COMPLETE |

## 21

URL: https://www.bbcgoodfood.com/recipes/easy-chicken-curry

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Easy chicken curry","json_ld":"Easy chicken curry","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 2 tbsp sunflower oil | 2 tbsp sunflower oil | MATCH |
| 2 | 1 onion thinly sliced | 1 onion thinly sliced | MATCH |
| 3 | 2 garlic cloves crushed | 2 garlic cloves crushed | MATCH |
| 4 | thumb-sized piece of ginger grated | thumb-sized piece of ginger grated | MATCH |
| 5 | 6 chicken thighs boneless and skinless | 6 chicken thighs boneless and skinless | MATCH |
| 6 | 3 tbsp medium spice paste (tikka works well) | 3 tbsp medium spice paste (tikka works well) | MATCH |
| 7 | 400g can chopped tomatoes | 400g can chopped tomatoes | MATCH |
| 8 | 100g Greek yogurt | 100g Greek yogurt | MATCH |
| 9 | 1 small bunch of coriander leaves chopped | 1 small bunch of coriander leaves chopped | MATCH |
| 10 | 50g ground almonds | 50g ground almonds | MATCH |
| 11 | naan breads or cooked basmati rice, to serve | naan breads or cooked basmati rice, to serve | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 4, JSON-LD steps 4, extracted entries 4, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 4.

Extractor evidence: {"ingredients":{"expected_count":11,"actual_count":11,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":4,"actual_count":4,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 22

URL: https://www.bbcgoodfood.com/recipes/easy-pancakes

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: false.

Title: {"visible":"Easy pancakes","json_ld":"Easy pancakes","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 100g plain flour | 100g plain flour | MATCH |
| 2 | 2 large eggs | 2 large eggs | MATCH |
| 3 | 300ml milk | 300ml milk | MATCH |
| 4 | 1 tbsp sunflower or vegetable oil plus a little extra for frying | 1 tbsp sunflower or vegetable oil plus a little extra for frying | MATCH |
| 5 | lemon wedges to serve (optional) | lemon wedges to serve (optional) | MATCH |
| 6 | caster sugar to serve (optional) | caster sugar to serve (optional) | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 5, JSON-LD steps 5, extracted entries 5, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 5.

Extractor evidence: {"ingredients":{"expected_count":6,"actual_count":6,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":5,"actual_count":5,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 23

URL: https://www.bbcgoodfood.com/recipes/fish-pie-four-steps

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: false.

Title: {"visible":"Fish pie - in four steps","json_ld":"Fish pie - in four steps","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 400g skinless white fish fillet | 400g skinless white fish fillet | MATCH |
| 2 | 400g skinless smoked haddock fillet | 400g skinless smoked haddock fillet | MATCH |
| 3 | 600ml semi-skimmed milk | 600ml semi-skimmed milk | MATCH |
| 4 | 1 small onion quartered | 1 small onion quartered | MATCH |
| 5 | 4 cloves | 4 cloves | MATCH |
| 6 | 2 bay leaves | 2 bay leaves | MATCH |
| 7 | 4 eggs | 4 eggs | MATCH |
| 8 | small bunch parsley leaves only, chopped | small bunch parsley leaves only, chopped | MATCH |
| 9 | 100g butter | 100g butter | MATCH |
| 10 | 50g plain flour | 50g plain flour | MATCH |
| 11 | pinch freshly grated nutmeg | pinch freshly grated nutmeg | MATCH |
| 12 | 1kg floury potato peeled and cut into even-sized chunks | 1kg floury potato peeled and cut into even-sized chunks | MATCH |
| 13 | 50g cheddar grated | 50g cheddar grated | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 4, JSON-LD steps 4, extracted entries 4, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 4.

Extractor evidence: {"ingredients":{"expected_count":13,"actual_count":13,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":4,"actual_count":4,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 24

URL: https://www.bbcgoodfood.com/recipes/best-ever-chocolate-brownies-recipe

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: true.

Title: {"visible":"Best ever chocolate brownies recipe","json_ld":"Best ever chocolate brownies recipe","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 185g unsalted butter | 185g unsalted butter | MATCH |
| 2 | 185g best dark chocolate | 185g best dark chocolate | MATCH |
| 3 | 85g plain flour | 85g plain flour | MATCH |
| 4 | 40g cocoa powder | 40g cocoa powder | MATCH |
| 5 | 50g white chocolate | 50g white chocolate | MATCH |
| 6 | 50g milk chocolate | 50g milk chocolate | MATCH |
| 7 | 3 large eggs | 3 large eggs | MATCH |
| 8 | 275g golden caster sugar | 275g golden caster sugar | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 15, JSON-LD steps 15, extracted entries 15, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 15.

Extractor evidence: {"ingredients":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":15,"actual_count":15,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 25

URL: https://www.bbcgoodfood.com/recipes/best-apple-crumble

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: false.

Title: {"visible":"Easy apple crumble recipe","json_ld":"Easy apple crumble recipe","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 575g Bramley apple (3 medium apples), peeled, cored and sliced to 1cm thick | 575g Bramley apple (3 medium apples), peeled, cored and sliced to 1cm thick | MATCH |
| 2 | 2 tbsp golden caster sugar | 2 tbsp golden caster sugar | MATCH |
| 3 | 175g plain flour | 175g plain flour | MATCH |
| 4 | 110g golden caster sugar | 110g golden caster sugar | MATCH |
| 5 | 110g cold butter | 110g cold butter | MATCH |
| 6 | 1 tbsp rolled oats | 1 tbsp rolled oats | MATCH |
| 7 | 1 tbsp demerara sugar | 1 tbsp demerara sugar | MATCH |
| 8 | double cream clotted cream or custard, to serve | double cream clotted cream or custard, to serve | MATCH |

Groups: [{"before_row":1,"heading":"For the filling","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null},{"before_row":3,"heading":"For the crumble","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null},{"before_row":6,"heading":"For the topping (optional)","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null}]

Instructions: COMPLETE; visible blocks 8, JSON-LD steps 8, extracted entries 8, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 8.

Extractor evidence: {"ingredients":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 26

URL: https://www.bbcgoodfood.com/recipes/tomato-soup

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: false.

Title: {"visible":"Tomato soup","json_ld":"Tomato soup","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 1-1.25kg/2lb 4oz-2lb 12oz ripe tomatoes | 1-1.25kg/2lb 4oz-2lb 12oz ripe  tomatoes | FORMAT_DIFFERENCE |
| 2 | 1 medium onion | 1 medium onion | MATCH |
| 3 | 1 small carrot | 1 small carrot | MATCH |
| 4 | 1 celery stick | 1 celery stick | MATCH |
| 5 | 2 tbsp olive oil | 2 tbsp olive oil | MATCH |
| 6 | 2 squirts of tomato purée (about 2 tsp) | 2 squirts of tomato purée (about 2 tsp) | MATCH |
| 7 | a good pinch of sugar | a good pinch of sugar | MATCH |
| 8 | 2 bay leaves | 2 bay leaves | MATCH |
| 9 | 1.2 litres/2 pints hot vegetable stock (made with boiling water and 4 rounded tsp bouillon powder or 2 stock cubes) | 1.2 litres/2 pints hot vegetable stock (made with boiling water and 4 rounded tsp bouillon powder or 2 stock cubes) | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 6, JSON-LD steps 6, extracted entries 6, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 6.

Extractor evidence: {"ingredients":{"expected_count":9,"actual_count":9,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":6,"actual_count":6,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 27

URL: https://www.bbcgoodfood.com/recipes/real-tomato-soup

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: false.

Title: {"visible":"Real tomato soup","json_ld":"Real tomato soup","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 2 tbsp olive oil | 2 tbsp olive oil | MATCH |
| 2 | 1 onion chopped | 1 onion chopped | MATCH |
| 3 | 1 garlic clove finely chopped | 1 garlic clove finely chopped | MATCH |
| 4 | 1 tbsp tomato purée | 1 tbsp tomato purée | MATCH |
| 5 | 400g can chopped tomato | 400g can chopped tomato | MATCH |
| 6 | handful basil leaf | handful basil leaf | MATCH |
| 7 | pinch bicarbonate of soda | pinch bicarbonate of soda | MATCH |
| 8 | 600ml milk | 600ml milk | MATCH |

Groups: []

Instructions: COMPLETE; visible blocks 2, JSON-LD steps 2, extracted entries 2, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 2.

Extractor evidence: {"ingredients":{"expected_count":8,"actual_count":8,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":2,"actual_count":2,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## 28

URL: https://www.bbcgoodfood.com/recipes/chicken-chilli-con-carne

Snapshot: UNCHANGED_RECIPE_CONTENT. HTML changed: false.

Title: {"visible":"Chicken chilli con carne","json_ld":"Chicken chilli con carne","verdict":"CLEAN"}

| Row | Visible | JSON-LD | Verdict |
|---|---|---|---|
| 1 | 2 tbsp olive oil | 2 tbsp olive oil | MATCH |
| 2 | 1 onion sliced | 1 onion sliced | MATCH |
| 3 | 2 mixed peppers sliced (use red, yellow or orange peppers) | 2 mixed peppers sliced (use red, yellow or orange peppers) | MATCH |
| 4 | 2 large garlic cloves crushed | 2 large garlic cloves crushed | MATCH |
| 5 | 1 small bunch of coriander stalks finely chopped and leaves roughly chopped | 1 small bunch of coriander stalks finely chopped and leaves roughly chopped | MATCH |
| 6 | ½ tbsp ground coriander | ½ tbsp ground coriander | MATCH |
| 7 | 1 tbsp ground cumin | 1 tbsp ground cumin | MATCH |
| 8 | 1-2 tsp chipotle paste | 1-2 tsp chipotle paste | MATCH |
| 9 | 400g can chopped tomatoes | 400g can chopped tomatoes | MATCH |
| 10 | 1 tbsp tomato purée | 1 tbsp tomato purée | MATCH |
| 11 | 300ml chicken stock | 300ml chicken stock | MATCH |
| 12 | 1 small cinnamon stick | 1 small cinnamon stick | MATCH |
| 13 | 4 skinless chicken thighs bone-in | 4 skinless chicken thighs bone-in | MATCH |
| 14 | 400g can black beans | 400g can black beans | MATCH |
| 15 | 400g can kidney beans drained | 400g can kidney beans drained | MATCH |
| 16 | 1 tbsp red wine vinegar | 1 tbsp red wine vinegar | MATCH |
| 17 | 20g dark chocolate (at least 70% cocoa solids) | 20g dark chocolate (at least 70% cocoa solids) | MATCH |
| 18 | cooked rice or tortilla chips | cooked rice or tortilla chips | MATCH |
| 19 | guacamole and soured cream (optional) | guacamole and soured cream (optional) | MATCH |

Groups: [{"before_row":18,"heading":"To serve","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null}]

Instructions: COMPLETE; visible blocks 3, JSON-LD steps 3, extracted entries 3, JSON-LD headings 0. Step bodies equal in source order. Ordinal step labels are presentation, not extra cooking steps. Full ordered body comparison: equal. @VISIBLE reference count: 3.

Extractor evidence: {"ingredients":{"expected_count":19,"actual_count":19,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"instructions":{"expected_count":3,"actual_count":3,"lost":0,"added":0,"modified_positions":[],"order_error":false,"exact_ordered_equality":true},"title_mutation":false,"raw_ingredients_preserved":true,"raw_instructions_preserved":true,"candidate_selection_problem":false}

## Decision

B3.3 may use only 21–28. Ingredient-group omissions in 25 and 28 are source issues. 29–30 remain ACCESS_BLOCKED / UNRESOLVED_CONTENT, excluded from all content and parser denominators. No extractor change is required. RecipeTextParser was not invoked. B3.0 references, snapshots, corpus and production code were not changed. B3.3 not started.

## Access exclusions

[
  {
    "id": "29",
    "url": "https://www.foodnetwork.com/recipes/food-network-kitchen/classic-meatloaf-5484735",
    "http_status": 403,
    "response_bytes": 450,
    "status": "ACCESS_BLOCKED",
    "content_status": "UNRESOLVED_CONTENT",
    "usable_recipe_snapshot": false,
    "verified_ground_truth": false,
    "extractor_content_verdict": null,
    "note": "ACCESS / FETCH LIMITATION. Non-2xx body not retained by B3.1. Extraction skipped: zero candidates does not prove absence of JSON-LD. Excluded from content/source/extractor/parser denominators; retained as technical failure. No retry."
  },
  {
    "id": "30",
    "url": "https://www.foodnetwork.com/recipes/guacamole-recipe2-1956046",
    "http_status": 403,
    "response_bytes": 418,
    "status": "ACCESS_BLOCKED",
    "content_status": "UNRESOLVED_CONTENT",
    "usable_recipe_snapshot": false,
    "verified_ground_truth": false,
    "extractor_content_verdict": null,
    "note": "ACCESS / FETCH LIMITATION. Non-2xx body not retained by B3.1. Extraction skipped: zero candidates does not prove absence of JSON-LD. Excluded from content/source/extractor/parser denominators; retained as technical failure. No retry."
  }
]

Denominators: {
  "technical": 10,
  "source_quality_recipes": 8,
  "extractor_recipes": 8,
  "excluded_ids": [
    "29",
    "30"
  ]
}
