# B3.4 – End-to-end draft simulation, 21–28

Offline B3.4, 21–28 only. Existing POC simulate() invokes unchanged production RecipeTextParser on full title/ingredients/preparation. Raw ingredient input and production warnings untouched. All eight clean Good Food titles unchanged. POC warning metadata uses B3.2/B3.3 human-audited labels, NOT an implemented online detector. No correction applied.

Required: one action per objectively misleading ingredient row. All 31 reviewed unsupported rows here contain a measure/expression represented as db or an ambiguous/null quantity, so they require resolution (not merely review); original words remain but do not make that numeric/unit representation reliable. Count overlapping reasons counted once; plus one action per missing source ingredient group. Review-only: non-required rows with accepted missing-quantity fallback. Clean means no production OR POC warning. Source/unsupported/warning/risk categories overlap. Source-error rows excluded from silent risk, not excluded from user correction needs.

BROKEN if title/preparation empty or no ingredient rows. READY if 0 required actions. POOR if >=4 required actions OR required actions / ingredient rows >=40%. Otherwise REVIEW. Group loss counts one structural action and cannot necessarily be restored in existing editor without notes; no new editor support assumed.

Desktop Dart JIT, one sequential pass, first recipe includes cold/JIT. Core normalization/parser/draft assembly only; file IO, metadata adjudication and preview/report formatting outside timers. No network.

## Summary

```json
{
  "summary": {
    "recipes": 8,
    "verdicts": {
      "READY": 1,
      "REVIEW": 2,
      "POOR": 5,
      "BROKEN": 0
    },
    "total_rows": 82,
    "clean_rows": 45,
    "source_error_rows": 0,
    "unsupported_rows": 31,
    "parser_error_rows": 0,
    "warning_rows": 37,
    "production_warning_rows": 16,
    "silent_fallback_risk_rows": 21,
    "silent_fallback_affected_recipes": 6,
    "required_correction_rows": 31,
    "review_only_rows": 6,
    "source_structure_warning_rows": 0,
    "source_structure_warning_count": 4,
    "source_structure_affected_recipes": 2,
    "instruction_entries_preserved": 47,
    "required_correction_actions": 35,
    "avg_required_corrections": 4.375,
    "avg_review_only": 0.75
  },
  "domains": {
    "www.bbcgoodfood.com": {
      "recipes": 8,
      "verdicts": {
        "READY": 1,
        "REVIEW": 2,
        "POOR": 5,
        "BROKEN": 0
      },
      "total_rows": 82,
      "clean_rows": 45,
      "source_error_rows": 0,
      "unsupported_rows": 31,
      "parser_error_rows": 0,
      "warning_rows": 37,
      "production_warning_rows": 16,
      "silent_fallback_risk_rows": 21,
      "silent_fallback_affected_recipes": 6,
      "required_correction_rows": 31,
      "review_only_rows": 6,
      "source_structure_warning_rows": 0,
      "source_structure_warning_count": 4,
      "source_structure_affected_recipes": 2,
      "instruction_entries_preserved": 47,
      "required_correction_actions": 35,
      "avg_required_corrections": 4.375,
      "avg_review_only": 0.75
    }
  },
  "timing": {
    "normalization_ms": {
      "total": 11.404000000000002,
      "average": 1.4255000000000002,
      "max": 8.641
    },
    "parser_ms": {
      "total": 9.700000000000001,
      "average": 1.2125000000000001,
      "max": 5.54
    },
    "draft_build_ms": {
      "total": 0.30400000000000005,
      "average": 0.038000000000000006,
      "max": 0.169
    },
    "total_local_ms": {
      "total": 21.435000000000002,
      "average": 2.6793750000000003,
      "max": 14.358
    }
  }
}
```

| ID | Rows | Clean | Unsupported | Silent | Structural | Required actions | Review only | Verdict | Preview |
|---|---|---|---|---|---|---|---|---|---|
| 21 | 11 | 5 | 5 | 4 | 0 | 5 | 1 | POOR | [preview](b3_4_previews/recipe_21.md) |
| 22 | 6 | 3 | 1 | 1 | 0 | 1 | 2 | REVIEW | [preview](b3_4_previews/recipe_22.md) |
| 23 | 13 | 11 | 2 | 0 | 0 | 2 | 0 | REVIEW | [preview](b3_4_previews/recipe_23.md) |
| 24 | 8 | 8 | 0 | 0 | 0 | 0 | 0 | READY | [preview](b3_4_previews/recipe_24.md) |
| 25 | 8 | 4 | 3 | 3 | 3 | 6 | 1 | POOR | [preview](b3_4_previews/recipe_25.md) |
| 26 | 9 | 3 | 6 | 2 | 0 | 6 | 0 | POOR | [preview](b3_4_previews/recipe_26.md) |
| 27 | 8 | 3 | 5 | 3 | 0 | 5 | 0 | POOR | [preview](b3_4_previews/recipe_27.md) |
| 28 | 19 | 8 | 9 | 8 | 1 | 10 | 2 | POOR | [preview](b3_4_previews/recipe_28.md) |

Titles: 8/8 unchanged. All 47 source instruction entries preserved in order, without duplicate headings. Spices empty. Four missing group headings are source structure warnings, not parser errors; 25 loses filling/crumble/optional-topping scopes, 28 loses To serve scope. They are counted as four separate structural correction actions, not ingredient rows. Ingredient categories overlap; clean + warning rows partitions all 82 rows.

## B2.4 comparison

B2.4: 0 READY / 5 REVIEW / 5 POOR / 0 BROKEN; 3.8 required actions per recipe; 27 silent fallback rows. B3.4 summary above uses the same one-row-one-action rule and one action per missing group heading. Different sample sizes (10 vs 8), no pooled statistics. Structural actions count toward the >=4 threshold; the 40% rule in this corpus gives the same result whether structural actions are included or only corrected ingredient rows are used.

No parser modification is needed before B3.5 summary. This is a supervised POC, not safe unattended production import. Production warnings and audit-derived POC warnings are distinct; no runtime unsupported detector was implemented. 29–30: NO_DRAFT_DUE_TO_ACCESS_BLOCK, HTTP 403, excluded from usability denominator. No production, extractor, parser or corpus changes. B3.5 not started.
