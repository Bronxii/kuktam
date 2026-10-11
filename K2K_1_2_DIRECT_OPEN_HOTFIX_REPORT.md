# K2K-1.2 – Direct open hotfix

## Verdict

DIRECT ACTION_VIEW: FIXED (local implementation/tests)
MESSENGER DIRECT OPEN: READY FOR RETEST

## ROOT CAUSE

A K2K-1.1 MainActivity a receiveRecipe legelején a RecipeFileInbox.supports(action, MIME, scheme, URI path) alapján döntött. Generic MIME esetén kötelező volt a .kuktamrecipe végű URI path. Opaque provider URI esetén false eredménnyel csendben kilépett, a DISPLAY_NAME-ot soha nem kérdezte le. A receiveText ACTION_VIEW esetén szintén visszatért: nem keletkezett sem event, sem hibaüzenet. A VIEW URI-t csak intent.data-ból vette, ClipData fallback nem volt.

Ez bizonyított forráskódbeli kiesési pont, amelyet a javítás és az opaque-URI regression contract teszt lefed. A konkrét Messenger intent MIME/URI metadata nem lett telefonról rögzítve; nem állítjuk, hogy annak pontos tartalmát megmértük. A felhasználói smoke szerint a chooser és SAF működik; a direct open új builddel még ellenőrizendő.

## Javítás

- ACTION_VIEW routing nem követel exact MIME-ot vagy fájlnevet az URI pathban.
- URI: intent.data, illetve annak hiányában egyetlen ClipData item URI-ja; SEND esetén EXTRA_STREAM, majd ugyanilyen ClipData fallback.
- SEND továbbra is custom K2K MIME; text SEND és SEND_MULTIPLE kezelés nem szélesedett.
- MIME rögzítése az intent egyszeri consumptionje előtt, mert data törlése type-ot is törölhet.
- Content URI ellenőrzés után worker threaden ugyanaz a RecipeUriReader fut direct és SAF esetén.
- ContentResolver query: OpenableColumns.DISPLAY_NAME; nincs valódi filesystem-path feloldás.
- Generic/hiányzó/eltérő MIME mellett .kuktamrecipe display name vagy URI path kell. Custom MIME direct megnyitásnál név nélkül is továbbadható; a strict decoder továbbra is kötelező.
- SAF megtartja a név-követelményét. Metadata-lekérdezési hibánál csak a meglévő suffix/custom-MIME szabály enged tovább; egyébként kontrollált format hiba.
- Közös bounded olvasás: maximum 256 KiB, stream bezárása siker és hiba után.
- Read/size/format hiba strukturált event; nincs új csendes visszatérés a felismert VIEW útban.
- Flutter oldalon változatlan strict UTF-8/JSON + format=kuktam.recipe + version=1 + teljes mező/domain validáció.
- A meglévő structured receiver, újrecept-editor és explicit mentés marad. Nincs külön decoder/import.

## Cold/warm és channel

Mind onCreate(initial), mind onNewIntent ugyanazt a receiveRecipe függvényt használja. Az intent egyszer fogy el; Activity restore nem játssza újra. A meglévő process-local queue a channel előtt is tárolja a begin/complete eseményeket; Flutter start() eleve drainel. Warm completion pending értesítést ad. Nem találtunk bizonyított channel-ready rést, ezért új handshake/queue nem készült.

A meglévő event-ID dedupe, login pending, session-generation fencing megmaradt. Process death tartós recovery továbbra sem scope.

## Security / scope

A manifest ebben a hotfixben NEM változott. Nincs generic */* vagy általános JSON handler. Explicit módon kézbesített VIEW esetén is csak content URI olvasható; MIME/név nem helyettesíti a strict decoder validációját. Random bináris vagy átnevezett JSON nem válik receptté.

Nincs új naplózás: JSON, receptszöveg, URI és személyes adat nem kerül logba. Nincs webfetch, backend, Firebase, schema, monetizáció vagy dependency változás.

## Érintett fájlok ebben a hotfixben

- android/app/src/main/kotlin/com/bronxii/kuktam/MainActivity.kt
- android/app/src/main/kotlin/com/bronxii/kuktam/RecipeDocumentPicker.kt
- android/app/src/main/kotlin/com/bronxii/kuktam/RecipeUriReader.kt (új ContentResolver adapter)
- android/app/src/main/java/com/bronxii/kuktam/RecipeDocumentRead.java (új közös, tesztelhető olvasási contract)
- android/app/src/test/java/com/bronxii/kuktam/RecipeDocumentReadTest.java (új)
- K2K_1_2_DIRECT_OPEN_HOTFIX_REPORT.md

A korábbi K2K-1/K2K-1.1 munkafájlok már módosított/untracked állapotban voltak; megőrizve. A teljes git diff nem kizárólag K2K-1.2.

## Teszteredmények

- Célzott K2K/A1 sharing, E1 export és recipe core: **162 PASS**.
- Teljes Flutter suite: **1253 PASS / 1 korábbi skipped**.
- Flutter analyze --no-pub: **CLEAN**.
- Android debug build: **PASS**; build/app/outputs/flutter-apk/app-debug.apk.
- git diff --check: **PASS**.
- Öt natív Java contract harness: **PASS** (RecipeDocumentRead, RecipeFileInbox, TextShareInbox, ExportCopy, ExportDocumentContract).
- Új natív coverage: custom/fallback/null MIME, opaque URI + provider display name, filename nélküli URI path, custom MIME név nélkül, SAF shared reader, nem-content elutasítás, random JSON név elutasítás, metadata/read hiba, oversized és stream close; cold queue channel nélkül, későbbi take, warm split completion, once-only consumption.
- Meglévő Flutter bridge test: start előtti pending → drain egyszer; warm pending → új event; nincs text-import routing. Meglévő codec tests: malformed, wrong format/version; Settings picker/editor; outbound; login/session; explicit mentés.
- A Java harness a ContentResolver adapter alatti contractot fake dokumentummal teszteli. A valódi provider query/ClipData/Activity callback és chooser út Android builddel ellenőrzött, de fizikai végponttól végpontig smoke még nincs. Ezért Messenger státusz READY FOR RETEST, nem telefonon igazolt PASS.
- Korábbi cloud_functions/Kotlin buildfigyelmeztetés továbbra is fennáll; nem hotfix scope.

## Kötelező telefonos retest

Telepítsd az új debug APK-t, majd:

A) Messenger → .kuktamrecipe tap → chooser → Kuktám → editor MUST open.

B) Kuktám force-stop → Messenger direct open → editor once.

C) Kuktám already running → Messenger direct open → editor once.

D) Settings → Kuktám recept importálása → továbbra is PASS.

Mindegyiknél ellenőrizd a pontos előtöltött tartalmat; megnyitáskor nincs automatikus mentés. Cancel után ne nyíljon újra magától. Ha elutasítás jelenik meg, annak rövid magyar üzenete segít a következő hibapont elkülönítésében; receptet/URI-t nem kell naplózni.

ROOT CAUSE: EARLY MIME/URI-PATH REJECTION BEFORE PROVIDER DISPLAY_NAME LOOKUP; MISSING CLIPDATA FALLBACK
DIRECT ACTION_VIEW: FIXED
MESSENGER DIRECT OPEN: READY FOR RETEST
SAF IMPORT REGRESSION: PASS
A1/A1.1 REGRESSION: PASS
E1 REGRESSION: PASS
GENERIC */* HANDLER: NONE
GENERIC JSON HANDLER: NONE
BACKEND CHANGES: NONE
PRODUCTION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
