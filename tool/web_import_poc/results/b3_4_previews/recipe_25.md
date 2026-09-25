RECEPT:
Easy apple crumble recipe

HOZZÁVALÓK:
- 575.0 g Bramley apple (3 medium apples), peeled, cored and sliced to 1cm thick
- 2.0 db tbsp golden caster sugar
- 175.0 g plain flour
- 110.0 g golden caster sugar
- 110.0 g cold butter
- 1.0 db tbsp rolled oats
- 1.0 db tbsp demerara sugar
- 1.0 db double cream clotted cream or custard, to serve

WARNINGS:
Production és POC jelzések külön; a POC jelzések kézi benchmark-besorolásból származnak, nem runtime felismerésből.
- 2: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 6: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 7: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 8: production=[missingQuantity]; POC=[]
- SOURCE_STRUCTURE_WARNING: missing ingredient group heading: [{before_row: 1, heading: For the filling, verdict: GROUP_HEADING_DIFFERENCE, json_ld: null}, {before_row: 3, heading: For the crumble, verdict: GROUP_HEADING_DIFFERENCE, json_ld: null}, {before_row: 6, heading: For the topping (optional), verdict: GROUP_HEADING_DIFFERENCE, json_ld: null}]

ELKÉSZÍTÉS:
Heat the oven to 190C/170 fan/gas 5.

Toss 575g peeled, cored and sliced Bramley apples with 2 tbsp golden caster sugar and put in a 23cm round baking dish at least 5cm deep, or a 20cm square dish. Flatten down with your hand to prevent too much crumble falling through.

Put 175g plain flour and 110g golden caster sugar in a bowl with a good pinch of salt.

Slice in 110g cold butter and rub it in with your fingertips until the mixture looks like moist breadcrumbs. Shake the bowl and any big bits will come to the surface – rub them in. Alternatively, pulse in a processor until sandy (don’t over-process).

Pour the crumb mix over the apples to form a pile in the centre, then use a fork to even out.

Gently press the surface with the back of the fork so the crumble holds together and goes crisp, then lightly drag the fork over the top for a decorative finish.

Sprinkle 1 tbsp rolled oats and 1 tbsp demerara sugar over evenly, if you wish.

Set on a baking tray and put in the preheated oven for 35-40 minutes, until the top is golden and the apples feel very soft when you insert a small, sharp knife. Leave to cool for 10 minutes before serving.

VERDICT:
POOR — 6 correction actions / 8 ingredient rows; 1 review-only quantities. Usable=true.

REQUIRED CORRECTIONS:
- {"row":2,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":6,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":7,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"field":"ingredient grouping","classification":"REQUIRED_CORRECTION","reason":"Ingredient group heading lost upstream; logical grouping/to-serve/optional scope needs manual representation. No automatic restoration or ingredient insertion.","evidence":{"before_row":1,"heading":"For the filling","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null},"counting":"One recipe-level structural correction; may need a note/workaround because current draft has no group field."}
- {"field":"ingredient grouping","classification":"REQUIRED_CORRECTION","reason":"Ingredient group heading lost upstream; logical grouping/to-serve/optional scope needs manual representation. No automatic restoration or ingredient insertion.","evidence":{"before_row":3,"heading":"For the crumble","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null},"counting":"One recipe-level structural correction; may need a note/workaround because current draft has no group field."}
- {"field":"ingredient grouping","classification":"REQUIRED_CORRECTION","reason":"Ingredient group heading lost upstream; logical grouping/to-serve/optional scope needs manual representation. No automatic restoration or ingredient insertion.","evidence":{"before_row":6,"heading":"For the topping (optional)","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null},"counting":"One recipe-level structural correction; may need a note/workaround because current draft has no group field."}

REVIEW ONLY:
- {"row":8,"field":"quantity","classification":"REVIEW_ONLY","reason":"Source gives no quantity; accepted 1 db default requires confirmation, not a proven erroneous value."}
