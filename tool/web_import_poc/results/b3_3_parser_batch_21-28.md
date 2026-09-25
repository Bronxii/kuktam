# B3.3 – RecipeTextParser benchmark, 21–28

Offline 21–28 only. Independent source-wording expectations and explicit reviewed unsupported primary measures. 4 absent group headings are source metadata only. No ingredient SOURCE_ERROR. Missing unspecified quantities use accepted 1 db fallback; warnings retained. Whole countable items use db, including cloves as spice (23/5). Garlic cloves and celery/cinnamon sticks treated as semantic unit decisions, consistent with Batch 2. Packaging after explicit grams remains a descriptor. Unsupported names scored against semantic ingredient-name expectation, not raw preservation; raw text is retained. Null quantity/unit metrics excluded and denominators explicit. No invented scores for absent quantity forms. Unsupported means unit or grammar, not supported-input parser error. Production warnings and audit classifications remain separate.

## Summary
```json
{
  "total": 82,
  "valid_source": 82,
  "source_errors": 0,
  "supported": 51,
  "correct_supported": 51,
  "parser_errors": 0,
  "unsupported_rows": 31,
  "unsupported_unit_rows": 27,
  "parser_limitation_rows": 4,
  "overall_valid_input_success_percent": 62.19512195121951,
  "supported_input_accuracy_percent": 100.0,
  "quantity_accuracy": {
    "correct": 72,
    "denominator": 73,
    "percent": 98.63013698630137,
    "not_applicable": 9
  },
  "explicit_quantity_accuracy": {
    "correct": 66,
    "denominator": 67,
    "percent": 98.50746268656717,
    "not_applicable": 9
  },
  "supported_unit_accuracy": {
    "correct": 51,
    "denominator": 51,
    "percent": 100.0,
    "not_applicable": 0
  },
  "explicit_supported_unit_accuracy": {
    "correct": 30,
    "denominator": 30,
    "percent": 100.0,
    "not_applicable": 0
  },
  "name_accuracy": {
    "correct": 51,
    "denominator": 82,
    "percent": 62.19512195121951,
    "not_applicable": 0
  },
  "supported_name_accuracy": {
    "correct": 51,
    "denominator": 51,
    "percent": 100.0,
    "not_applicable": 0
  },
  "silent_fallback_rows": 21,
  "silent_fallback_rate_percent": 25.609756097560975,
  "silent_fallback_affected_recipes": 6,
  "supported_quantity_accuracy": {
    "correct": 51,
    "denominator": 51,
    "percent": 100.0,
    "not_applicable": 0
  },
  "quantity_forms": {
    "integer": {
      "count": 66,
      "accuracy": {
        "correct": 65,
        "denominator": 66,
        "percent": 98.48484848484848,
        "not_applicable": 0
      }
    },
    "decimal": {
      "count": 0,
      "accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "comma_decimal": {
      "count": 0,
      "accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "slash_fraction": {
      "count": 0,
      "accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "unicode_fraction": {
      "count": 1,
      "accuracy": {
        "correct": 1,
        "denominator": 1,
        "percent": 100.0,
        "not_applicable": 0
      }
    },
    "mixed_fraction": {
      "count": 0,
      "accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "range": {
      "count": 2,
      "accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 2
      }
    },
    "multiplier": {
      "count": 0,
      "accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "textual": {
      "count": 6,
      "accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 6
      }
    },
    "missing": {
      "count": 6,
      "accuracy": {
        "correct": 6,
        "denominator": 6,
        "percent": 100.0,
        "not_applicable": 0
      }
    },
    "compound_alternative": {
      "count": 1,
      "accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 1
      }
    }
  },
  "warning_rows": 16,
  "unknown_unit_warning_rows": 0,
  "timing": {
    "avg_parser_ms_per_row": 0.0494390243902439,
    "avg_parser_ms_per_recipe": 1.077125,
    "batch_recipe_parser_ms": 8.617,
    "row_pass_parser_ms": 4.054,
    "method": "DESKTOP Dart JIT; one recipe pass plus independent row pass. Stopwatch excludes IO. First recipe includes cold/JIT cost. The two timings are separate, not interchangeable."
  }
}
```

