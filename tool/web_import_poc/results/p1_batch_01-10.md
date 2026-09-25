# P1 – batch 01–10

2026-09-24T15:08:22.322607Z

Egy sorozatos kérés/URL; retry nincs. Desktop Dart JIT, nem mobilmérés. Ground truth összevetés nem történt. A teljes jelöltek és warnings a JSON-ban; HTML snapshotok későbbi offline P2-höz.

| ID | URL | Status | HTTP | Title | Ingredients | Instructions | JSON-LD | Candidates | Bytes | Fetch ms | Extract ms | Total ms | Warnings / error |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 01 | https://www.mindmegette.hu/recept/rakott-krumpli | SUCCESS | 200 | Rakott krumpli \| Mindmegette.hu | 8 | 22 | 1 | 1 | 1045184 | 251.593 | 97.23 | 348.833 | [] — |
| 02 | https://www.mindmegette.hu/recept/fasirt | SUCCESS | 200 | Fasírt \| Mindmegette.hu | 12 | 8 | 1 | 1 | 1047174 | 131.925 | 32.803 | 164.732 | [] — |
| 03 | https://www.mindmegette.hu/recept/husleves | SUCCESS | 200 | Húsleves \| Mindmegette.hu | 14 | 14 | 1 | 1 | 1032292 | 133.228 | 24.501 | 157.733 | [] — |
| 04 | https://www.mindmegette.hu/recept/eredeti-tiramisu | SUCCESS | 200 | Eredeti tiramisu \| Mindmegette.hu | 7 | 12 | 1 | 1 | 1032949 | 174.552 | 23.019 | 197.574 | [] — |
| 05 | https://www.mindmegette.hu/recept/zserbo-alaprecept | SUCCESS | 200 | Zserbó alaprecept \| Mindmegette.hu | 17 | 8 | 1 | 1 | 1058791 | 1772.921 | 19.178 | 1792.102 | [] — |
| 06 | https://www.nosalty.hu/recept/csirkepaprikas | SUCCESS | 200 | Csirkepaprikás | 10 | 3 | 1 | 1 | 327108 | 1708.071 | 19.006 | 1727.08 | [] — |
| 07 | https://www.nosalty.hu/recept/palacsinta-alaprecept | SUCCESS | 200 | Palacsinta alaprecept | 7 | 3 | 1 | 1 | 357969 | 83.263 | 15.016 | 98.281 | [] — |
| 08 | https://www.nosalty.hu/recept/turos-csusza | SUCCESS | 200 | Túrós csusza | 6 | 6 | 1 | 1 | 321389 | 71.804 | 11.407 | 83.213 | [] — |
| 09 | https://www.nosalty.hu/recept/eredeti-brassoi-apropecsenye | SUCCESS | 200 | Eredeti brassói aprópecsenye | 9 | 5 | 1 | 1 | 327340 | 77.029 | 10.16 | 87.192 | [] — |
| 10 | https://www.nosalty.hu/recept/sajtos-pogacsa | SUCCESS | 200 | Sajtos pogácsa | 10 | 7 | 1 | 1 | 330141 | 1161.92 | 10.854 | 1172.778 | [] — |

## Összesítés

```json
{
  "total_urls": 10,
  "status_counts": {
    "SUCCESS": 10,
    "MULTIPLE_RECIPES": 0,
    "NO_RECIPE": 0,
    "NO_JSON_LD": 0,
    "HTTP_ERROR": 0,
    "FETCH_ERROR": 0,
    "INVALID_JSON_LD": 0,
    "INVALID_RECIPE": 0
  },
  "downloaded_2xx": 10,
  "urls_with_recipe": 10,
  "success_rate_percent": 100,
  "fetch_ms": {
    "average": 556.6306000000001,
    "median": 153.89,
    "min": 71.804,
    "max": 1772.921
  },
  "extract_ms": {
    "average": 26.3174,
    "median": 19.092,
    "min": 10.16,
    "max": 97.23
  },
  "total_ms": {
    "average": 582.9518,
    "median": 181.15300000000002,
    "min": 83.213,
    "max": 1792.102
  },
  "fastest": {
    "id": "08",
    "url": "https://www.nosalty.hu/recept/turos-csusza"
  },
  "slowest": {
    "id": "05",
    "url": "https://www.mindmegette.hu/recept/zserbo-alaprecept"
  }
}
```

## Technikai megfigyelések és ellenőrzések

- 10/10 letöltés HTTP 200; 10/10 oldalon egy JSON-LD blokk és egy Recipe jelölt.
- Minden eset SUCCESS, warnings üres, error null; retry nem történt.
- A SUCCESS strukturális eredmény, nem ground truth pontossági minősítés.
- 01–05 címében a forrás JSON-LD-je tartalmazza a ` | Mindmegette.hu` utótagot. Nem távolítottuk el.
- Az instruction_count megőrzi és számolja a lépéscímeket is: 01: 11 cím + 11 lépés; 02: 4 + 4; 03: 7 + 7; 04: 6 + 6; 05: 4 + 4. A 06–10 esetekben minden bejegyzés step. Ez nem automatikusan duplikációs hiba.
- Az első extract 97,230 ms, a továbbiak 10,160–32,803 ms közöttiek. JIT/bemelegedés és eltérő dokumentumok egyaránt befolyásolhatják; egy mérésből nem különíthetők el.
- A lassú 05, 06 és 10 esetben a fetch dominált. Cache-hit/miss vagy szerveroldali ok a rendelkezésre álló adatokból nem állapítható meg.
- Windows desktop Dart-mérés: nem bizonyítja a közvetlen androidos fetch stabilitását, illetve más domain támogatását.
- P0 offline tesztek: 23/23 PASS. POC dart analyze: PASS. Production flutter analyze: PASS. git diff --check: PASS.
- Production lib/pubspec/lock változatlan. A már meglévő RELEASE_NOTES_DRAFT.md és corpus módosításokhoz nem nyúltunk.

## P2 javasolt belépési pont

A p1_batch_01-10.json jelöltjeit és a html/p1_XX.html snapshotokat kell használni, új hálózati kör nélkül. Kizárólag 01–10 ground truth következhet külön jóváhagyással. Külön mérendő a cím/utótag, nyers hozzávalók tagsága és sorrendje, instrukciócímek és lépések tartalma/sorrendje. A korpusz README szerint az elkészítés tömör, saját megfogalmazású referencia, ezért a szöveges eltérés nem tekinthető automatikusan extraction errornak. P2 nem indult el.
