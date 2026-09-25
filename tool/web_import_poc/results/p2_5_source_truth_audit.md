# P2.5 source-truth audit

Csak mentett HTML/JSON, hálózat nélkül. A látható érték a snapshot recepttartalmát jelenti, nem új élő böngészőmérést.

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

## 01 – title – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/rakott-krumpli

Snapshot: html/p1_01.html

- Látható: "Rakott krumpli"
- JSON-LD: "Rakott krumpli | Mindmegette.hu"
- Eredeti GT: "Rakott krumpli"

A látható h1 receptcímhez a JSON-LD webhely-utótagot ad.

## 01 – instruction 2 markup – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/rakott-krumpli

Snapshot: html/p1_01.html

- Látható: "A krumplit felöntjük annyi hideg vízzel, hogy bőven ellepje."
- JSON-LD: "A krumplit felöntjük annyi hideg vízzel, hogy bőven ellepje.&nbsp;"
- Eredeti GT: ["1. A burgonyát héjában sós vízben főzd puhára, majd hűtsd le, hámozd meg és karikázd fel.","2. A tojásokat főzd keményre, hűtsd le, hámozd meg és szeleteld fel.","3. A kolbászt karikázd fel, a tejfölt keverd össze a tojássárgájával.","4. Vajazz ki egy sütőtálat, majd rétegezd a burgonyát, tojást, kolbászt és tejfölt.","5. A tetejére kerüljön a maradék tejföl és a bacon.","6. 180 °C-on süsd aranybarnára, nagyjából 35–40 perc alatt."]

A látható HTML whitespace-ként jeleníti meg az &nbsp; entitást; a JSON-LD-ben entitásszöveg marad. Nincs tartalomveszteség.

## 01 – instruction 4 markup – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/rakott-krumpli

Snapshot: html/p1_01.html

- Látható: "A tojásokat sós, hideg vízben feltesszük főni, és a forrástól számított 8 percig főzzük, majd hideg vízbe merítve azonnal lehűtjük."
- JSON-LD: "A tojásokat sós, hideg vízben feltesszük főni, és a forrástól számított 8 percig főzzük, majd hideg vízbe merítve azonnal lehűtjük.&nbsp;"
- Eredeti GT: ["1. A burgonyát héjában sós vízben főzd puhára, majd hűtsd le, hámozd meg és karikázd fel.","2. A tojásokat főzd keményre, hűtsd le, hámozd meg és szeleteld fel.","3. A kolbászt karikázd fel, a tejfölt keverd össze a tojássárgájával.","4. Vajazz ki egy sütőtálat, majd rétegezd a burgonyát, tojást, kolbászt és tejfölt.","5. A tetejére kerüljön a maradék tejföl és a bacon.","6. 180 °C-on süsd aranybarnára, nagyjából 35–40 perc alatt."]

A látható HTML whitespace-ként jeleníti meg az &nbsp; entitást; a JSON-LD-ben entitásszöveg marad. Nincs tartalomveszteség.

## 01 – instruction 6 markup – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/rakott-krumpli

Snapshot: html/p1_01.html

- Látható: "A kolbászt meleg vízzel leöblítjük, így könnyen lehúzhatjuk a héját, aztán vékonyan felkarikázzuk."
- JSON-LD: "A kolbászt meleg vízzel leöblítjük, így könnyen lehúzhatjuk a héját, aztán vékonyan felkarikázzuk.&nbsp;"
- Eredeti GT: ["1. A burgonyát héjában sós vízben főzd puhára, majd hűtsd le, hámozd meg és karikázd fel.","2. A tojásokat főzd keményre, hűtsd le, hámozd meg és szeleteld fel.","3. A kolbászt karikázd fel, a tejfölt keverd össze a tojássárgájával.","4. Vajazz ki egy sütőtálat, majd rétegezd a burgonyát, tojást, kolbászt és tejfölt.","5. A tetejére kerüljön a maradék tejföl és a bacon.","6. 180 °C-on süsd aranybarnára, nagyjából 35–40 perc alatt."]

A látható HTML whitespace-ként jeleníti meg az &nbsp; entitást; a JSON-LD-ben entitásszöveg marad. Nincs tartalomveszteség.

