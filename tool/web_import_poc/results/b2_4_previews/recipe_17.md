RECEPT:
Classic Victoria sandwich recipe

HOZZÁVALÓK:
- 200.0 g caster sugar
- 200.0 g softened butter
- 4.0 db eggs beaten
- 200.0 g self-raising flour
- 1.0 db tsp baking powder
- 2.0 db tbsp milk
- 100.0 g butter softened
- 140.0 g icing sugar sifted
- 1.0 db drop vanilla extract (optional)
- [javítandó] db half a 340g jar good-quality strawberry jam
- 1.0 db icing sugar to decorate

WARNINGS:
Production és POC jelzések külön; a POC jelzések kézi benchmark-besorolásból származnak, nem runtime felismerésből.
- 5: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 6: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 9: production=[missingQuantity]; POC=[UNSUPPORTED_INPUT, PARSER_LIMITATION]
- 10: production=[ambiguousIngredient]; POC=[UNSUPPORTED_INPUT, PARSER_LIMITATION]
- 11: production=[missingQuantity]; POC=[]
- SOURCE_WARNING: missing ingredient group heading: [{before_row: 7, heading: For the filling, verdict: GROUP_HEADING_DIFFERENCE, json_ld: null}]

ELKÉSZÍTÉS:
Heat oven to 190C/fan 170C/gas 5. Butter two 20cm sandwich tins and line with non-stick baking paper.

In a large bowl, beat 200g caster sugar, 200g softened butter, 4 beaten eggs, 200g self-raising flour, 1 tsp baking powder and 2 tbsp milk together until you have a smooth, soft batter.

Divide the mixture between the tins, smooth the surface with a spatula or the back of a spoon.

Bake for about 20 mins until golden and the cake springs back when pressed.

Turn onto a cooling rack and leave to cool completely.

To make the filling, beat the 100g softened butter until smooth and creamy, then gradually beat in 140g sifted icing sugar and a drop of vanilla extract (if you’re using it).

Spread the buttercream over the bottom of one of the sponges. Top it with 170g strawberry jam and sandwich the second sponge on top.

Dust with a little icing sugar before serving. Keep in an airtight container and eat within 2 days.

VERDICT:
POOR — 5 correction actions / 11 ingredient rows; 1 review-only quantities. Usable=true.

REQUIRED CORRECTIONS:
- {"row":5,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":6,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":9,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":10,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"field":"ingredient grouping","classification":"REQUIRED_CORRECTION","reason":"For the filling group heading lost upstream; no automatic restoration or ingredient insertion.","evidence":{"before_row":7,"heading":"For the filling","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null},"counting":"One recipe-level structural correction; may need a note/workaround because current draft has no group field."}

REVIEW ONLY:
- {"row":11,"field":"quantity","classification":"REVIEW_ONLY","reason":"Source gives no quantity; accepted 1 db default requires confirmation, not a proven erroneous value."}
