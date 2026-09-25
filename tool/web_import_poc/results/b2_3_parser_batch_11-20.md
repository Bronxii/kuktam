# B2.3 – RecipeTextParser compatibility, 11–20

Offline 11–20 only. Independent source-wording oracle: leading quantity and reviewed supported-unit arithmetic; explicit unsupported semantic phrase inventory. No production normalizer used as oracle. Two SOURCE_ERROR rows excluded from every accuracy denominator. Null metric is not supported/measurable, not correct. Missing quantities use accepted 1 db fallback, not source-provided quantity. Primary gram/ml quantities stay supported even with can/pack/ball descriptors; whole eggs, onions, stock cubes use db. Name fidelity compares case/whitespace only, retains optional/to serve/other notes. Group heading omission is source-level only, never injected as an ingredient. Secondary mentions (alternative tbsp, thumbnail-sized piece) retained as notes. This is not automatic English recipe support.

```json
{
  "total": 110,
  "source_errors": 2,
  "valid_source": 108,
  "correct": 73,
  "parser_errors": 0,
  "unsupported": 35,
  "overall_accuracy_percent": 67.5925925925926,
  "supported_input_accuracy": {
    "correct": 73,
    "denominator": 73,
    "percent": 100.0
  },
  "quantity_accuracy": {
    "correct": 101,
    "denominator": 102,
    "percent": 99.01960784313725,
    "not_applicable": 6
  },
  "explicit_quantity_accuracy": {
    "correct": 85,
    "denominator": 86,
    "percent": 98.83720930232558,
    "not_applicable": 6
  },
  "supported_unit_accuracy": {
    "correct": 73,
    "denominator": 73,
    "percent": 100.0,
    "not_applicable": 0
  },
  "explicit_supported_unit_accuracy": {
    "correct": 47,
    "denominator": 47,
    "percent": 100.0,
    "not_applicable": 0
  },
  "name_accuracy": {
    "correct": 74,
    "denominator": 108,
    "percent": 68.51851851851852,
    "not_applicable": 0
  },
  "supported_name_accuracy": {
    "correct": 73,
    "denominator": 73,
    "percent": 100.0,
    "not_applicable": 0
  },
  "warning_rows": 24,
  "unknown_unit_warning_rows": 1,
  "unit_phrase_in_name_rows": 35,
  "supported_normalization_rows": 18,
  "quantity_forms": {
    "integer": {
      "count": 87,
      "valid_source_accuracy": {
        "correct": 84,
        "denominator": 85,
        "percent": 98.82352941176471,
        "not_applicable": 0
      }
    },
    "decimal": {
      "count": 0,
      "valid_source_accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "comma_decimal": {
      "count": 0,
      "valid_source_accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "slash_fraction": {
      "count": 0,
      "valid_source_accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "unicode_fraction": {
      "count": 1,
      "valid_source_accuracy": {
        "correct": 1,
        "denominator": 1,
        "percent": 100.0,
        "not_applicable": 0
      }
    },
    "mixed_fraction": {
      "count": 0,
      "valid_source_accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 0
      }
    },
    "range": {
      "count": 1,
      "valid_source_accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 1
      }
    },
    "multiplier": {
      "count": 2,
      "valid_source_accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 2
      }
    },
    "missing": {
      "count": 16,
      "valid_source_accuracy": {
        "correct": 16,
        "denominator": 16,
        "percent": 100.0,
        "not_applicable": 0
      }
    },
    "textual": {
      "count": 3,
      "valid_source_accuracy": {
        "correct": 0,
        "denominator": 0,
        "percent": null,
        "not_applicable": 3
      }
    }
  },
  "domains": {
    "www.bbcgoodfood.com": {
      "total": 62,
      "source_errors": 0,
      "valid_source": 62,
      "correct": 36,
      "parser_errors": 0,
      "unsupported": 26,
      "overall_accuracy_percent": 58.064516129032256,
      "supported_input_accuracy": {
        "correct": 36,
        "denominator": 36,
        "percent": 100.0
      },
      "quantity_accuracy": {
        "correct": 55,
        "denominator": 56,
        "percent": 98.21428571428571,
        "not_applicable": 6
      },
      "explicit_quantity_accuracy": {
        "correct": 50,
        "denominator": 51,
        "percent": 98.03921568627452,
        "not_applicable": 6
      },
      "supported_unit_accuracy": {
        "correct": 36,
        "denominator": 36,
        "percent": 100.0,
        "not_applicable": 0
      },
      "explicit_supported_unit_accuracy": {
        "correct": 21,
        "denominator": 21,
        "percent": 100.0,
        "not_applicable": 0
      },
      "name_accuracy": {
        "correct": 36,
        "denominator": 62,
        "percent": 58.064516129032256,
        "not_applicable": 0
      },
      "supported_name_accuracy": {
        "correct": 36,
        "denominator": 36,
        "percent": 100.0,
        "not_applicable": 0
      }
    },
    "www.mindmegette.hu": {
      "total": 48,
      "source_errors": 2,
      "valid_source": 46,
      "correct": 37,
      "parser_errors": 0,
      "unsupported": 9,
      "overall_accuracy_percent": 80.43478260869566,
      "supported_input_accuracy": {
        "correct": 37,
        "denominator": 37,
        "percent": 100.0
      },
      "quantity_accuracy": {
        "correct": 46,
        "denominator": 46,
        "percent": 100.0,
        "not_applicable": 0
      },
      "explicit_quantity_accuracy": {
        "correct": 35,
        "denominator": 35,
        "percent": 100.0,
        "not_applicable": 0
      },
      "supported_unit_accuracy": {
        "correct": 37,
        "denominator": 37,
        "percent": 100.0,
        "not_applicable": 0
      },
      "explicit_supported_unit_accuracy": {
        "correct": 26,
        "denominator": 26,
        "percent": 100.0,
        "not_applicable": 0
      },
      "name_accuracy": {
        "correct": 38,
        "denominator": 46,
        "percent": 82.6086956521739,
        "not_applicable": 0
      },
      "supported_name_accuracy": {
        "correct": 37,
        "denominator": 37,
        "percent": 100.0,
        "not_applicable": 0
      }
    }
  },
  "timing": {
    "avg_parser_ms_per_ingredient": 0.04194545454545454,
    "avg_parser_ms_per_recipe": 1.08,
    "batch_recipe_parser_ms": 10.8,
    "row_pass_parser_ms": 4.614,
    "all_calls_parser_ms": 15.414,
    "method": "One desktop Dart JIT pass; recipe pass then separate row calls. First recipe includes cold/JIT cost; IO excluded. Recipe and row times are separate measurements."
  }
}
```