## Per recipe
| ID | Rows | Supported | Correct | Unsupported (incl. grammar) | Errors | Silent | Overall success |
|---|---|---|---|---|---|---|---|
| 21 | 11 | 6 | 6 | 5 | 0 | 4 | 54.55% |
| 22 | 6 | 5 | 5 | 1 | 0 | 1 | 83.33% |
| 23 | 13 | 11 | 11 | 2 | 0 | 0 | 84.62% |
| 24 | 8 | 8 | 8 | 0 | 0 | 0 | 100.00% |
| 25 | 8 | 5 | 5 | 3 | 0 | 3 | 62.50% |
| 26 | 9 | 3 | 3 | 6 | 0 | 2 | 33.33% |
| 27 | 8 | 3 | 3 | 5 | 0 | 3 | 37.50% |
| 28 | 19 | 10 | 10 | 9 | 0 | 8 | 52.63% |

## Unsupported inventory
| Token/expression | Count | Warning rows | db | In name | Silent | Category |
|---|---|---|---|---|---|---|
| cloves | 3 | 0 | 3 | 3 | 3 | SEMANTIC_DECISION |
| good pinch | 1 | 1 | 1 | 1 | 0 | SEMANTIC_DECISION |
| handful | 1 | 1 | 1 | 1 | 0 | SEMANTIC_DECISION |
| litres/pints + alternative stock quantities | 1 | 1 | 1 | 1 | 0 | QUANTITY_GRAMMAR |
| pinch | 2 | 2 | 2 | 2 | 0 | SEMANTIC_DECISION |
| range + kg/lb/oz compound quantity | 1 | 1 | 1 | 1 | 0 | QUANTITY_GRAMMAR |
| range tsp | 1 | 1 | 1 | 1 | 0 | QUANTITY_GRAMMAR |
| small bunch | 3 | 1 | 3 | 3 | 2 | SEMANTIC_DECISION |
| squirts + alternative tsp | 1 | 1 | 1 | 1 | 0 | QUANTITY_GRAMMAR |
| stick | 2 | 0 | 2 | 2 | 2 | SEMANTIC_DECISION |
| tbsp | 14 | 0 | 14 | 14 | 14 | SIMPLE_ALIAS_CANDIDATE |
| thumb-sized piece | 1 | 1 | 1 | 1 | 0 | SEMANTIC_DECISION |

## Token coverage (including secondary notes)
```json
{
  "tsp": 3,
  "tbsp": 14,
  "cloves": 3,
  "clove": 1,
  "cans": 0,
  "can": 5,
  "tin": 0,
  "tins": 0,
  "handful": 1,
  "bunch": 3,
  "sprigs": 0,
  "slices": 0,
  "stick": 2,
  "piece": 1,
  "knob": 0,
  "rashers": 0,
  "optional": 3,
  "to serve": 4,
  "divided": 0,
  "half": 0,
  "quarter": 0,
  "dkg": 0,
  "dl": 0,
  "kk": 0
}
```
Absent forms have no benchmark evidence. ½ occurs once and its numeric value is preserved (0.5), while tbsp is unsupported. Compound kg/lb/oz and litres/pints expressions are limitations, not supported metric unit failures. Explicit dkg/dl/kk conversions do not occur. Optional/to serve text remains in ingredient names; absent group headings cannot be recovered.