## 01 – instruction 7 markup – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/rakott-krumpli

Snapshot: html/p1_01.html

- Látható: "A tejfölt egy kis tálba tesszük és elkeverjük benne a tojássárgákat."
- JSON-LD: "A tejfölt egy kis tálba tesszük és elkeverjük benne a tojássárgákat.&nbsp;"
- Eredeti GT: ["1. A burgonyát héjában sós vízben főzd puhára, majd hűtsd le, hámozd meg és karikázd fel.","2. A tojásokat főzd keményre, hűtsd le, hámozd meg és szeleteld fel.","3. A kolbászt karikázd fel, a tejfölt keverd össze a tojássárgájával.","4. Vajazz ki egy sütőtálat, majd rétegezd a burgonyát, tojást, kolbászt és tejfölt.","5. A tetejére kerüljön a maradék tejföl és a bacon.","6. 180 °C-on süsd aranybarnára, nagyjából 35–40 perc alatt."]

A látható HTML whitespace-ként jeleníti meg az &nbsp; entitást; a JSON-LD-ben entitásszöveg marad. Nincs tartalomveszteség.

## 02 – ingredient 1 – SOURCE_JSONLD_ERROR

URL: https://www.mindmegette.hu/recept/fasirt

Snapshot: html/p1_02.html

- Látható: "50 dkg sertéshús (darált, lapocka vagy comb)"
- JSON-LD: "50 dkg sertéshús"
- Eredeti GT: "50 dkg darált sertéshús"

A .ingredients-meta small elemben a jelző látható, de a JSON-LD kihagyja.

## 02 – ingredient 8 – SOURCE_JSONLD_ERROR

URL: https://www.mindmegette.hu/recept/fasirt

Snapshot: html/p1_02.html

- Látható: "1 tk fűszerpaprika (őrölt)"
- JSON-LD: "1 tk fűszerpaprika"
- Eredeti GT: "1 tk őrölt fűszerpaprika"

A .ingredients-meta small elemben a jelző látható, de a JSON-LD kihagyja.

## 02 – ingredient 3 – SOURCE_JSONLD_ERROR (járulékos)

URL: https://www.mindmegette.hu/recept/fasirt

Snapshot: html/p1_02.html

- Látható: "1 fej vöröshagyma (kicsi)"
- JSON-LD: "1 fej Vöröshagyma"
- Eredeti GT: "1 fej vöröshagyma"

További látható zárójeles megjegyzés hiányzik a JSON-LD-ből és a régi GT-ből is. Külön, járulékos találat; GT itt nem módosult.

## 02 – title – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/fasirt

Snapshot: html/p1_02.html

- Látható: "Fasírt"
- JSON-LD: "Fasírt | Mindmegette.hu"
- Eredeti GT: "Fasírt"

A látható h1 receptcímhez a JSON-LD webhely-utótagot ad.

## 03 – ingredient 14 – GROUND_TRUTH_ERROR

URL: https://www.mindmegette.hu/recept/husleves

Snapshot: html/p1_03.html

- Látható: "10 dkg levelestészta"
- JSON-LD: "10 dkg levelestészta"
- Eredeti GT: "10 dkg levesbetét tészta"

A látható recept és a JSON-LD azonos információt ad; a referencia átírta a nevet vagy kihagyta a megjegyzést.

## 03 – ingredient 3 – SOURCE_JSONLD_ERROR (járulékos)

URL: https://www.mindmegette.hu/recept/husleves

Snapshot: html/p1_03.html

- Látható: "50 dkg vegyes zöldség (sárgarépa, fehérrépa, zeller, karalábé)"
- JSON-LD: "50 dkg vegyes zöldség"
- Eredeti GT: "50 dkg vegyes zöldség"

További látható zárójeles megjegyzés hiányzik a JSON-LD-ből és a régi GT-ből is. Külön, járulékos találat; GT itt nem módosult.

## 03 – ingredient 4 – SOURCE_JSONLD_ERROR (járulékos)

URL: https://www.mindmegette.hu/recept/husleves

Snapshot: html/p1_03.html