## Recipe results

| ID | Valid | Correct | Parser error | Unsupported | Supported accuracy |
|---|---|---|---|---|---|
| 11 | 7 | 6 | 0 | 1 | 6/6 |
| 12 | 14 | 9 | 0 | 5 | 9/9 |
| 13 | 9 | 8 | 0 | 1 | 8/8 |
| 14 | 8 | 7 | 0 | 1 | 7/7 |
| 15 | 8 | 7 | 0 | 1 | 7/7 |
| 16 | 8 | 7 | 0 | 1 | 7/7 |
| 17 | 11 | 7 | 0 | 4 | 7/7 |
| 18 | 16 | 8 | 0 | 8 | 8/8 |
| 19 | 12 | 7 | 0 | 5 | 7/7 |
| 20 | 15 | 7 | 0 | 8 | 7/7 |

## Unsupported primary measures

| Phrase | Rows (all/valid) | Warning rows | db fallback | Unit/phrase retained in name |
|---|---|---|---|---|
| 2 x 400g cans | 2/2 | 2 | 2 | 2 |
| cloves | 3/3 | 0 | 3 | 3 |
| csipet | 1/1 | 1 | 1 | 0 |
| drop | 1/1 | 1 | 1 | 1 |
| fej | 4/3 | 0 | 4 | 4 |
| gerezd | 2/2 | 0 | 2 | 2 |
| half a … jar | 1/1 | 1 | 1 | 1 |
| heaped tsp; alternative level tbsp | 1/1 | 1 | 1 | 1 |
| kis fej | 1/1 | 0 | 1 | 1 |
| kávéskanál | 1/1 | 0 | 1 | 1 |
| large handful | 1/1 | 1 | 1 | 1 |
| mokkáskanál | 1/1 | 0 | 1 | 1 |
| range tbsp | 1/1 | 1 | 1 | 1 |
| rashers | 1/1 | 0 | 1 | 1 |
| stick | 1/1 | 0 | 1 | 1 |
| tbsp | 9/9 | 0 | 9 | 9 |
| tsp | 5/5 | 0 | 5 | 5 |

