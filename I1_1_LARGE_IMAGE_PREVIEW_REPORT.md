# I1.1 – Large image preview UX hotfix

**VERDICT: READY FOR I2 – local implementation / automated validation.**

A tényleges 4–5 TikTok/web screenshot fő-listás felismerhetőségét a lenti telefonos smoke során még ellenőrizni kell. Fizikai készüléken ebben a fázisban nem történt teszt; nincs erre vonatkozó PASS állítás.

## Eredeti probléma

Az I1 72×72-es, 144 pixelre dekódolt thumbnailjeiből nem lehetett jól megkülönböztetni egymáshoz hasonló hosszú screenshotokat. A rendezés működött, de a hozzá szükséges vizuális információ túl kicsi volt.

## Nagy kártyák és responsive méretezés

- Egy kép egy teljes szélességű kártyában; nincs többoszlopos grid.
- Külön fejléc: erős „1. kép”, „2. kép” stb., mellette normál méretű fel/le/törlés gombok.
- A kép kerete a kártya teljes belső szélességét használja; a tényleges kép **BoxFit.contain**, soha nem crop vagy torzítás.
- Portré célmagasság: **viewport height × 0.33**. Felső korlát a rendelkezésre álló szélesség × 1.25, illetve 480 logical pixel. A 480 csak tablet-felső korlát, nem fix kártyamagasság.
- Tesztelt 390×844 telefonon a képtér 278.52 logical pixel; 320×568 esetén 187.44. Nagy tableten legfeljebb 480.
- Fekvő képnél a magasság legfeljebb szélesség/aspect ratio, illetve a portrékeret célmagassága: nincs indokolatlanul magas üres kártya.
- Nagyon hosszú képnél az aspect-fit szükségszerű oldalsó üres teret hagy. A teljes kép megmarad; a finom betűkhöz a nagyítás használható.
- A lista görgethető, öt képhez természetesen több képernyő szükséges. Stabil item-ID kulcsok; a sorszám mindig az aktuális controller-listából készül.
- A hozzáadás gomb a költségelőnézet alatt, a képlista felett marad jól megtalálható. Max 5 és az add/remove folyamat változatlan.

## Full-screen inspection

A már előkészített kép megérintése külön Flutter route-ot nyit:
- teljes képernyős, aspect-fit kép;
- Flutter InteractiveViewer, csippentés/pásztázás, 1–5× zoom;
- aktuális pozíció: „2 / 5”;
- előző/következő gombok, széleken letiltva;
- egyértelmű bezárás, rendszer Back is használható.

A viewer a controller **aktuális sorrendjét** olvassa, az első megnyitott képet stabil item-ID azonosítja. Nincs második sorrendlista vagy automatikus rendezés. Képváltáskor a zoom visszaáll.

A viewer read-only: nem módosít kiválasztást, prepared adatot, hibát, operationId-t, kreditet vagy sessiont. Bezáráskor az eredeti import route marad életben, görgetési állapotával együtt. Nem indul új preprocessing.

Munkamenet-invalidáláskor a viewer is figyeli a meglévő controller jelzését: azonnal kikerül a kép/zoom widget, és munkamenet-hiba látható. Nem marad régi account képe a nagyított nézetben.

## Memória, privacy és accessibility

- Mindkét nézet a meglévő, privát, előkészített JPEG-et használja. Nincs új JPEG, másolat, base64, URI-feloldás vagy hálózati kép.
- A listában a tényleges aspect-fit megjelenítési szélesség × eszköz-pixelarány alapján korlátozott decode-méretet kérünk; nem tart öt teljes felbontású bitmapet.
- A viewer csak az aktuális képet dekódolja a már I1-ben korlátozott felbontáson. Képváltás/bezárás eltávolítja a full-size FileImage cache-bejegyzést; nincs ötképes full-resolution előtöltés.
- A kis listaváltozatokat a Flutter image cache kezeli; új scroll/rebuild nem kér új preprocessinget. Alacsony memóriájú fizikai készüléken smoothness/peak-memory smoke még szükséges.
- Semantics: „2. kép az 5-ből”; „Kép nagyítása”; fel/le/törlés; előző/következő/bezárás. A vezérlők nem apró custom hitboxok, hanem Flutter IconButtonok.

## Scope / érintett fájlok

