# B2.4 – End-to-end draft simulation, 11–20

Offline B2.4, 11–20 only. Existing POC simulate() invokes unchanged production RecipeTextParser on full title/ingredients/preparation. Raw ingredient input and production warnings untouched. Known host + exact Mindmegette suffix only. POC warning metadata uses B2.2/B2.3 human-audited labels, NOT an implemented online detector. No correction applied.

Required: one action per objectively misleading/unsupported ingredient row, overlapping reasons counted once; plus one action per missing source ingredient group. Review-only: non-required rows with accepted missing-quantity fallback. Clean means no production OR POC warning. Source/unsupported/warning/risk categories overlap. Source-error rows excluded from silent risk, not excluded from user correction needs.

BROKEN if title/preparation empty or no ingredient rows. READY if 0 required actions. POOR if >=4 required actions OR required actions / ingredient rows >=40%. Otherwise REVIEW. Group loss counts one structural action and cannot necessarily be restored in existing editor without notes; no new editor support assumed.

Desktop Dart JIT, one sequential pass, first recipe includes cold/JIT. Core normalization/parser/draft assembly only; file IO, metadata adjudication and preview/report formatting outside timers. No network.

## Summary

```json
{
  "summary": {
    "recipes": 10,
    "verdicts": {
      "READY": 0,
      "REVIEW": 5,
      "POOR": 5,
      "BROKEN": 0
    },
    "total_rows": 110,
    "clean_rows": 57,
    "source_error_rows": 2,
    "unsupported_rows": 36,
    "parser_error_rows": 0,
    "warning_rows": 53,
    "production_warning_rows": 24,
    "silent_fallback_risk_rows": 27,
    "silent_fallback_affected_recipes": 10,
    "required_correction_rows": 37,
    "required_correction_actions": 38,
    "avg_required_corrections": 3.8,
    "avg_review_only": 1.6
  },
  "domains": {
    "www.mindmegette.hu": {
      "recipes": 5,
      "verdicts": {
        "READY": 0,
        "REVIEW": 4,
        "POOR": 1,
        "BROKEN": 0
      },
      "total_rows": 48,
      "clean_rows": 26,
      "source_error_rows": 2,
      "unsupported_rows": 10,
      "parser_error_rows": 0,
      "warning_rows": 22,
      "production_warning_rows": 12,
      "silent_fallback_risk_rows": 8,
      "silent_fallback_affected_recipes": 5,
      "required_correction_rows": 11,
      "required_correction_actions": 11,
      "avg_required_corrections": 2.2,
      "avg_review_only": 2.2
    },
    "www.bbcgoodfood.com": {
      "recipes": 5,
      "verdicts": {
        "READY": 0,
        "REVIEW": 1,
        "POOR": 4,
        "BROKEN": 0
      },
      "total_rows": 62,
      "clean_rows": 31,
      "source_error_rows": 0,
      "unsupported_rows": 26,
      "parser_error_rows": 0,
      "warning_rows": 31,
      "production_warning_rows": 12,
      "silent_fallback_risk_rows": 19,
      "silent_fallback_affected_recipes": 5,
      "required_correction_rows": 26,
      "required_correction_actions": 27,
      "avg_required_corrections": 5.4,
      "avg_review_only": 1.0
    }
  },
  "timing": {
    "normalization_ms": {
      "total": 23.004,
      "average": 2.3004000000000002,
      "max": 19.575
    },
    "parser_ms": {
      "total": 10.751000000000001,
      "average": 1.0751000000000002,
      "max": 5.12
    },
    "draft_build_ms": {
      "total": 0.3890000000000001,
      "average": 0.03890000000000001,
      "max": 0.183
    },
    "total_local_ms": {
      "total": 34.177,
      "average": 3.4177,
      "max": 24.886
    }
  }
}
```

| ID | Verdict | Required actions | Review only | Silent risk rows | Preview |
|---|---|---|---|---|---|
| 11 | REVIEW | 1 | 1 | 1 | [preview](b2_4_previews/recipe_11.md) |
| 12 | POOR | 5 | 0 | 4 | [preview](b2_4_previews/recipe_12.md) |
| 13 | REVIEW | 1 | 3 | 1 | [preview](b2_4_previews/recipe_13.md) |
| 14 | REVIEW | 3 | 2 | 1 | [preview](b2_4_previews/recipe_14.md) |
| 15 | REVIEW | 1 | 5 | 1 | [preview](b2_4_previews/recipe_15.md) |
| 16 | REVIEW | 1 | 1 | 1 | [preview](b2_4_previews/recipe_16.md) |
| 17 | POOR | 5 | 1 | 2 | [preview](b2_4_previews/recipe_17.md) |
| 18 | POOR | 8 | 2 | 7 | [preview](b2_4_previews/recipe_18.md) |
| 19 | POOR | 5 | 1 | 3 | [preview](b2_4_previews/recipe_19.md) |
| 20 | POOR | 8 | 0 | 6 | [preview](b2_4_previews/recipe_20.md) |

Titles: five exact known-domain suffix removals; five unchanged. No guessing. Instructions: heading/body entries joined in original order by existing POC helper; full preparation retained through parser. Recipe 12 remains a single source block with its embedded numbering, not split by guessing. Spices empty in every draft.

Source errors: 14/8 and 14/9 remain uncorrected with SOURCE_WARNING; 17 group loss tracked structurally. Unsupported rows receive POC warnings even when production parser is silent. No supported-input parser regression appeared in full-context simulation.

B2.5 can summarize these results without a parser change. Drafts require supervised review, particularly English input. Silent unsupported db fallback remains a product risk. No production integration or automatic save. B2.5 not started.