## Row evidence
- **21/1** `2 tbsp sunflower oil` → 2.0 db | `tbsp sunflower oil`; raw quantity `2`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 2.0, "unit": null, "name": "sunflower oil", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/2** `1 onion thinly sliced` → 1.0 db | `onion thinly sliced`; raw quantity `1`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 1.0, "unit": "db", "name": "onion thinly sliced", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/3** `2 garlic cloves crushed` → 2.0 db | `garlic cloves crushed`; raw quantity `2`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 2.0, "unit": null, "name": "garlic crushed", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/4** `thumb-sized piece of ginger grated` → 1.0 db | `thumb-sized piece of ginger grated`; raw quantity `None`; production warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; silent fallback False; expected {"quantity": null, "unit": null, "name": "ginger grated", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/5** `6 chicken thighs boneless and skinless` → 6.0 db | `chicken thighs boneless and skinless`; raw quantity `6`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 6.0, "unit": "db", "name": "chicken thighs boneless and skinless", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/6** `3 tbsp medium spice paste (tikka works well)` → 3.0 db | `tbsp medium spice paste (tikka works well)`; raw quantity `3`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 3.0, "unit": null, "name": "medium spice paste (tikka works well)", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/7** `400g can chopped tomatoes` → 400.0 g | `can chopped tomatoes`; raw quantity `400`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 400.0, "unit": "g", "name": "can chopped tomatoes", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/8** `100g Greek yogurt` → 100.0 g | `Greek yogurt`; raw quantity `100`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 100.0, "unit": "g", "name": "Greek yogurt", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/9** `1 small bunch of coriander leaves chopped` → 1.0 db | `small bunch of coriander leaves chopped`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "coriander leaves chopped", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/10** `50g ground almonds` → 50.0 g | `ground almonds`; raw quantity `50`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 50.0, "unit": "g", "name": "ground almonds", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **21/11** `naan breads or cooked basmati rice, to serve` → 1.0 db | `naan breads or cooked basmati rice, to serve`; raw quantity `None`; production warnings ['missingQuantity']; **CORRECT**; silent fallback False; expected {"quantity": 1, "unit": "db", "name": "naan breads or cooked basmati rice, to serve", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **22/1** `100g plain flour` → 100.0 g | `plain flour`; raw quantity `100`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 100.0, "unit": "g", "name": "plain flour", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **22/2** `2 large eggs` → 2.0 db | `large eggs`; raw quantity `2`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 2.0, "unit": "db", "name": "large eggs", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **22/3** `300ml milk` → 300.0 ml | `milk`; raw quantity `300`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 300.0, "unit": "ml", "name": "milk", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **22/4** `1 tbsp sunflower or vegetable oil plus a little extra for frying` → 1.0 db | `tbsp sunflower or vegetable oil plus a little extra for frying`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "sunflower or vegetable oil plus a little extra for frying", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **22/5** `lemon wedges to serve (optional)` → 1.0 db | `lemon wedges to serve (optional)`; raw quantity `None`; production warnings ['missingQuantity']; **CORRECT**; silent fallback False; expected {"quantity": 1, "unit": "db", "name": "lemon wedges to serve (optional)", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **22/6** `caster sugar to serve (optional)` → 1.0 db | `caster sugar to serve (optional)`; raw quantity `None`; production warnings ['missingQuantity']; **CORRECT**; silent fallback False; expected {"quantity": 1, "unit": "db", "name": "caster sugar to serve (optional)", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/1** `400g skinless white fish fillet` → 400.0 g | `skinless white fish fillet`; raw quantity `400`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 400.0, "unit": "g", "name": "skinless white fish fillet", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/2** `400g skinless smoked haddock fillet` → 400.0 g | `skinless smoked haddock fillet`; raw quantity `400`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 400.0, "unit": "g", "name": "skinless smoked haddock fillet", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/3** `600ml semi-skimmed milk` → 600.0 ml | `semi-skimmed milk`; raw quantity `600`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 600.0, "unit": "ml", "name": "semi-skimmed milk", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/4** `1 small onion quartered` → 1.0 db | `small onion quartered`; raw quantity `1`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 1.0, "unit": "db", "name": "small onion quartered", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/5** `4 cloves` → 4.0 db | `cloves`; raw quantity `4`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 4.0, "unit": "db", "name": "cloves", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/6** `2 bay leaves` → 2.0 db | `bay leaves`; raw quantity `2`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 2.0, "unit": "db", "name": "bay leaves", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/7** `4 eggs` → 4.0 db | `eggs`; raw quantity `4`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 4.0, "unit": "db", "name": "eggs", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/8** `small bunch parsley leaves only, chopped` → 1.0 db | `small bunch parsley leaves only, chopped`; raw quantity `None`; production warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; silent fallback False; expected {"quantity": null, "unit": null, "name": "parsley leaves only, chopped", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/9** `100g butter` → 100.0 g | `butter`; raw quantity `100`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 100.0, "unit": "g", "name": "butter", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/10** `50g plain flour` → 50.0 g | `plain flour`; raw quantity `50`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 50.0, "unit": "g", "name": "plain flour", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/11** `pinch freshly grated nutmeg` → 1.0 db | `pinch freshly grated nutmeg`; raw quantity `None`; production warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; silent fallback False; expected {"quantity": null, "unit": null, "name": "freshly grated nutmeg", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/12** `1kg floury potato peeled and cut into even-sized chunks` → 1.0 kg | `floury potato peeled and cut into even-sized chunks`; raw quantity `1`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 1.0, "unit": "kg", "name": "floury potato peeled and cut into even-sized chunks", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **23/13** `50g cheddar grated` → 50.0 g | `cheddar grated`; raw quantity `50`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 50.0, "unit": "g", "name": "cheddar grated", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **24/1** `185g unsalted butter` → 185.0 g | `unsalted butter`; raw quantity `185`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 185.0, "unit": "g", "name": "unsalted butter", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **24/2** `185g best dark chocolate` → 185.0 g | `best dark chocolate`; raw quantity `185`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 185.0, "unit": "g", "name": "best dark chocolate", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **24/3** `85g plain flour` → 85.0 g | `plain flour`; raw quantity `85`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 85.0, "unit": "g", "name": "plain flour", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **24/4** `40g cocoa powder` → 40.0 g | `cocoa powder`; raw quantity `40`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 40.0, "unit": "g", "name": "cocoa powder", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **24/5** `50g white chocolate` → 50.0 g | `white chocolate`; raw quantity `50`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 50.0, "unit": "g", "name": "white chocolate", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **24/6** `50g milk chocolate` → 50.0 g | `milk chocolate`; raw quantity `50`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 50.0, "unit": "g", "name": "milk chocolate", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **24/7** `3 large eggs` → 3.0 db | `large eggs`; raw quantity `3`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 3.0, "unit": "db", "name": "large eggs", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **24/8** `275g golden caster sugar` → 275.0 g | `golden caster sugar`; raw quantity `275`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 275.0, "unit": "g", "name": "golden caster sugar", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **25/1** `575g Bramley apple (3 medium apples), peeled, cored and sliced to 1cm thick` → 575.0 g | `Bramley apple (3 medium apples), peeled, cored and sliced to 1cm thick`; raw quantity `575`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 575.0, "unit": "g", "name": "Bramley apple (3 medium apples), peeled, cored and sliced to 1cm thick", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **25/2** `2 tbsp golden caster sugar` → 2.0 db | `tbsp golden caster sugar`; raw quantity `2`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 2.0, "unit": null, "name": "golden caster sugar", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **25/3** `175g plain flour` → 175.0 g | `plain flour`; raw quantity `175`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 175.0, "unit": "g", "name": "plain flour", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **25/4** `110g golden caster sugar` → 110.0 g | `golden caster sugar`; raw quantity `110`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 110.0, "unit": "g", "name": "golden caster sugar", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **25/5** `110g cold butter` → 110.0 g | `cold butter`; raw quantity `110`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 110.0, "unit": "g", "name": "cold butter", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **25/6** `1 tbsp rolled oats` → 1.0 db | `tbsp rolled oats`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "rolled oats", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **25/7** `1 tbsp demerara sugar` → 1.0 db | `tbsp demerara sugar`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "demerara sugar", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **25/8** `double cream clotted cream or custard, to serve` → 1.0 db | `double cream clotted cream or custard, to serve`; raw quantity `None`; production warnings ['missingQuantity']; **CORRECT**; silent fallback False; expected {"quantity": 1, "unit": "db", "name": "double cream clotted cream or custard, to serve", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/1** `1-1.25kg/2lb 4oz-2lb 12oz ripe  tomatoes` → 1.0 db | `1-1.25kg/2lb 4oz-2lb 12oz ripe  tomatoes`; raw quantity `None`; production warnings ['missingQuantity']; **PARSER_LIMITATION**; silent fallback False; expected {"quantity": null, "unit": null, "name": "ripe tomatoes", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/2** `1 medium onion` → 1.0 db | `medium onion`; raw quantity `1`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 1.0, "unit": "db", "name": "medium onion", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/3** `1 small carrot` → 1.0 db | `small carrot`; raw quantity `1`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 1.0, "unit": "db", "name": "small carrot", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/4** `1 celery stick` → 1.0 db | `celery stick`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "celery", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/5** `2 tbsp olive oil` → 2.0 db | `tbsp olive oil`; raw quantity `2`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 2.0, "unit": null, "name": "olive oil", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/6** `2 squirts of tomato purée (about 2 tsp)` → None db | `2 squirts of tomato purée (about 2 tsp)`; raw quantity `None`; production warnings ['ambiguousIngredient']; **PARSER_LIMITATION**; silent fallback False; expected {"quantity": 2.0, "unit": null, "name": "tomato purée (about 2 tsp)", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/7** `a good pinch of sugar` → 1.0 db | `a good pinch of sugar`; raw quantity `None`; production warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; silent fallback False; expected {"quantity": null, "unit": null, "name": "sugar", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/8** `2 bay leaves` → 2.0 db | `bay leaves`; raw quantity `2`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 2.0, "unit": "db", "name": "bay leaves", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **26/9** `1.2 litres/2 pints hot vegetable stock (made with boiling water and 4 rounded tsp bouillon powder or 2 stock cubes)` → None db | `1.2 litres/2 pints hot vegetable stock (made with boiling water and 4 rounded tsp bouillon powder or 2 stock cubes)`; raw quantity `None`; production warnings ['ambiguousIngredient']; **PARSER_LIMITATION**; silent fallback False; expected {"quantity": null, "unit": null, "name": "hot vegetable stock (made with boiling water and 4 rounded tsp bouillon powder or 2 stock cubes)", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **27/1** `2 tbsp olive oil` → 2.0 db | `tbsp olive oil`; raw quantity `2`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 2.0, "unit": null, "name": "olive oil", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **27/2** `1 onion chopped` → 1.0 db | `onion chopped`; raw quantity `1`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 1.0, "unit": "db", "name": "onion chopped", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **27/3** `1 garlic clove finely chopped` → 1.0 db | `garlic clove finely chopped`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "garlic finely chopped", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **27/4** `1 tbsp tomato purée` → 1.0 db | `tbsp tomato purée`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "tomato purée", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **27/5** `400g can chopped tomato` → 400.0 g | `can chopped tomato`; raw quantity `400`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 400.0, "unit": "g", "name": "can chopped tomato", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **27/6** `handful basil leaf` → 1.0 db | `handful basil leaf`; raw quantity `None`; production warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; silent fallback False; expected {"quantity": null, "unit": null, "name": "basil leaf", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **27/7** `pinch bicarbonate of soda` → 1.0 db | `pinch bicarbonate of soda`; raw quantity `None`; production warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; silent fallback False; expected {"quantity": null, "unit": null, "name": "bicarbonate of soda", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **27/8** `600ml milk` → 600.0 ml | `milk`; raw quantity `600`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 600.0, "unit": "ml", "name": "milk", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/1** `2 tbsp olive oil` → 2.0 db | `tbsp olive oil`; raw quantity `2`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 2.0, "unit": null, "name": "olive oil", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/2** `1 onion sliced` → 1.0 db | `onion sliced`; raw quantity `1`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 1.0, "unit": "db", "name": "onion sliced", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/3** `2 mixed peppers sliced (use red, yellow or orange peppers)` → 2.0 db | `mixed peppers sliced (use red, yellow or orange peppers)`; raw quantity `2`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 2.0, "unit": "db", "name": "mixed peppers sliced (use red, yellow or orange peppers)", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/4** `2 large garlic cloves crushed` → 2.0 db | `large garlic cloves crushed`; raw quantity `2`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 2.0, "unit": null, "name": "large garlic crushed", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/5** `1 small bunch of coriander stalks finely chopped and leaves roughly chopped` → 1.0 db | `small bunch of coriander stalks finely chopped and leaves roughly chopped`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "coriander stalks finely chopped and leaves roughly chopped", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/6** `½ tbsp ground coriander` → 0.5 db | `tbsp ground coriander`; raw quantity `½`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 0.5, "unit": null, "name": "ground coriander", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/7** `1 tbsp ground cumin` → 1.0 db | `tbsp ground cumin`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "ground cumin", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/8** `1-2 tsp chipotle paste` → 1.0 db | `1-2 tsp chipotle paste`; raw quantity `None`; production warnings ['missingQuantity']; **PARSER_LIMITATION**; silent fallback False; expected {"quantity": null, "unit": null, "name": "chipotle paste", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/9** `400g can chopped tomatoes` → 400.0 g | `can chopped tomatoes`; raw quantity `400`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 400.0, "unit": "g", "name": "can chopped tomatoes", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/10** `1 tbsp tomato purée` → 1.0 db | `tbsp tomato purée`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "tomato purée", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/11** `300ml chicken stock` → 300.0 ml | `chicken stock`; raw quantity `300`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 300.0, "unit": "ml", "name": "chicken stock", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/12** `1 small cinnamon stick` → 1.0 db | `small cinnamon stick`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "small cinnamon", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/13** `4 skinless chicken thighs bone-in` → 4.0 db | `skinless chicken thighs bone-in`; raw quantity `4`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 4.0, "unit": "db", "name": "skinless chicken thighs bone-in", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/14** `400g can black beans` → 400.0 g | `can black beans`; raw quantity `400`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 400.0, "unit": "g", "name": "can black beans", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/15** `400g can kidney beans drained` → 400.0 g | `can kidney beans drained`; raw quantity `400`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 400.0, "unit": "g", "name": "can kidney beans drained", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/16** `1 tbsp red wine vinegar` → 1.0 db | `tbsp red wine vinegar`; raw quantity `1`; production warnings []; **UNSUPPORTED_UNIT**; silent fallback True; expected {"quantity": 1.0, "unit": null, "name": "red wine vinegar", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/17** `20g dark chocolate (at least 70% cocoa solids)` → 20.0 g | `dark chocolate (at least 70% cocoa solids)`; raw quantity `20`; production warnings []; **CORRECT**; silent fallback False; expected {"quantity": 20.0, "unit": "g", "name": "dark chocolate (at least 70% cocoa solids)", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/18** `cooked rice or tortilla chips` → 1.0 db | `cooked rice or tortilla chips`; raw quantity `None`; production warnings ['missingQuantity']; **CORRECT**; silent fallback False; expected {"quantity": 1, "unit": "db", "name": "cooked rice or tortilla chips", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.
- **28/19** `guacamole and soured cream (optional)` → 1.0 db | `guacamole and soured cream (optional)`; raw quantity `None`; production warnings ['missingQuantity']; **CORRECT**; silent fallback False; expected {"quantity": 1, "unit": "db", "name": "guacamole and soured cream (optional)", "note": "Null = unsupported semantic quantity/unit, not expected null parser output."}.

## Quantity interpretation
The one explicit numeric mismatch is 26/6: 2 squirts with alternative (about 2 tsp) produces ambiguousIngredient and null quantity. It belongs to PARSER_LIMITATION, not supported-input error. The 1.2 decimal occurs only inside a compound litres/pints expression; the zero standalone decimal count does not mean that no decimal characters appear. Semantic unsupported names retain all original words but are not normalized ingredient-only names.

## Decision
No production parser change is needed before a supervised B3.4 POC simulation. Carry all unsupported classifications into explicit POC review warnings, including silent fallbacks. This is not approval for unattended production import. 29–30: NOT_TESTED_DUE_TO_ACCESS_BLOCK (HTTP 403), absent from every parser denominator. B3.4 not started. No network or production changes.