- Látható: "1 fej hagyma (közepes)"
- JSON-LD: "1 fej Hagyma"
- Eredeti GT: "1 fej hagyma"

További látható zárójeles megjegyzés hiányzik a JSON-LD-ből és a régi GT-ből is. Külön, járulékos találat; GT itt nem módosult.

## 03 – ingredient 7 – SOURCE_JSONLD_ERROR (járulékos)

URL: https://www.mindmegette.hu/recept/husleves

Snapshot: html/p1_03.html

- Látható: "cseresznyepaprika (körömnyi )"
- JSON-LD: "cseresznyepaprika"
- Eredeti GT: "cseresznyepaprika"

További látható zárójeles megjegyzés hiányzik a JSON-LD-ből és a régi GT-ből is. Külön, járulékos találat; GT itt nem módosult.

## 03 – ingredient 8 – SOURCE_JSONLD_ERROR (járulékos)

URL: https://www.mindmegette.hu/recept/husleves

Snapshot: html/p1_03.html

- Látható: "1 csapott mokkáskanál szeklice (sáfrányos )"
- JSON-LD: "1 csapott mokkáskanál szeklice"
- Eredeti GT: "1 csapott mokkáskanál szeklice"

További látható zárójeles megjegyzés hiányzik a JSON-LD-ből és a régi GT-ből is. Külön, járulékos találat; GT itt nem módosult.

## 03 – title – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/husleves

Snapshot: html/p1_03.html

- Látható: "Húsleves"
- JSON-LD: "Húsleves | Mindmegette.hu"
- Eredeti GT: "Húsleves"

A látható h1 receptcímhez a JSON-LD webhely-utótagot ad.

## 04 – title – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/eredeti-tiramisu

Snapshot: html/p1_04.html

- Látható: "Eredeti tiramisu"
- JSON-LD: "Eredeti tiramisu | Mindmegette.hu"
- Eredeti GT: "Eredeti tiramisu"

A látható h1 receptcímhez a JSON-LD webhely-utótagot ad.

## 05 – title – FORMAT_DIFFERENCE

URL: https://www.mindmegette.hu/recept/zserbo-alaprecept

Snapshot: html/p1_05.html

- Látható: "Zserbó alaprecept"
- JSON-LD: "Zserbó alaprecept | Mindmegette.hu"
- Eredeti GT: "Zserbó alaprecept"

A látható h1 receptcímhez a JSON-LD webhely-utótagot ad.

## 06 – ingredient 2 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/csirkepaprikas

Snapshot: html/p1_06.html

- Látható: "0.5 ek sertészsír"
- JSON-LD: "0 ek Sertészsír"
- Eredeti GT: "0.5 ek sertészsír"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 06 – ingredient 3 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/csirkepaprikas

Snapshot: html/p1_06.html

- Látható: "0.5 közepes db vöröshagyma"
- JSON-LD: "0 közepes db Vöröshagyma"
- Eredeti GT: "0.5 közepes db vöröshagyma"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 06 – ingredient 4 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/csirkepaprikas

Snapshot: html/p1_06.html

- Látható: "0.5 teáskanál fűszerpaprika"
- JSON-LD: "0 teáskanál Fűszerpaprika"
- Eredeti GT: "0.5 tk fűszerpaprika"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 06 – ingredient 9 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/csirkepaprikas

Snapshot: html/p1_06.html

- Látható: "só ízlés szerint"
- JSON-LD: "0 ízlés szerint Só"
- Eredeti GT: "só ízlés szerint"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 06 – ingredient 10 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/csirkepaprikas

Snapshot: html/p1_06.html

- Látható: "bors ízlés szerint"
- JSON-LD: "0 ízlés szerint Bors"
- Eredeti GT: "bors ízlés szerint"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 06 – instructions – GROUND_TRUTH_ERROR

URL: https://www.nosalty.hu/recept/csirkepaprikas

Snapshot: html/p1_06.html