## Requested English token coverage (rows containing token, including notes)

```json
{
  "g": 21,
  "kg": 1,
  "ml": 3,
  "l": 8,
  "tsp": 6,
  "tbsp": 11,
  "oz": 0,
  "lb": 0,
  "cup": 0,
  "cans": 2,
  "cloves": 3,
  "rashers": 1,
  "bunch": 0,
  "handful": 1,
  "slices": 0,
  "sticks": 0,
  "sprigs": 0,
  "knob": 0,
  "piece": 1,
  "thumb-sized piece": 0,
  "optional": 2,
  "to serve": 3,
  "divided": 0
}
```

Absent tokens have no corpus evidence; no synthetic accuracy claim. `stick` occurs once, `sticks` zero. `thumbnail-sized piece` is a secondary alternative note, not primary ingredient quantity. `can`/`pack`/`ball` after explicit gram weights are retained descriptors.

## Per-row evidence

- **11/1** `40 dkg Paradicsom` → `Paradicsom` | 400.0 g; raw quantity `40`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Paradicsom", "quantity": 400.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **11/2** `80 dkg Paprika` → `Paprika` | 800.0 g; raw quantity `80`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Paprika", "quantity": 800.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **11/3** `2 fej Hagyma` → `fej Hagyma` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "Hagyma", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **11/4** `5 dkg Füstölt szalonna` → `Füstölt szalonna` | 50.0 g; raw quantity `5`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Füstölt szalonna", "quantity": 50.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **11/5** `2 ek Olaj` → `Olaj` | 2.0 ek; raw quantity `2`; warnings []; **CORRECT**; expected {"name": "Olaj", "quantity": 2.0, "unit": "ek", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **11/6** `1 ek Pirospaprika` → `Pirospaprika` | 1.0 ek; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "Pirospaprika", "quantity": 1.0, "unit": "ek", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **11/7** `Só` → `Só` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Só", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/1** `80 dkg savanyú káposzta` → `savanyú káposzta` | 800.0 g; raw quantity `80`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "savanyú káposzta", "quantity": 800.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/2** `8 darab savanyított káposztalevél` → `savanyított káposztalevél` | 8.0 db; raw quantity `8`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "savanyított káposztalevél", "quantity": 8.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/3** `2 fej Hagyma` → `fej Hagyma` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "Hagyma", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/4** `1 gerezd Fokhagyma` → `gerezd Fokhagyma` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "Fokhagyma", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/5** `5 dkg Füstölt szalonna` → `Füstölt szalonna` | 50.0 g; raw quantity `5`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Füstölt szalonna", "quantity": 50.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/6** `40 dkg darált sertéshús` → `darált sertéshús` | 400.0 g; raw quantity `40`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "darált sertéshús", "quantity": 400.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/7** `2 kávéskanál édesnemes pirospaprika` → `kávéskanál édesnemes pirospaprika` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "édesnemes pirospaprika", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/8** `8 dkg Rizs` → `Rizs` | 80.0 g; raw quantity `8`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Rizs", "quantity": 80.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/9** `1 darab Tojás` → `Tojás` | 1.0 db; raw quantity `1`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Tojás", "quantity": 1.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/10** `1 csipet őrölt köménymag` → `őrölt köménymag` | 1.0 db; raw quantity `1`; warnings ['unknownUnit']; **UNSUPPORTED_UNIT**; expected {"name": "őrölt köménymag", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/11** `1 mokkáskanál Majoránna` → `mokkáskanál Majoránna` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "Majoránna", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/12** `2 evőkanál Olaj` → `Olaj` | 2.0 ek; raw quantity `2`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Olaj", "quantity": 2.0, "unit": "ek", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/13** `2 evőkanál Liszt` → `Liszt` | 2.0 ek; raw quantity `2`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Liszt", "quantity": 2.0, "unit": "ek", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **12/14** `2 dl Tejföl` → `Tejföl` | 200.0 ml; raw quantity `2`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Tejföl", "quantity": 200.0, "unit": "ml", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/1** `1 kg Burgonya` → `Burgonya` | 1.0 kg; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "Burgonya", "quantity": 1.0, "unit": "kg", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/2** `1 db Vöröshagyma` → `Vöröshagyma` | 1.0 db; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "Vöröshagyma", "quantity": 1.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/3** `15 dkg szárazkolbász` → `szárazkolbász` | 150.0 g; raw quantity `15`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "szárazkolbász", "quantity": 150.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/4** `4 ek Étolaj` → `Étolaj` | 4.0 ek; raw quantity `4`; warnings []; **CORRECT**; expected {"name": "Étolaj", "quantity": 4.0, "unit": "ek", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/5** `2 gerezd Fokhagyma` → `gerezd Fokhagyma` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "Fokhagyma", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/6** `2 tk Pirospaprika` → `Pirospaprika` | 2.0 tk; raw quantity `2`; warnings []; **CORRECT**; expected {"name": "Pirospaprika", "quantity": 2.0, "unit": "tk", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/7** `Só` → `Só` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Só", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/8** `Bors` → `Bors` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Bors", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **13/9** `friss petrezselyem` → `friss petrezselyem` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "friss petrezselyem", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/1** `1 kis fej Hagyma` → `kis fej Hagyma` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "Hagyma", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/2** `5 dkg Sertészsír` → `Sertészsír` | 50.0 g; raw quantity `5`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Sertészsír", "quantity": 50.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/3** `50 dkg darált sertéshús` → `darált sertéshús` | 500.0 g; raw quantity `50`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "darált sertéshús", "quantity": 500.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/4** `25 dkg Rizs` → `Rizs` | 250.0 g; raw quantity `25`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Rizs", "quantity": 250.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/5** `Só` → `Só` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Só", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/6** `Bors` → `Bors` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Bors", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/7** `1 ek Pirospaprika` → `Pirospaprika` | 1.0 ek; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "Pirospaprika", "quantity": 1.0, "unit": "ek", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/8** `1 fej édes káposzta` → `fej édes káposzta` | 1.0 db; raw quantity `1`; warnings []; **SOURCE_ERROR**; expected {"name": "édes káposzta", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/9** `3 dl paradicsomlé` → `paradicsomlé` | 300.0 ml; raw quantity `3`; warnings []; **SOURCE_ERROR**; expected {"name": "paradicsomlé", "quantity": 300.0, "unit": "ml", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **14/10** `2 dl Tejföl` → `Tejföl` | 200.0 ml; raw quantity `2`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Tejföl", "quantity": 200.0, "unit": "ml", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **15/1** `50 dkg Krumpli` → `Krumpli` | 500.0 g; raw quantity `50`; warnings []; **SUPPORTED_NORMALIZATION**; expected {"name": "Krumpli", "quantity": 500.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **15/2** `1 fej Vöröshagyma` → `fej Vöröshagyma` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "Vöröshagyma", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **15/3** `6 db Tojás` → `Tojás` | 6.0 db; raw quantity `6`; warnings []; **CORRECT**; expected {"name": "Tojás", "quantity": 6.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **15/4** `Kolbász` → `Kolbász` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Kolbász", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **15/5** `Tejföl` → `Tejföl` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Tejföl", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **15/6** `Szalonna` → `Szalonna` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Szalonna", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **15/7** `Só` → `Só` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Só", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **15/8** `Bors` → `Bors` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "Bors", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **16/1** `100g pancetta` → `pancetta` | 100.0 g; raw quantity `100`; warnings []; **CORRECT**; expected {"name": "pancetta", "quantity": 100.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **16/2** `50g pecorino cheese` → `pecorino cheese` | 50.0 g; raw quantity `50`; warnings []; **CORRECT**; expected {"name": "pecorino cheese", "quantity": 50.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **16/3** `50g parmesan` → `parmesan` | 50.0 g; raw quantity `50`; warnings []; **CORRECT**; expected {"name": "parmesan", "quantity": 50.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **16/4** `3 large eggs` → `large eggs` | 3.0 db; raw quantity `3`; warnings []; **CORRECT**; expected {"name": "large eggs", "quantity": 3.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **16/5** `350g spaghetti` → `spaghetti` | 350.0 g; raw quantity `350`; warnings []; **CORRECT**; expected {"name": "spaghetti", "quantity": 350.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **16/6** `2 plump garlic cloves peeled and left whole` → `plump garlic cloves peeled and left whole` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "plump garlic peeled and left whole", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **16/7** `50g unsalted butter` → `unsalted butter` | 50.0 g; raw quantity `50`; warnings []; **CORRECT**; expected {"name": "unsalted butter", "quantity": 50.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **16/8** `sea salt and freshly ground black pepper` → `sea salt and freshly ground black pepper` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "sea salt and freshly ground black pepper", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/1** `200g caster sugar` → `caster sugar` | 200.0 g; raw quantity `200`; warnings []; **CORRECT**; expected {"name": "caster sugar", "quantity": 200.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/2** `200g softened butter` → `softened butter` | 200.0 g; raw quantity `200`; warnings []; **CORRECT**; expected {"name": "softened butter", "quantity": 200.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/3** `4 eggs beaten` → `eggs beaten` | 4.0 db; raw quantity `4`; warnings []; **CORRECT**; expected {"name": "eggs beaten", "quantity": 4.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/4** `200g self-raising flour` → `self-raising flour` | 200.0 g; raw quantity `200`; warnings []; **CORRECT**; expected {"name": "self-raising flour", "quantity": 200.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/5** `1 tsp  baking powder` → `tsp baking powder` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "baking powder", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/6** `2 tbsp milk` → `tbsp milk` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "milk", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/7** `100g butter softened` → `butter softened` | 100.0 g; raw quantity `100`; warnings []; **CORRECT**; expected {"name": "butter softened", "quantity": 100.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/8** `140g icing sugar sifted` → `icing sugar sifted` | 140.0 g; raw quantity `140`; warnings []; **CORRECT**; expected {"name": "icing sugar sifted", "quantity": 140.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/9** `drop vanilla extract (optional)` → `drop vanilla extract (optional)` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; expected {"name": "vanilla extract (optional)", "quantity": null, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/10** `half a 340g jar good-quality strawberry jam` → `half a 340g jar good-quality strawberry jam` | None db; raw quantity `None`; warnings ['ambiguousIngredient']; **UNSUPPORTED_UNIT**; expected {"name": "good-quality strawberry jam", "quantity": null, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **17/11** `icing sugar to decorate` → `icing sugar to decorate` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "icing sugar to decorate", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/1** `1 large onion` → `large onion` | 1.0 db; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "large onion", "quantity": 1.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/2** `1 red pepper` → `red pepper` | 1.0 db; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "red pepper", "quantity": 1.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/3** `2 garlic cloves` → `garlic cloves` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "garlic", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/4** `1 tbsp oil` → `tbsp oil` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "oil", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/5** `1 heaped tsp hot chilli powder (or 1 level tbsp if you only have mild)` → `1 heaped tsp hot chilli powder (or 1 level tbsp if you only have mild)` | None db; raw quantity `None`; warnings ['ambiguousIngredient']; **UNSUPPORTED_UNIT**; expected {"name": "hot chilli powder (or 1 level tbsp if you only have mild)", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/6** `1 tsp paprika` → `tsp paprika` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "paprika", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/7** `1 tsp ground cumin` → `tsp ground cumin` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "ground cumin", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/8** `500g lean minced beef` → `lean minced beef` | 500.0 g; raw quantity `500`; warnings []; **CORRECT**; expected {"name": "lean minced beef", "quantity": 500.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/9** `1 beef stock cube` → `beef stock cube` | 1.0 db; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "beef stock cube", "quantity": 1.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/10** `400g can Mutti chopped tomatoes` → `can Mutti chopped tomatoes` | 400.0 g; raw quantity `400`; warnings []; **CORRECT**; expected {"name": "can Mutti chopped tomatoes", "quantity": 400.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/11** `½ tsp dried marjoram` → `tsp dried marjoram` | 0.5 db; raw quantity `½`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "dried marjoram", "quantity": 0.5, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/12** `1 tsp sugar (or add a thumbnail-sized piece of dark chocolate along with the beans instead, see tip)` → `tsp sugar (or add a thumbnail-sized piece of dark chocolate along with the beans instead, see tip)` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "sugar (or add a thumbnail-sized piece of dark chocolate along with the beans instead, see tip)", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/13** `2 tbsp tomato purée` → `tbsp tomato purée` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "tomato purée", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/14** `410g can red kidney beans` → `can red kidney beans` | 410.0 g; raw quantity `410`; warnings []; **CORRECT**; expected {"name": "can red kidney beans", "quantity": 410.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/15** `plain boiled long grain rice to serve` → `plain boiled long grain rice to serve` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "plain boiled long grain rice to serve", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **18/16** `soured cream to serve` → `soured cream to serve` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **CORRECT**; expected {"name": "soured cream to serve", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/1** `4 tbsp vegetable oil` → `tbsp vegetable oil` | 4.0 db; raw quantity `4`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "vegetable oil", "quantity": 4.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/2** `25g butter` → `butter` | 25.0 g; raw quantity `25`; warnings []; **CORRECT**; expected {"name": "butter", "quantity": 25.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/3** `4 onions roughly chopped` → `onions roughly chopped` | 4.0 db; raw quantity `4`; warnings []; **CORRECT**; expected {"name": "onions roughly chopped", "quantity": 4.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/4** `6 tbsp chicken tikka masala paste (use shop-bought or make your own – see recipe, below)` → `tbsp chicken tikka masala paste (use shop-bought or make your own – see recipe, below)` | 6.0 db; raw quantity `6`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "chicken tikka masala paste (use shop-bought or make your own – see recipe, below)", "quantity": 6.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/5** `2 red peppers deseeded and cut into chunks` → `red peppers deseeded and cut into chunks` | 2.0 db; raw quantity `2`; warnings []; **CORRECT**; expected {"name": "red peppers deseeded and cut into chunks", "quantity": 2.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/6** `8 boneless, skinless chicken breasts cut into 2.5cm cubes` → `boneless, skinless chicken breasts cut into 2.5cm cubes` | 8.0 db; raw quantity `8`; warnings []; **CORRECT**; expected {"name": "boneless, skinless chicken breasts cut into 2.5cm cubes", "quantity": 8.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/7** `2 x 400g cans  chopped tomatoes` → `2 x 400g cans  chopped tomatoes` | None db; raw quantity `None`; warnings ['ambiguousIngredient']; **UNSUPPORTED_UNIT**; expected {"name": "chopped tomatoes", "quantity": null, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/8** `4 tbsp tomato purée` → `tbsp tomato purée` | 4.0 db; raw quantity `4`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "tomato purée", "quantity": 4.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/9** `2-3 tbsp  mango chutney` → `2-3 tbsp  mango chutney` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; expected {"name": "mango chutney", "quantity": null, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/10** `150ml double cream` → `double cream` | 150.0 ml; raw quantity `150`; warnings []; **CORRECT**; expected {"name": "double cream", "quantity": 150.0, "unit": "ml", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/11** `150ml natural  yogurt` → `natural yogurt` | 150.0 ml; raw quantity `150`; warnings []; **FORMAT_ONLY**; expected {"name": "natural yogurt", "quantity": 150.0, "unit": "ml", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **19/12** `chopped  coriander leaves, to serve` → `chopped  coriander leaves, to serve` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **FORMAT_ONLY**; expected {"name": "chopped coriander leaves, to serve", "quantity": 1, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/1** `1 tbsp olive oil` → `tbsp olive oil` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "olive oil", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/2** `2 rashers smoked streaky bacon` → `rashers smoked streaky bacon` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "smoked streaky bacon", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/3** `1 onion finely chopped` → `onion finely chopped` | 1.0 db; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "onion finely chopped", "quantity": 1.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/4** `1 celery stick, finely chopped` → `celery stick, finely chopped` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "celery, finely chopped", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/5** `1 medium carrot grated` → `medium carrot grated` | 1.0 db; raw quantity `1`; warnings []; **CORRECT**; expected {"name": "medium carrot grated", "quantity": 1.0, "unit": "db", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/6** `2 garlic cloves finely chopped` → `garlic cloves finely chopped` | 2.0 db; raw quantity `2`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "garlic finely chopped", "quantity": 2.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/7** `500g beef mince` → `beef mince` | 500.0 g; raw quantity `500`; warnings []; **CORRECT**; expected {"name": "beef mince", "quantity": 500.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/8** `1 tbsp tomato purée` → `tbsp tomato purée` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "tomato purée", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/9** `2 x 400g cans chopped tomatoes` → `2 x 400g cans chopped tomatoes` | None db; raw quantity `None`; warnings ['ambiguousIngredient']; **UNSUPPORTED_UNIT**; expected {"name": "chopped tomatoes", "quantity": null, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/10** `1 tbsp clear honey` → `tbsp clear honey` | 1.0 db; raw quantity `1`; warnings []; **UNSUPPORTED_UNIT**; expected {"name": "clear honey", "quantity": 1.0, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/11** `500g pack fresh egg lasagne sheets` → `pack fresh egg lasagne sheets` | 500.0 g; raw quantity `500`; warnings []; **CORRECT**; expected {"name": "pack fresh egg lasagne sheets", "quantity": 500.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/12** `400ml crème fraîche` → `crème fraîche` | 400.0 ml; raw quantity `400`; warnings []; **CORRECT**; expected {"name": "crème fraîche", "quantity": 400.0, "unit": "ml", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/13** `125g ball mozzarella roughly torn` → `ball mozzarella roughly torn` | 125.0 g; raw quantity `125`; warnings []; **CORRECT**; expected {"name": "ball mozzarella roughly torn", "quantity": 125.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/14** `50g freshly grated parmesan` → `freshly grated parmesan` | 50.0 g; raw quantity `50`; warnings []; **CORRECT**; expected {"name": "freshly grated parmesan", "quantity": 50.0, "unit": "g", "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.
- **20/15** `large handful basil leaves torn (optional)` → `large handful basil leaves torn (optional)` | 1.0 db; raw quantity `None`; warnings ['missingQuantity']; **UNSUPPORTED_UNIT**; expected {"name": "basil leaves torn (optional)", "quantity": null, "unit": null, "note": "null quantity/unit = unsupported semantic expression; not expected parser null fallback"}.

## Interpretation

Source errors: 14/8 missing (1,5 kg), 14/9 missing (házi). They cannot be recovered by the parser and do not reduce parser scores. The 17 group heading omission is not an ingredient parser error.

English tsp/tbsp mostly remain in the name with db and no warning. Unicode ½ itself parses as 0.5 even when tsp is unsupported. Ranges can become missingQuantity + 1 db with the complete raw name; multiplier expressions and half-a-jar become ambiguous with null quantity. The alternative numbered quantity in 18/5 also makes the row ambiguous. These are unsupported-input limitations, not supported-input regressions.

No production parser change is required to RUN a supervised B2.4 simulation. English drafts will need substantial review; unsupported tokens must not be presented as reliable canonical units. Highest-value future option: consistent unsupported-measure warnings before any deliberate alias decisions. Multipliers/ranges/textual fractions require separate, tested grammar. No implementation performed.

B2.4 not started. No network, commit, push, corpus or production changes.
