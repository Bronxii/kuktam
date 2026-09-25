RECEPT:
Chicken chilli con carne

HOZZÁVALÓK:
- 2.0 db tbsp olive oil
- 1.0 db onion sliced
- 2.0 db mixed peppers sliced (use red, yellow or orange peppers)
- 2.0 db large garlic cloves crushed
- 1.0 db small bunch of coriander stalks finely chopped and leaves roughly chopped
- 0.5 db tbsp ground coriander
- 1.0 db tbsp ground cumin
- 1.0 db 1-2 tsp chipotle paste
- 400.0 g can chopped tomatoes
- 1.0 db tbsp tomato purée
- 300.0 ml chicken stock
- 1.0 db small cinnamon stick
- 4.0 db skinless chicken thighs bone-in
- 400.0 g can black beans
- 400.0 g can kidney beans drained
- 1.0 db tbsp red wine vinegar
- 20.0 g dark chocolate (at least 70% cocoa solids)
- 1.0 db cooked rice or tortilla chips
- 1.0 db guacamole and soured cream (optional)

WARNINGS:
Production és POC jelzések külön; a POC jelzések kézi benchmark-besorolásból származnak, nem runtime felismerésből.
- 1: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 4: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 5: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 6: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 7: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 8: production=[missingQuantity]; POC=[UNSUPPORTED_INPUT, PARSER_LIMITATION]
- 10: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 12: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 16: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 18: production=[missingQuantity]; POC=[]
- 19: production=[missingQuantity]; POC=[]
- SOURCE_STRUCTURE_WARNING: missing ingredient group heading: [{before_row: 18, heading: To serve, verdict: GROUP_HEADING_DIFFERENCE, json_ld: null}]

ELKÉSZÍTÉS:
Heat the oil in a casserole dish over a medium heat, and fry the onion and peppers for 10-12 mins, or until softened. Add the garlic, coriander stalks, ground coriander, cumin and chipotle paste, and fry for 2 mins more. Tip in the tomatoes, tomato pureé and stock, then add the cinnamon stick. Nestle the chicken thighs into the mixture, then reduce the heat to low and simmer, covered, for 45 mins or until the chicken is tender. Remove the chicken from the casserole and transfer to a chopping board, then shred the meat off the bone using two forks.

Return the shredded chicken to the pan, then tip in the black beans along with the liquid from the can, the drained kidney beans, vinegar and chocolate. Stir well to combine all of the ingredients and melt the chocolate, then turn the heat up to medium and simmer, uncovered, for 10-15 mins, or until the mixture has thickened slightly.

Remove the cinnamon stick, season to taste and stir though most, or all of the coriander leaves (you can reserve a few leaves to scatter over at the end, if you like). Serve the chilli with rice or tortilla chips, topped with guacamole and soured cream, if using, and scatter over any remaining coriander.

VERDICT:
POOR — 10 correction actions / 19 ingredient rows; 2 review-only quantities. Usable=true.

REQUIRED CORRECTIONS:
- {"row":1,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":4,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":5,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":6,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":7,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":8,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":10,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":12,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":16,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"field":"ingredient grouping","classification":"REQUIRED_CORRECTION","reason":"Ingredient group heading lost upstream; logical grouping/to-serve/optional scope needs manual representation. No automatic restoration or ingredient insertion.","evidence":{"before_row":18,"heading":"To serve","verdict":"GROUP_HEADING_DIFFERENCE","json_ld":null},"counting":"One recipe-level structural correction; may need a note/workaround because current draft has no group field."}

REVIEW ONLY:
- {"row":18,"field":"quantity","classification":"REVIEW_ONLY","reason":"Source gives no quantity; accepted 1 db default requires confirmation, not a proven erroneous value."}
- {"row":19,"field":"quantity","classification":"REVIEW_ONLY","reason":"Source gives no quantity; accepted 1 db default requires confirmation, not a proven erroneous value."}
