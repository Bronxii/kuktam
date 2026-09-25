RECEPT:
Hagyományos szatmári töltött káposzta

HOZZÁVALÓK:
- 1.0 db kis fej Hagyma
- 50.0 g Sertészsír
- 500.0 g darált sertéshús
- 250.0 g Rizs
- 1.0 db Só
- 1.0 db Bors
- 1.0 ek Pirospaprika
- 1.0 db fej édes káposzta
- 300.0 ml paradicsomlé
- 200.0 ml Tejföl

WARNINGS:
Production és POC jelzések külön; a POC jelzések kézi benchmark-besorolásból származnak, nem runtime felismerésből.
- 1: production=[]; POC=[UNSUPPORTED_INPUT, SILENT_BAD_FALLBACK_RISK]
- 5: production=[missingQuantity]; POC=[]
- 6: production=[missingQuantity]; POC=[]
- 8: production=[]; POC=[SOURCE_WARNING, UNSUPPORTED_INPUT]
- 9: production=[]; POC=[SOURCE_WARNING]

ELKÉSZÍTÉS:
1. lépés: A hagymát apróra vágjuk, és 2 dkg felforrósított zsíron üvegesre pároljuk, majd félretesszük hűlni. Ezután a hagymát, a darált húst és a rizst összekeverjük, és sóval, borssal, pirospaprikával ízesítjük.

2. lépés: A káposztát forró vízben megpuhítjuk. A leválasztott levelekre a vastag erek laposra vágása után tölteléket teszünk. Ezután mindet feltekerjük, és a két végüket benyomjuk.

3. lépés: A levelekről levágott részeket és a belső, túl apró leveleket laskára metéljük. Egy nagyobb lábost kikenünk 3 dkg zsírral. Az aljára tesszük a vágott káposzta felét, sorban rárakjuk a töltelékeket, majd rászórjuk a megmaradt aprítékot. Annyi vizet öntünk rá, amennyi ellepi, és feltesszük főni. Közben az elfőtt folyadékot időnként vízzel pótoljuk.

4. lépés: Amikor kb. 40 perc alatt félpuhára főtt, felöntjük paradicsomlével. Ezután jól befedjük, és lassú tűzön készre főzzük. Tejföllel meglocsolva tálaljuk.

VERDICT:
REVIEW — 3 correction actions / 10 ingredient rows; 2 review-only quantities. Usable=true.

REQUIRED CORRECTIONS:
- {"row":1,"classification":"REQUIRED_CORRECTION","fields":["name/quantity/unit interpretation"],"reasons":["Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":8,"classification":"REQUIRED_CORRECTION","fields":["name/source note","name/quantity/unit interpretation"],"reasons":["Visible source note lost in JSON-LD; not repaired.","Unsupported measure/expression cannot safely be represented by current db fallback."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}
- {"row":9,"classification":"REQUIRED_CORRECTION","fields":["name/source note"],"reasons":["Visible source note lost in JSON-LD; not repaired."],"counting":"One row-level correction action even if multiple fields/reasons overlap."}

REVIEW ONLY:
- {"row":5,"field":"quantity","classification":"REVIEW_ONLY","reason":"Source gives no quantity; accepted 1 db default requires confirmation, not a proven erroneous value."}
- {"row":6,"field":"quantity","classification":"REVIEW_ONLY","reason":"Source gives no quantity; accepted 1 db default requires confirmation, not a proven erroneous value."}