- Látható: ["A combokat megmossuk, szárazra itatjuk. A hagymát meghámozzuk, apróra vágjuk. A paprikát mossuk, kockára vágjuk. A paradicsomot mossuk, kockákra vágjuk.","A zsírt egy serpenyőben felhevítjük, rászórjuk a hagymát, és megpirítjuk. A tűzről levesszük, hozzákeverjük az édesnemes paprikát és kb. 100 ml vizet öntünk hozzá. Hozzáadjuk a csirkecombokat, a zöldpaprikát és a paradicsomot. Sóval, borssal ízesítjük.","Fedő alatt mérsékelt tűzőn, puhára pároljuk (ha szükséges öntsünk hozzá kevés vizet). A húst kiszedjük. A párolólét botmixerrel pürésítjük, hozzáadjuk a liszttel elkevert tejfölt, és 2-3 perc alatt mártássá forraljuk. A combokkal együtt még egyszer felforraljuk."]
- JSON-LD: ["A combokat megmossuk, szárazra itatjuk. A hagymát meghámozzuk, apróra vágjuk. A paprikát mossuk, kockára vágjuk. A paradicsomot mossuk, kockákra vágjuk.","A zsírt egy serpenyőben felhevítjük, rászórjuk a hagymát, és megpirítjuk. A tűzről levesszük, hozzákeverjük az édesnemes paprikát és kb. 100 ml vizet öntünk hozzá. Hozzáadjuk a csirkecombokat, a zöldpaprikát és a paradicsomot. Sóval, borssal ízesítjük.","Fedő alatt mérsékelt tűzőn, puhára pároljuk (ha szükséges öntsünk hozzá kevés vizet). A húst kiszedjük. A párolólét botmixerrel pürésítjük, hozzáadjuk a liszttel elkevert tejfölt, és 2-3 perc alatt mártássá forraljuk. A combokkal együtt még egyszer felforraljuk."]
- Eredeti GT: ["1. A hagymát zsíron párold üvegesre, majd húzd le a tűzről és keverd hozzá a pirospaprikát.","2. Add hozzá a csirkét, a paprikát és paradicsomot, sózd, borsozd, majd kevés vízzel párold puhára.","3. A tejfölt keverd simára a liszttel.","4. Hőkiegyenlítés után keverd a tejfölös habarást a szaftba, és röviden forrald össze.","5. Nokedlivel vagy más körettel tálald."]

A látható 3 lépés egyezik a JSON-LD-vel; nincs hőkiegyenlítés/köret-tálalás, van botmixerezés. A referencia hozzáírt és elhagyott részleteket.

## 07 – ingredient 7 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/palacsinta-alaprecept

Snapshot: html/p1_07.html

- Látható: "0.5 dl napraforgó olaj"
- JSON-LD: "0 dl Napraforgó olaj"
- Eredeti GT: "0.5 dl napraforgó olaj"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 08 – ingredient 2 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/turos-csusza

Snapshot: html/p1_08.html

- Látható: "só ízlés szerint"
- JSON-LD: "0 ízlés szerint Só"
- Eredeti GT: "só ízlés szerint"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 08 – ingredient 4 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/turos-csusza

Snapshot: html/p1_08.html

- Látható: "2.5 dl víz"
- JSON-LD: "2 dl Víz"
- Eredeti GT: "2.5 dl víz"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 08 – ingredient 5 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/turos-csusza

Snapshot: html/p1_08.html

- Látható: "2.5 dl tejföl"
- JSON-LD: "2 dl Tejföl"
- Eredeti GT: "2.5 dl tejföl"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 08 – instructions – GROUND_TRUTH_ERROR

URL: https://www.nosalty.hu/recept/turos-csusza

Snapshot: html/p1_08.html

