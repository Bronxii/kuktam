# P3 – RecipeTextParser kompatibilitás, batch 01–10

Csak mentett input, változatlan production parser. Minden sor és minden teljes hozzávalólista `Hozzávalók:` fejléccel futott; ez a parser publikus szöveg API-jának kontextusa, nem P4-import. Nincs hálózat.

```json
{
  "total_rows": 100,
  "source_error_rows": 22,
  "valid_source_rows": 78,
  "correctly_parsed_rows": 67,
  "parser_error_rows": 2,
  "unsupported_rows_all": 12,
  "unsupported_valid_source_rows": 9,
  "unsupported_units": {
    "fej": 2,
    "gerezd": 3,
    "kis kanál": 1,
    "szem": 1,
    "csapott mokkáskanál": 1,
    "csokor": 1,
    "mokkáskanál": 1,
    "csipet": 1,
    "kávéskanál": 1
  },
  "parser_success_valid_source_percent": 85.8974358974359,
  "supported_input_parser_success_percent": 97.10144927536231,
  "source_error_behavior": {
    "invalid_quantity_and_null": 11,
    "missing_quantity_fallback": 1,
    "without_warning": 10
  },
  "valid_input_missing_quantity_fallback_rows": 6,
  "explicit_quantity_accuracy": {
    "correct": 72,
    "denominator": 72
  },
  "quantity": {
    "correct": 78,
    "denominator": 78,
    "note": "Missing quantity uses accepted 1 db fallback; not a claim that the source stated 1."
  },
  "unit": {
    "correct": 69,
    "denominator": 69,
    "not_applicable_unsupported": 9
  },
  "name": {
    "correct": 68,
    "denominator": 78,
    "note": "Unit phrases separated from name; meaningful descriptors/notes retained. Unsupported units included; compare case/whitespace insensitive."
  },
  "timing": {
    "recipe_calls_total_us": 9569,
    "recipe_calls_average_us": 956.9,
    "row_calls_total_us": 5371,
    "row_calls_average_us": 53.71,
    "all_parser_calls_total_us": 14940,
    "note": "Single pass, desktop Dart JIT Stopwatch; first recipe includes cold/JIT cost; row calls run after its recipe call. Not phone/release performance; no IO inside timed regions."
  },
  "coverage_note": "Natural dataset only: positive decimal dot 0.5 dl; no comma quantities, slash/Unicode fractions, kk, explicit l/ml/g→kg threshold or foreign units. Existing production tests cover additional cases but are NOT corpus benchmark evidence."
}
```

| ID | Sor | Forráshiba | Értékelt | Helyes | Parserhiba | Unsupported (értékelt) | Siker % | Idő µs |
|---|---|---|---|---|---|---|---|---|
| 01 | 8 | 0 | 8 | 8 | 0 | 0 | 100.00 | 6261 |
| 02 | 12 | 3 | 9 | 7 | 0 | 2 | 77.78 | 1011 |
| 03 | 14 | 4 | 10 | 7 | 0 | 3 | 70.00 | 351 |
| 04 | 7 | 0 | 7 | 7 | 0 | 0 | 100.00 | 162 |
| 05 | 17 | 0 | 17 | 16 | 0 | 1 | 94.12 | 695 |
| 06 | 10 | 5 | 5 | 3 | 2 | 0 | 60.00 | 272 |
| 07 | 7 | 1 | 6 | 6 | 0 | 0 | 100.00 | 152 |
| 08 | 6 | 3 | 3 | 3 | 0 | 0 | 100.00 | 134 |
| 09 | 9 | 5 | 4 | 3 | 0 | 1 | 75.00 | 286 |
| 10 | 10 | 1 | 9 | 7 | 0 | 2 | 77.78 | 245 |

## Soronkénti bizonyíték

