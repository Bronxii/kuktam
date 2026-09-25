# Web import POC — P0

Izolált Dart CLI, nem Flutter feature. Nincs production import, Firebase, AI,
OCR, browser automation vagy kapcsolat a RecipeTextParserrel.
A production pubspec és lib változatlan. A meglévő web_import_corpus fájlokhoz
nem írunk. P0 során egyetlen korpusz-URL-t sem kérünk le.

## Ellenőrzés

A `tool/web_import_poc` könyvtárban:

```powershell
dart pub get
dart test
dart analyze
```

Minden teszt helyi HTML/JSON fixture-t vagy injektált fake fetchert használ.
Az HTTP kliens tényleges hálózati működését és az oldalak elérhetőségét P0 nem
minősíti; ezek P1-ben mérendők.

## Egy URL futtatása — csak a következő fázis jóváhagyása után

```powershell
Set-Location C:\Users\gabor\kuktam\tool\web_import_poc
$recipeUrl = (Get-Content -Raw ..\..\test\fixtures\web_import_corpus\batch_1_01-10\website_01.txt).Trim()
dart run bin/extract.dart $recipeUrl
```

Ez pontosan egy URL-t dolgoz fel, JSON eredményt ír stdout-ra. Nem olvassa be
automatikusan a korpuszt. P1 jóváhagyása után kizárólag a 01–10 fájlpárokhoz
kell ezt egymás után meghívni és elmenteni az eredményeket; a batch-összesítő,
átlag/medián/min/max riport még P1 feladat. A 11–30 oldalakhoz nem nyúlhatunk
annak külön engedélyezése nélkül. P0-ban ez a parancs NEM volt lefuttatva.

## Felépítés

- `lib/extractor.dart`: tiszta HTML/JSON-LD feldolgozás és jelöltek.
- `lib/runner.dart`: egy URL letöltése, hibastátusz, Stopwatch mérések.
- `bin/extract.dart`: egyetlen explicit HTTP(S) URL parancssori adaptere.
- `test/fixtures/structures.json`: közvetlen, graph, típuslista, szöveg/lépés/szakasz fixture-k.
- `test/fixtures/multiple.html`: több script és több jelölt.
- `test/extractor_test.dart`: offline regresszió és runner fake-ek.

Egyetlen közvetlen runtime dependency: `html` (HTML5 parser, hogy ne regex
próbálja kinyerni a script blokkokat). A HTTP, JSON és Stopwatch a Dart SDK része.
A `test` kizárólag a POC dev dependencyje. Saját pubspec.lock rögzíti a feloldást.

## Pontossági szerződés

- Minden megfelelő MIME-típusú script vizsgálva, dokumentumsorrendben.
- Közvetlen objektum, gyökértömb, @graph és más beágyazott objektumok bejárása.
- Recipe @type string/tömb, továbbá teljes http(s) schema.org típus-URI.
- Több jelölt esetén nincs választás és nincs deduplikálás.
- Hozzávalók változatlan stringek: whitespace, tört, egység és sorrend megmarad.
- String instructions nem kerül mondatokra vagy sorokra feldarabolásra.
- Lista, HowToStep, HowToSection és beágyazott itemListElement sorrendben lapul.
- Szakaszcímek `section`, lépéscímek `heading`, szövegek `step` típusú bejegyzések.
- Az `instruction_count` minden szöveges bejegyzést, a címeket is számolja.
- `preparation` a bejegyzések újsorral összefűzött szövege.
- Az eredeti name/recipeIngredient/recipeInstructions értékek külön megmaradnak.
- Nem támogatott részek warningot és érvénytelen jelöltet eredményeznek:
  a részleges eredmény nem jelent SUCCESS-t.
- HTML-tag vagy entity az instrukciós JSON-stringen belül változatlan marad;
  P0 nem tisztítja és nem jeleníti meg HTML-ként.

## Státuszok

FETCH_ERROR: URL/kapcsolat/timeout/méret/karakterkódolási hiba.
HTTP_ERROR: nem 2xx HTTP válasz.
NO_JSON_LD: nincs megfelelő script.
NO_RECIPE: érvényes JSON-blokkokban nincs Recipe.
INVALID_JSON_LD: hibás blokk vagy bejárási mélységlimit.
MULTIPLE_RECIPES: több jelölt, mind megjelenik valid flaggel.
INVALID_RECIPE: egyetlen jelölt hiányos vagy nem támogatott tartalmú.
SUCCESS: egyetlen érvényes jelölt, hibás JSON-blokk nélkül.

Precedencia: fetch/HTTP hiba; utána NO_JSON_LD, MULTIPLE_RECIPES,
INVALID_JSON_LD, NO_RECIPE, INVALID_RECIPE, SUCCESS.
Hibás és jó blokk együtt: a jó jelölt megmarad, de nem SUCCESS.
Több jelölt és hibás blokk együtt: MULTIPLE_RECIPES + blokk-warning.
Ez szándékosan konzervatív, az eredmények későbbi értelmezéséhez fontos.

## Időmérés és korlátok

Stopwatch, mikrosekundum felbontásból számított milliszekundum:

- fetch_ms: kérés, redirect, választest és dekódolás;
- extract_ms: HTML-parsing, JSON-parsing, jelöltek feldolgozása;
- total_ms: teljes futás, eredmény JSON-szerializálása/kiírása nélkül.

HTTP státusz, letöltött/dekompresszált HTML byte-méret, végső URL,
JSON-LD blokkszám és jelöltszám is szerepel. Nem wire/compressed byte-méretet mérünk.
20 s kapcsolódási és 30 s teljes fetch timeout, legfeljebb 5 redirect,
5 MiB response body, 100 szintű feldolgozási mélység. TLS ellenőrzés bekapcsolva.
Túllépésnél hiba, nem csonkítás. Fejléces charsetet használunk; ennek hiányában
szigorú UTF-8-at. Ismeretlen charset hibát ad, nincs néma karaktercsere.
HTML meta charset sniffing, JS-renderelés, login/cookie/CAPTCHA, @id referenciák
feloldása, JSON-LD context/alias expansion és DOM-fallback nincs.

Ez helyben futó fejlesztői CLI, nem nyilvános URL-fetch szolgáltatás.
Szerverre kitétel előtt külön SSRF/DNS/redirect-védelem szükséges.
Valódi webes pontosság, megbízhatóság és sebesség P0-ból nem következik.
Ground truth összehasonlítás, parser-integráció és corpus benchmark még nincs.