I1.1-ben módosult:
- lib/image_import/image_import_screen.dart – nagy, responsive kártya és viewer entry; add action felül.
- test/image_import/image_import_ui_test.dart – meglévő teszt görgetése a nagy kártyákhoz igazítva.

Új:
- lib/image_import/image_inspection_screen.dart – kizárólag Flutter inspection UI.
- test/image_import/large_preview_test.dart – valós helyi JPEG fixture-ökkel végzett layout/viewer tesztek.
- I1_1_LARGE_IMAGE_PREVIEW_REPORT.md.

Controller, preprocessing policy, picker/native bridge, session contract és kreditlogika **nem módosult ebben a hotfixben**. A munkafában meglévő I1 módosítások megmaradtak. Dependency delta: **NONE**. Android/native source delta I1.1-ben: **NONE**. Future iOS ugyanazt a Flutter UI-t használhatja.

## Tesztek és validáció

- Image import célzott suite: **55 PASS** (47 meglévő I1 + 8 új I1.1).
- Új tesztek: öt nagy egyoszlopos kártya/görgetés; kis telefon/tablet; portré/fekvő contain; helyes kép/pozíció/navigation; viewer close állapotmegőrzés; reorder→számok/viewer/operation; remove/add 5→4→5; session-invalidálás a viewerben.
- Meglévő 1/3/5 kredit, fake balance, preprocessing, orientation/metadata, limit, cleanup és auth-generation tesztek változatlanul zöldek.
- Full Flutter suite: **1300 PASS / 1 korábbi skipped**.
- Flutter analyze --no-pub: **CLEAN**.
- Android debug APK: **PASS**.
- Git diff --check: **PASS**.
- Meglévő cloud_functions Kotlin Gradle Plugin build-warning maradt; nem indítottunk dependency upgrade-et.
- Backend suite nem futott; natív teszt újrafuttatása nem szükséges, natív kód változatlan.

## Telefonos smoke

A. Válassz öt hosszú, egymást követő TikTok/web screenshotot.
B. A fő listában, fullscreen nélkül is próbáld azonosítani a részeket/sorrendet. Ez a hotfix legfontosabb manuális elfogadási pontja.
C. Normál telefonon ellenőrizd a körülbelül 30–35% képernyőmagasságú képtért, a teljes kép megőrzését és a tiszta layoutot.
D. Görgess végig mind az öt kártyán; ne legyen overflow vagy indokolatlan ugrálás.
E. Mozgasd az 1/2/3 képeket fel/le; azonnal frissülő sorszám, változatlan 5 kredit.
F. Nyiss meg egy képet; ellenőrizd a pozíciót és a csippentéses nagyítást.
G. Előző/következő gombbal járd végig mind az ötöt; a sorrend egyezzen a fő listával.
H. Bezárás és Android Back után a kiválasztás, előkészített képek, sorrend és kreditek maradjanak meg.
I. Törölj egy képet: 5→4 kredit.
J. A felül elérhető hozzáadással adj egyet: 4→5 kredit; a többi kép ne vesszen el.
K. „Importálás – 5 kredit”: továbbra is kizárólag helyi placeholder, nincs AI/kreditlevonás/receptmentés.
L. Próbálj egy fekvő fotót és kisebb kijelzőt is; aspect-fit, nincs crop vagy túl magas landscape kártya.

Nincs ismert P0/P1 az automatizált ellenőrzésben. I2 folytatható; a valós screenshotsorozat olvashatóságáról nem állítunk telefonos teszt nélkül végleges bizonyosságot.

LARGE IMAGE CARDS: IMPLEMENTED
TARGET PREVIEW HEIGHT: ~30–35% VIEWPORT
ONE IMAGE PER ROW: IMPLEMENTED
PORTRAIT SCREENSHOT UX: IMPROVED
FULL-SCREEN IMAGE INSPECTION: IMPLEMENTED
VIEWER ORDER: MATCHES IMPORT ORDER
ORDER INDICATOR: PRESERVED
IMAGE REORDER: PRESERVED
CREDIT COST LOGIC: UNCHANGED
AI EXTRACTION: NOT IMPLEMENTED
AI API CALLS: NONE
AI COST: ZERO
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PLAY CHANGES: NONE
PRODUCTION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