- **01/1** `1 kg Burgonya` → `Burgonya` | 1.0 | kg; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 85 µs.
- **01/2** `6 db Tojás` → `Tojás` | 6.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 73 µs.
- **01/3** `Só` → `Só` | 1.0 | db; warning: [missingQuantity]; source: VALID_SOURCE; parser: FORMAT_ONLY; 29 µs.
- **01/4** `10 dkg Kolbász` → `Kolbász` | 100.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 74 µs.
- **01/5** `5 dl Tejföl` → `Tejföl` | 500.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 55 µs.
- **01/6** `2 db Tojássárgája` → `Tojássárgája` | 2.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 39 µs.
- **01/7** `2 tk Vaj` → `Vaj` | 2.0 | tk; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 36 µs.
- **01/8** `10 dkg Bacon` → `Bacon` | 100.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 37 µs.
- **02/1** `50 dkg sertéshús` → `sertéshús` | 500.0 | g; warning: []; source: SOURCE_ERROR; parser: SUPPORTED_NORMALIZATION; 47 µs.
- **02/2** `2 db zsemle` → `zsemle` | 2.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 39 µs.
- **02/3** `1 fej Vöröshagyma` → `fej Vöröshagyma` | 1.0 | db; warning: []; source: SOURCE_ERROR; parser: UNSUPPORTED_UNIT; 75 µs.
- **02/4** `Olaj` → `Olaj` | 1.0 | db; warning: [missingQuantity]; source: VALID_SOURCE; parser: FORMAT_ONLY; 51 µs.
- **02/5** `3 gerezd Fokhagyma` → `gerezd Fokhagyma` | 3.0 | db; warning: []; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 64 µs.
- **02/6** `2 db Tojás` → `Tojás` | 2.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 252 µs.
- **02/7** `1 kis kanál Majoránna` → `kis kanál Majoránna` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 133 µs.
- **02/8** `1 tk fűszerpaprika` → `fűszerpaprika` | 1.0 | tk; warning: []; source: SOURCE_ERROR; parser: FORMAT_ONLY; 114 µs.
- **02/9** `Só` → `Só` | 1.0 | db; warning: [missingQuantity]; source: VALID_SOURCE; parser: FORMAT_ONLY; 45 µs.
- **02/10** `Bors` → `Bors` | 1.0 | db; warning: [missingQuantity]; source: VALID_SOURCE; parser: FORMAT_ONLY; 52 µs.
- **02/11** `10 dkg Zsemlemorzsa` → `Zsemlemorzsa` | 100.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 54 µs.
- **02/12** `5 dl Olaj` → `Olaj` | 500.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 39 µs.
- **03/1** `1 kg színhús` → `színhús` | 1.0 | kg; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 47 µs.
- **03/2** `50 dkg csont` → `csont` | 500.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 41 µs.
- **03/3** `50 dkg vegyes zöldség` → `vegyes zöldség` | 500.0 | g; warning: []; source: SOURCE_ERROR; parser: SUPPORTED_NORMALIZATION; 43 µs.
- **03/4** `1 fej Hagyma` → `fej Hagyma` | 1.0 | db; warning: []; source: SOURCE_ERROR; parser: UNSUPPORTED_UNIT; 63 µs.
- **03/5** `2 gerezd Fokhagyma` → `gerezd Fokhagyma` | 2.0 | db; warning: []; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 49 µs.
- **03/6** `10 szem Bors` → `szem Bors` | 10.0 | db; warning: []; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 41 µs.
- **03/7** `cseresznyepaprika` → `cseresznyepaprika` | 1.0 | db; warning: [missingQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 27 µs.
- **03/8** `1 csapott mokkáskanál szeklice` → `csapott mokkáskanál szeklice` | 1.0 | db; warning: []; source: SOURCE_ERROR; parser: UNSUPPORTED_UNIT; 40 µs.
- **03/9** `1 csokor Petrezselyem` → `csokor Petrezselyem` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 40 µs.
- **03/10** `15 dkg Kelkáposzta` → `Kelkáposzta` | 150.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 38 µs.
- **03/11** `1 db Zöldpaprika` → `Zöldpaprika` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 447 µs.
- **03/12** `1 db Paradicsom` → `Paradicsom` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 54 µs.
- **03/13** `Só` → `Só` | 1.0 | db; warning: [missingQuantity]; source: VALID_SOURCE; parser: FORMAT_ONLY; 28 µs.
- **03/14** `10 dkg levelestészta` → `levelestészta` | 100.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 41 µs.
- **04/1** `4 db Tojás` → `Tojás` | 4.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 42 µs.
- **04/2** `20 dkg Porcukor` → `Porcukor` | 200.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 39 µs.
- **04/3** `1 dl Rum` → `Rum` | 100.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 35 µs.
- **04/4** `50 dkg Mascarpone` → `Mascarpone` | 500.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 38 µs.
- **04/5** `3 dl kávé` → `kávé` | 300.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 33 µs.
- **04/6** `1 doboz Babapiskóta` → `Babapiskóta` | 1.0 | doboz; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 133 µs.
- **04/7** `Kakaópor` → `Kakaópor` | 1.0 | db; warning: [missingQuantity]; source: VALID_SOURCE; parser: FORMAT_ONLY; 32 µs.
- **05/1** `25 dkg Darált dió` → `Darált dió` | 250.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 44 µs.
- **05/2** `20 dkg Porcukor` → `Porcukor` | 200.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 36 µs.
- **05/3** `1 db Citrom` → `Citrom` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 32 µs.
- **05/4** `1 csomag Vaníliás cukor` → `Vaníliás cukor` | 1.0 | csomag; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 33 µs.
- **05/5** `40 dkg Baracklekvár` → `Baracklekvár` | 400.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 48 µs.
- **05/6** `2 ek Rum` → `Rum` | 2.0 | ek; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 34 µs.
- **05/7** `1 dkg Élesztő` → `Élesztő` | 10.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 46 µs.
- **05/8** `0.5 dl Tej` → `Tej` | 50.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 36 µs.
- **05/9** `50 dkg Liszt` → `Liszt` | 500.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 34 µs.
- **05/10** `25 dkg Margarin` → `Margarin` | 250.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 32 µs.
- **05/11** `1 mokkáskanál Szódabikarbóna` → `mokkáskanál Szódabikarbóna` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 36 µs.
- **05/12** `10 dkg Porcukor` → `Porcukor` | 100.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 32 µs.
- **05/13** `1 db Tojássárgája` → `Tojássárgája` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 83 µs.
- **05/14** `1 csomag Vaníliás cukor` → `Vaníliás cukor` | 1.0 | csomag; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 52 µs.
- **05/15** `2 ek Tejföl` → `Tejföl` | 2.0 | ek; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 34 µs.
- **05/16** `15 dkg Étcsokoládé` → `Étcsokoládé` | 150.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 36 µs.
- **05/17** `1 tk Étolaj` → `Étolaj` | 1.0 | tk; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 32 µs.
- **06/1** `6 db Csirke alsócomb` → `Csirke alsócomb` | 6.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 37 µs.
- **06/2** `0 ek Sertészsír` → `Sertészsír` | null | ek; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 34 µs.
- **06/3** `0 közepes db Vöröshagyma` → `közepes db Vöröshagyma` | null | db; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: PARSER_ERROR; 78 µs.
- **06/4** `0 teáskanál Fűszerpaprika` → `Fűszerpaprika` | null | tk; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 47 µs.
- **06/5** `1 közepes db Zöldpaprika` → `közepes db Zöldpaprika` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: PARSER_ERROR; 40 µs.
- **06/6** `1 közepes db Paradicsom` → `közepes db Paradicsom` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: PARSER_ERROR; 52 µs.
- **06/7** `200 g Tejföl` → `Tejföl` | 200.0 | g; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 51 µs.
- **06/8** `1 ek Finomliszt` → `Finomliszt` | 1.0 | ek; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 33 µs.
- **06/9** `0 ízlés szerint Só` → `ízlés szerint Só` | null | db; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 50 µs.
- **06/10** `0 ízlés szerint Bors` → `ízlés szerint Bors` | null | db; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 88 µs.
- **07/1** `3 db Tojás` → `Tojás` | 3.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 31 µs.
- **07/2** `2 ek Cukor` → `Cukor` | 2.0 | ek; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 30 µs.
- **07/3** `1 csomag Vaníliás cukor` → `Vaníliás cukor` | 1.0 | csomag; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 57 µs.
- **07/4** `240 g Finomliszt` → `Finomliszt` | 240.0 | g; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 36 µs.
- **07/5** `4 dl Tej` → `Tej` | 400.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 143 µs.
- **07/6** `3 dl Szódavíz` → `Szódavíz` | 300.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 51 µs.
- **07/7** `0 dl Napraforgó olaj` → `Napraforgó olaj` | null | ml; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: SUPPORTED_NORMALIZATION; 39 µs.
- **08/1** `40 dkg Csuszatészta` → `Csuszatészta` | 400.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 35 µs.
- **08/2** `0 ízlés szerint Só` → `ízlés szerint Só` | null | db; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 71 µs.
- **08/3** `350 g Füstölt szalonna` → `Füstölt szalonna` | 350.0 | g; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 52 µs.
- **08/4** `2 dl Víz` → `Víz` | 200.0 | ml; warning: []; source: SOURCE_ERROR; parser: SUPPORTED_NORMALIZATION; 36 µs.
- **08/5** `2 dl Tejföl` → `Tejföl` | 200.0 | ml; warning: []; source: SOURCE_ERROR; parser: SUPPORTED_NORMALIZATION; 51 µs.
- **08/6** `450 g Tehéntúró` → `Tehéntúró` | 450.0 | g; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 41 µs.
- **09/1** `1 kg Sertéshús az eredeti recept bélszínt ír` → `Sertéshús az eredeti recept bélszínt ír` | 1.0 | kg; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 48 µs.
- **09/2** `15 dkg Füstölt szalonna ízlés szerint` → `Füstölt szalonna ízlés szerint` | 150.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 112 µs.
- **09/3** `1 kg Burgonya` → `Burgonya` | 1.0 | kg; warning: []; source: SOURCE_ERROR; parser: FORMAT_ONLY; 82 µs.
- **09/4** `2 db Vöröshagyma` → `Vöröshagyma` | 2.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 33 µs.
- **09/5** `8 gerezd Fokhagyma` → `gerezd Fokhagyma` | 8.0 | db; warning: []; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 35 µs.
- **09/6** `0 ízlés szerint Só` → `ízlés szerint Só` | null | db; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 35 µs.
- **09/7** `0 ízlés szerint Bors` → `ízlés szerint Bors` | null | db; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 32 µs.
- **09/8** `0 ízlés szerint Majoranna` → `ízlés szerint Majoranna` | null | db; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 32 µs.
- **09/9** `0 ízlés szerint Kakukkfű` → `ízlés szerint Kakukkfű` | null | db; warning: [invalidQuantity]; source: SOURCE_ERROR; parser: FORMAT_ONLY; 48 µs.
- **10/1** `20 dkg Vaj` → `Vaj` | 200.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 32 µs.
- **10/2** `40 dkg Finomliszt` → `Finomliszt` | 400.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 32 µs.
- **10/3** `2 db Tojás` → `Tojás` | 2.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 30 µs.
- **10/4** `2 dl Tejföl` → `Tejföl` | 200.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 27 µs.
- **10/5** `2 dkg Friss élesztő` → `Friss élesztő` | 20.0 | g; warning: []; source: SOURCE_ERROR; parser: SUPPORTED_NORMALIZATION; 39 µs.
- **10/6** `1 dl Tej langyos` → `Tej langyos` | 100.0 | ml; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 32 µs.
- **10/7** `1 csipet Cukor` → `Cukor` | 1.0 | db; warning: [unknownUnit]; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 30 µs.
- **10/8** `1 kávéskanál Só` → `kávéskanál Só` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: UNSUPPORTED_UNIT; 29 µs.
- **10/9** `15 dkg Sajt` → `Sajt` | 150.0 | g; warning: []; source: VALID_SOURCE; parser: SUPPORTED_NORMALIZATION; 27 µs.
- **10/10** `1 db Tojás a kenéshez` → `Tojás a kenéshez` | 1.0 | db; warning: []; source: VALID_SOURCE; parser: FORMAT_ONLY; 29 µs.

## Értelmezés

A nem támogatott mennyiségi szavak többsége a névben marad db fallback mellett, warning nélkül; csipet esetén explicit unknownUnit és db fallback van. Ezeket nem keverjük a támogatott input parserhibáival. A fej/gerezd/szem/csokor nem automatikusan felcserélhető db-vel, a különböző kanalakat sem szabad önkényesen tk-vá alakítani.

A `1 közepes db ...` két helyes forrássornál a db szó a névben marad: a parser csak a számot közvetlenül követő unitot keresi. A közepes jelző megőrzendő, a db a unit mezőbe tartozik. Ez a benchmark névszétválasztási hibakritériuma; nem adatvesztés.

A hibás 0 inputok invalidQuantity warningot és null quantityt kapnak; a pozitívra csonkolt forrásmennyiségek hibaüzenet nélkül normalizálódhatnak. A parser nem tudja rekonstruálni a forrásból hiányzó törtet/megjegyzést.

Legkisebb későbbi javítási irány: ismert, nem canonical mennyiségi szavak következetes unknownUnit figyelmeztetése és rawText-megőrzés; külön, tesztelt szabály a jelzővel elválasztott canonical db felismerésére. Többszavas kanálkifejezések és unit-szemantika termékdöntést igényelnek, nem vak aliasbővítést.

P4 felügyelt, szerkeszthető szimulációra alkalmas külön jóváhagyással; megbízható automatikus mentésre nem. Production parser nem módosult.
