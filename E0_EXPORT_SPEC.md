# E0 – Export audit és E1 specifikáció

Állapot: DESIGN ONLY. Csak ez a dokumentum készült; teszt/build nem futott.
Javaslat: **Free, Android V1: minden saját recept → egy ZIP**, JSON + UTF-8 TXT.

## 1. Auditált jelenlegi modell

Források: recipe.dart, recipe_repository.dart, add_recipe_screen.dart,
recipe_details_screen.dart, shopping_repository.dart, settings_screen.dart,
pubspec.yaml/lock és Android share infrastruktúra. Élő Firestore nem lett olvasva.

- Recipe: id? (Firestore doc ID), name: String, ingredients: lista,
  spices: lista, preparation: String.
- Ingredient: name: String, quantity: double, unit: String.
- Spice: csak name: String; nincs mennyiség vagy mértékegység.
- Firestore út: users/{uid}/recipes/{id}. A recipe.toMap() a tartalmi mezőket írja;
  create createdAt, update updatedAt szerver timestampet ad hozzá.
- A domain a timestamp mezőket nem tartalmazza. A create/edit a szövegmezőket
  trimeli, a listák sorrendjét megőrzi; az import mentése ugyanide vezet.
- Nincs tárolt adag, kép, URL, kategória vagy import-eredeti szöveg a Recipe-ben.
  Ezeket nem szabad az exporthoz kitalálni.
- Receptenkénti szövegmegosztás már van a details screen privát formatterében:
  név, Hozzávalók, opcionális Fűszerek, Elkészítés, Kuktám footer.
  ZIP/file-export és felhasználó által választott fájlmentési helper nincs.

## 2. V1 tartalom / kizárások

Exportálható: name, ingredients[{name, quantity, unit}], spices[{name}], preparation.
A JSON őrizze meg a tárolt szöveget, számpontosságot, egységet és listasorrendet;
export közben nincs egységkonverzió, default-pótlás vagy parseren átvezetés.
Külön explicit allowlist DTO készüljön, ne nyers Firestore map export.

Kizárt: doc ID, UID, email, auth/purchase token, entitlement/grant/billing/HMAC,
account lifecycle, createdAt/updatedAt és más backend metadata. Doc ID nem kell
új receptként történő későbbi restore-hoz. Belső rendezési tie-breakhez használható,
a ZIP-be nem kerül. A user receptszövegében saját maga által megadott személyes
szöveget nem cenzúrázzuk; azt a user-adat részeként exportáljuk.

V1 shopping: **nem kerül bele**. Az aktuális pipált/pipálatlan lista átmeneti állapot,
külön restore/merge döntéseket igényel. A shopping modell name/quantity/unit/
isChecked mezői későbbi verzióhoz rendelkezésre állnak. UI alcím: „Összes recept
exportálása”; ne ígérje az összes account-adat teljes mentését.

## 3. ZIP és verziózott JSON

```text
Kuktam-receptek-YYYYMMDD-HHmmssZ.zip
├── recipes.json
├── export_info.txt
└── receptek/
    ├── 000001-Túrós lepény.txt
    └── 000002-....txt
```

recipes.json maga a manifest; külön manifest.json nem szükséges.
UTF-8 BOM nélkül, két szóközös JSON indent, LF sorvég, lezáró newline.
Példa (illusztratív recept, nem kinyert felhasználói adat):

```json
{
  "format": "kuktam.recipes",
  "exportVersion": 1,
  "exportedAt": "2026-10-10T12:00:00Z",
  "appVersion": "1.0.0",
  "appBuild": "1",
  "recipes": [
    {
      "textFile": "receptek/000001-Túrós lepény.txt",
      "name": "Túrós lepény",
      "ingredients": [{"name": "túró", "quantity": 500.0, "unit": "g"}],
      "spices": [{"name": "só"}],
      "preparation": "Keverd össze.\nSüsd készre."
    }
  ]
}
```

textFile kizárólag exporton belüli kapcsolat, nem új receptmező. Az exportVersion
az egész export sémáját verziózza; ne vezessünk be fiktív Firestore schemaVersiont.
Az appVersion/build runtime PackageInfo-ból, exportedAt injektálható UTC clockból.
recipeCount redundáns mező nem kell; a tömb hosszából számítható.
export_info.txt: formátumverzió, UTC idő, darabszám, receptek-only tartalom,
„A gépi visszaállítás alapja a recipes.json; restore még nincs az appban.”

