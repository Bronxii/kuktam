# Korrigált P2 – batch 01–10

A teljes döntési bizonyíték: p2_5_source_truth_audit.json/md. Az eredeti P2 megmaradt.

| ID | Verdict | Normalizált GT-egyezés | Látható oldal–JSON-LD hibás sor |
|---|---|---|---|
| 01 | ACCEPTABLE | 8/8 | 0 |
| 02 | PARTIAL | 10/12 | 3 |
| 03 | PARTIAL | 14/14 | 4 |
| 04 | ACCEPTABLE | 7/7 | 0 |
| 05 | ACCEPTABLE | 17/17 | 0 |
| 06 | PARTIAL | 5/10 | 5 |
| 07 | PARTIAL | 6/7 | 1 |
| 08 | PARTIAL | 3/6 | 3 |
| 09 | PARTIAL | 2/9 | 5 |
| 10 | PARTIAL | 8/10 | 1 |

```json
{
  "primary_audit_decisions": {
    "FORMAT_DIFFERENCE": 10,
    "SOURCE_JSONLD_ERROR": 17,
    "GROUND_TRUTH_ERROR": 6
  },
  "incidental_source_errors": 5,
  "counting_unit": "One ingredient row, one complete instruction-reference correction per recipe, one title per recipe, one markup-bearing step.",
  "corrected_files": [
    "recipe_03.txt",
    "recipe_06.txt",
    "recipe_08.txt",
    "recipe_09.txt",
    "recipe_10.txt"
  ],
  "extractor": {
    "ingredients_preserved": 100,
    "ingredients_total": 100,
    "steps_preserved": 56,
    "steps_total": 56,
    "rows_lost": 0,
    "rows_added": 0,
    "order_errors": 0,
    "instruction_loss": 0,
    "fidelity_percent": 100
  },
  "source_quality": {
    "ingredient_mismatches": 22,
    "ingredient_rows_total": 100,
    "ingredient_content_agreement_percent": 78,
    "quantity_mismatches": 15,
    "truncated_fraction_rows": 8,
    "spurious_zero_rows": 7,
    "instruction_omissions": 0,
    "title_decoration_only": 5
  },
  "verdicts": {
    "PERFECT": 0,
    "ACCEPTABLE": 3,
    "PARTIAL": 7,
    "FAILED": 0
  },
  "scope_note": "Primary 21 ingredients + 06/08 instructions + titles/markup. Five incidental ingredient-note omissions are separately disclosed and included in source-quality verdict. Other GT instructions remain paraphrased; no literal instruction accuracy is claimed."
}
```

A zárójeles megjegyzések miatt a szigorú szövegegyezés nem azonos a tartalmi megfeleléssel. Nincs elveszett teljes hozzávalósor vagy extractor okozta lépésveszteség. A corrected verdict a látható forrástartalom teljességét is figyelembe veszi, nem csupán a régi, tömör referencia egyezését. Tartalmi siker: 3/10 = 30%.