- Látható: ["A tésztát lobogó, enyhén sós vízben fogkeményre kifőzzük.","A szalonnát egy centis darabokra felkockázzuk, serpenyőbe tesszük. Felöntjük annyi vízzel, ami éppen ellepi, és közepes lángon melegíteni kezdjük. Egészen addig folytatjuk, amíg minden csepp víz el nem párolog, sőt utána szép barnára, zsírjára sütjük. (A vízre azért van szükség, mert így kívül ropogós, de belül puha marad.) Ha elkészült, akkor szűrőlapáttal kivesszük a szalonnát, és félretesszük.","A zsírt is kiöntjük, csak három evőkanállal hagyunk benne, ehhez hozzáadjuk a tejfölt, és alaposan elkeverjük.","A kifőtt tésztát összeforgatjuk a tejfölös keverék és a túró egyharmadával, majd a sütőt grill fokozatra és maximum hőfokra állítjuk, és 10-12 percre betesszük, amíg meg nem pirul a tészta széle.","Kivesszük a tésztát a sütőből, átforgatjuk, majd hozzáadjuk a túró és tejföl második harmadát, és újra visszatesszük a sütőbe 10 percre.","Ha kész, azonnal tálaljuk. A tetejét a maradék tejföllel és túróval meglocsoljuk."]
- JSON-LD: ["A tésztát lobogó, enyhén sós vízben fogkeményre kifőzzük.","A szalonnát egy centis darabokra felkockázzuk, serpenyőbe tesszük. Felöntjük annyi vízzel, ami éppen ellepi, és közepes lángon melegíteni kezdjük. Egészen addig folytatjuk, amíg minden csepp víz el nem párolog, sőt utána szép barnára, zsírjára sütjük. (A vízre azért van szükség, mert így kívül ropogós, de belül puha marad.) Ha elkészült, akkor szűrőlapáttal kivesszük a szalonnát, és félretesszük.","A zsírt is kiöntjük, csak három evőkanállal hagyunk benne, ehhez hozzáadjuk a tejfölt, és alaposan elkeverjük.","A kifőtt tésztát összeforgatjuk a tejfölös keverék és a túró egyharmadával, majd a sütőt grill fokozatra és maximum hőfokra állítjuk, és 10-12 percre betesszük, amíg meg nem pirul a tészta széle.","Kivesszük a tésztát a sütőből, átforgatjuk, majd hozzáadjuk a túró és tejföl második harmadát, és újra visszatesszük a sütőbe 10 percre.","Ha kész, azonnal tálaljuk. A tetejét a maradék tejföllel és túróval meglocsoljuk."]
- Eredeti GT: ["1. A tésztát sós vízben főzd fogkeményre.","2. A szalonnát kockázd fel, kevés vízzel kezdd sütni, majd pirítsd zsírjára.","3. A visszamaradt zsír egy részét keverd össze tejföllel.","4. A tésztát forgasd össze a tejfölös keverékkel és a túró egy részével.","5. Grill alatt pirítsd meg, majd add hozzá a maradék túrót és tejfölt, és röviden süsd tovább.","6. A ropogós szalonnával tálald."]

A látható 6 lépés egyezik a JSON-LD-vel; a tálalás tejfölt/túrót említ, nem szalonnát. A weboldalt nem javítjuk főzési tudásból.

## 09 – ingredient 1 – GROUND_TRUTH_ERROR

URL: https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye

Snapshot: html/p1_09.html

- Látható: "1 kg sertéshús (az eredeti recept bélszínt ír)"
- JSON-LD: "1 kg Sertéshús az eredeti recept bélszínt ír"
- Eredeti GT: "1 kg sertéshús"

A látható recept és a JSON-LD azonos információt ad; a referencia átírta a nevet vagy kihagyta a megjegyzést.

## 09 – ingredient 2 – GROUND_TRUTH_ERROR

URL: https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye

Snapshot: html/p1_09.html

- Látható: "15 dkg füstölt szalonna (ízlés szerint)"
- JSON-LD: "15 dkg Füstölt szalonna ízlés szerint"
- Eredeti GT: "15 dkg füstölt szalonna"

A látható recept és a JSON-LD azonos információt ad; a referencia átírta a nevet vagy kihagyta a megjegyzést.

## 09 – ingredient 3 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye

Snapshot: html/p1_09.html

- Látható: "1.5 kg burgonya"
- JSON-LD: "1 kg Burgonya"
- Eredeti GT: "1.5 kg burgonya"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 09 – ingredient 6 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye

Snapshot: html/p1_09.html

- Látható: "só ízlés szerint"
- JSON-LD: "0 ízlés szerint Só"
- Eredeti GT: "só ízlés szerint"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 09 – ingredient 7 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye

Snapshot: html/p1_09.html