## 4. Pontos TXT példa

```text
Túrós lepény

Hozzávalók:
• túró – 500 g

Fűszerek:
• só

Elkészítés:
Keverd össze.
Süsd készre.

──────────────
Készült a Kuktám alkalmazással
```

Meglévő share-formátumhoz igazodik. Üres spices/preparation szakasz kihagyható,
a JSON-ban viszont üres lista/szöveg is szerepel. Mennyiséghez formattedQuantity
használható kerekítés nélkül. TXT emberi olvasatra szolgál: nem garantált veszteség-
mentes parser round-trip (pl. fűszerek, szakaszcímnek látszó user-szöveg). A JSON az
irányadó. E1-ben pure export formatter; a jelenlegi share formatter refaktora nem kell.

## 5. Fájlnevek és determinisztikusság

- Receptsorrend: meglévő compareHungarianRecipeNames; holtversenyben belső doc ID.
- Prefix 1-től, legalább 6 számjegy (nagyobb darabszámhoz szélesedik): collision-safe.
- A névrészben / \ : * ? " < > |, vezérlők és bidi-format vezérlők → `_`;
  whitespace futam → szóköz; záró pont/szóköz levágása; üres névrész → `Recept`.
- Magyar ékezet/Unicode megmarad. Maximum 120 UTF-8 bájt a névrészre,
  code-point határon vágva, nem fél UTF-16 surrogate-nál. Prefix miatt Windows
  reserved nevek sem lesznek önálló basename-ek. Ékezetes ZIP-nevekhez UTF-8 flag.
- Csak fix `receptek/` alatti relatív út, nincs userből vett path vagy `..` komponens.
- Azonos snapshot azonos belső neveket kap. ZIP byte-azonosság nem cél az exportidő miatt.

## 6. Adatforrás / offline / session

V1: online, teljes server query egyetlen kollekció-snapshotból, filter/orderBy nélkül.
A mai getRecipes() alapértelmezett .get()-je vagy UI streamje nem megfelelő
„teljes mentés” garanciának: cache fallback/hiányos cache lehetséges.
Új export-only snapshot reader: rögzített aktuális UID/session → bounded timeouttal
waitForPendingWrites → get(GetOptions(source: Source.server)) → cache/pending-write
metadata ellenőrzés → strict domain/DTO mapping → memóriában rögzített snapshot.

Offline, timeout, permission vagy malformed dokumentum: az egész export álljon meg,
érthető retryval; ne legyen csendes részexport/skipped recept. Üres szervereredmény
érvényes export recipes: []-val. Nincs üzleti receptdarab-limit.
Auth UID/session generáció ellenőrzés minden await után és átadás előtt; logout,
accountváltás (A→B→A is) vagy deletion alatt abort. UID csak belső context, nem exportadat.
A helyi, még el nem mentett editor draft nem része. Más készülék későbbi módosítása
sem része: ez az olvasott snapshot mentése, nem globális szerkesztési zárolás.
Ne lapozzunk V1-ben több külön időpontú queryre teljességi garancia nélkül.

## 7. Android UX és függőségek

Beállítások → Saját adatok exportálása (alcím: Összes recept, JSON + TXT ZIP).
Egy folyamat egyszerre: betöltés/szinkronizálás → ZIP készül → Mentés / Megosztás.
Cancel/hiba ne írjon receptadatot. Megosztás eredménye nem bizonyítja a külső mentést.

- JSON: dart:convert; file: dart:io; háttér ZIP-építés isolate-ban a UI megakadás ellen.
- share_plus **13.2.1** már közvetlen dependency; ShareParams.files + XFile ZIP MIME-mal.
- package_info_plus **10.2.1** már közvetlen dependency.
- archive **4.0.9**, path_provider **2.1.6**, cross_file **0.3.5+4** már lockolt
  tranzitív package-ek. E1-ben amelyikből közvetlen import lesz, azt ugyanilyen
  verzióval direct dependencyként deklaráljuk; ne támaszkodjunk véletlen tranzitívre.