- Látható: "bors ízlés szerint"
- JSON-LD: "0 ízlés szerint Bors"
- Eredeti GT: "bors ízlés szerint"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 09 – ingredient 8 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye

Snapshot: html/p1_09.html

- Látható: "majoranna ízlés szerint"
- JSON-LD: "0 ízlés szerint Majoranna"
- Eredeti GT: "majoranna ízlés szerint"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 09 – ingredient 9 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye

Snapshot: html/p1_09.html

- Látható: "kakukkfű ízlés szerint"
- JSON-LD: "0 ízlés szerint Kakukkfű"
- Eredeti GT: "kakukkfű ízlés szerint"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 10 – ingredient 5 – SOURCE_JSONLD_ERROR

URL: https://www.nosalty.hu/recept/sajtos-pogacsa

Snapshot: html/p1_10.html

- Látható: "2.5 dkg friss élesztő"
- JSON-LD: "2 dkg Friss élesztő"
- Eredeti GT: "2.5 dkg friss élesztő"

A #ingredients listában a tört mennyiség / mennyiség nélküli ízlés szerint helyes; a JSON-LD csonkol vagy 0 előtagot illeszt be.

## 10 – ingredient 6 – GROUND_TRUTH_ERROR

URL: https://www.nosalty.hu/recept/sajtos-pogacsa

Snapshot: html/p1_10.html

- Látható: "1 dl tej (langyos)"
- JSON-LD: "1 dl Tej langyos"
- Eredeti GT: "1 dl tej"

A látható recept és a JSON-LD azonos információt ad; a referencia átírta a nevet vagy kihagyta a megjegyzést.

## 10 – instruction 7 markup – FORMAT_DIFFERENCE

URL: https://www.nosalty.hu/recept/sajtos-pogacsa

Snapshot: html/p1_10.html

- Látható: "Lehetőség szerint magas falú tepsibe pakoljuk őket egymástól kb. 2 centire, hogy ne nőjenek össze. 180 fokos sütőben 25 perc alatt készre sütjük."
- JSON-LD: "Lehetőség szerint magas falú tepsibe pakoljuk őket egymástól kb. 2 centire, hogy ne nőjenek össze.\r\n\r\n180 fokos sütőben 25 perc alatt készre sütjük."
- Eredeti GT: ["1. Az élesztőt langyos, enyhén cukros tejben futtasd fel.","2. A lisztet morzsold össze a vajjal és sóval, majd add hozzá a tejfölös tojást és az élesztőt.","3. Gyúrd össze és keleszd körülbelül fél órát.","4. Nyújtsd és hajtogasd többször rövid pihentetésekkel.","5. Nyújtsd kb. 1,5 cm vastagra, kend meg tojással és szórd meg sajttal.","6. Szaggasd ki, majd 180 °C-on süsd nagyjából 25 percig."]

A dekódolt JSON-LD valódi CR/LF sortörést tartalmaz, nem literális backslash-r/backslash-n karaktereket. A P2 korábbi megfogalmazása pontatlan volt. Nincs tartalomveszteség.

## Korlát és döntés

A 21 eredeti sorból 4 referenciahiba, 17 forráshiba. További 2 teljes elkészítés-referencia hibás (06/08); összesen 6 GT-korrekciós egység. A 10 formázási döntés 5 címutótag + 4 &nbsp; + 1 valódi CR/LF sortörés (a P2 literális escape állítása helyesbítve). Az 5 járulékos megjegyzéshiány miatt a teljes megfigyelt forráshibás sorok száma 22. A 03 tésztanév javítása ezért nem teszi az egész receptet hibamentessé.

A snapshot ellenőrzésében további GT-rövidítések is láthatók (pl. tk/teáskanál, zárójelek); nem mennyiségi konverzióval korrigáltuk őket. A nem érintett, tömör instrukciókat ebben a szűk körben nem írtuk át. A corpus nem tekinthető még minden mezőjében szó szerinti átiratnak.

P3 előtt NEM szükséges extractor-módosítás. Mindmegette: ingredient megjegyzések kiesése és címdekoráció. Nosalty: törtcsonkolás és hibás nullás előtag. Ezeket a parser nem állíthatja helyre találgatással.