- ZIP-hez archive direct szükséges; app-private temp fájlhoz path_provider direct;
  XFile-hoz share_plus exportja használható, külön cross_file import esetén direct kell.
  E0-ban ezek egyike sem változik, upgrade nem javasolt.
- Garantált helyi „Mentés” gomb: kis Android ACTION_CREATE_DOCUMENT / CATEGORY_OPENABLE
  / application/zip híd, EXTRA_TITLE-lel; user által választott content URI-ra másolás.
  Nincs saját file manager és broad storage permission. A share sheet önmagában
  nem garantál mentési célpontot, ezért ne nevezzük automatikusan fájlmentésnek.
- Export saját temp alkönyvtárban, nem logolva; sérült/félkész fájl hibánál törölhető.
  Share után ne töröljük azonnal: fogadó még olvashatja. E1-ben ellenőrizni kell a
  plugin cache-másolatát is; kizárólag saját export artifactokra szűkített takarítás,
  aktív átadást nem bontva. Külső elmentett fájl a user kezelésében marad.

## 8. Restore, kockázatok, E1 elfogadás

Restore később JSON schema alapján, külön verzió-dispatch/migráció, explicit
névütközés-policy, új doc ID-k. textFile nem importer által megbízható disk path.
Nincs automatikus account-binding vagy backup-visszaírás V1-ben. CRC a ZIP-ben
sérülésdetektálás, nem hitelességi aláírás; titkosítást ne ígérjünk.

Kockázatok: nagy receptkönyv memória/ZIP idő, disk-full, share target inkompatibilitás,
SAF cancel/URI write failure, auth switch, még pending write, hibás régi dokumentum,
NaN/Infinity (JSON-ban nem megengedett), rendkívül hosszú név, azonos nevek,
Unicode és receptszövegbe írt szakaszcímek. Ne legyen hallgatólagos adatcsonkolás.
Tesztek E1-ben: JSON decode-egyezés, ZIP megnyitás és fájlegyezés, TXT snapshot,
privacy allowlist, filename traversal/collision/Unicode, 0/1/sok recept, offline és
pending-write hiba, sessionváltás, share/save cancel/hiba, dupla tap és UI responsive.

## E1 IMPLEMENTATION PLAN

1. Export DTO/schema + tesztfixture: lib/export/domain/recipe_export.dart.
2. Szigorú server snapshot/session olvasó: lib/export/data/recipe_export_source.dart;
   meglévő RecipeRepository normál CRUD/read viselkedését ne módosítsuk.
3. Pure TXT formatter és filename policy: lib/export/domain/recipe_export_formatter.dart.
4. Verziózott JSON + ZIP encoder: lib/export/domain/recipe_export_encoder.dart;
   fenti direct dependency deklarációk pubspec.yaml/lock-ban, upgrade nélkül.
5. Temp artifact + share/save gateway: lib/export/data/export_file_gateway.dart.
6. Android SAF híd külön export channelen: MainActivity.kt és szükség szerint
   új ExportDocumentWriter.kt; A1 share fogadást ne keverjük össze vele.
7. UI/state orchestration: lib/export/presentation/recipe_export_controller.dart;
   session-fencing, busy/cancel/error, átadás előtti ellenőrzés.
8. SettingsScreen új Free export action és kompakt progress/result UI;
   érintett fájl lib/settings/settings_screen.dart, nincs monetizációs gate.
9. test/export/ unit/widget/gateway tesztek, szükséges Android hídteszt;
   célzott auth/settings regresszió, analyze, debug build, készülékes ZIP megnyitás.
10. E1_REPORT.md: ellenőrzött eredmények, méret/performance korlátok, manuális
    Save/Share checklist; restore és további roadmap nélkül lezárás.

Technikai források (tervezési ellenőrzés, nincs élő adatlekérés):
- [share_plus fájlmegosztás és cache](https://pub.dev/packages/share_plus)
- [Firestore read source](https://firebase.google.com/docs/firestore/query-data/get-data)
- [Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)

IMPLEMENTATION: NOT STARTED
SOURCE CHANGES: NONE
DEPENDENCY CHANGES: NONE
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
COMMIT: NONE
PUSH: NONE
