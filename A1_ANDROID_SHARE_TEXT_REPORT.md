# A1 – Android Share → text → recipe import

**Verdict: READY – helyi implementáció, automatizált tesztek és Android debug build kész.**
Fizikai készülékes / Android sharesheet végponttól végpontig smoke teszt nem történt;
a lent felsorolt ellenőrzések release előtt elvégzendők. Ismert P0/P1 blocker nincs.

## Integráció és dependency

Kis natív Android híd + Flutter MethodChannel (`kuktam/text_share`). Nem került be
új Flutter/Android dependency, nem történt csomagfrissítés. A meglévő entitlement
natív channel működése változatlan.

A manifest külön SEND + DEFAULT + text/plain intent-filtert kapott. Nincs image,
file, wildcard vagy SEND_MULTIPLE regisztráció. MAIN/LAUNCHER változatlan.
MainActivity singleTop → singleTask: háttérben levő példányhoz is onNewIntent
érkezzen, ne párhuzamos Flutter activity/import jöjjön létre. Package ID, signing,
taskAffinity és Firebase konfiguráció változatlan. Az összefésült debug manifestet
is ellenőriztem.

Hivatalos alapok:
- [Android receive text](https://developer.android.com/training/sharing/receive)
- [Android task / launch mode](https://developer.android.com/guide/components/activities/tasks-and-back-stack)
- [Flutter platform channels](https://docs.flutter.dev/platform-integration/platform-channels)

## Cold / warm / auth

- Cold: onCreate → natív memóriasor → Flutter channel indul → normál Firebase/app
  bootstrap → walkthrough/auth → MainScreen → előtöltött meglévő importdialog.
- Warm: onNewIntent → új queue event → pending jelzés → Flutter take → import.
- EXTRA_TEXT a payload; EXTRA_SUBJECT nem kerül hozzákeverésre.
- A queue a MainScreenen kívül él, ezért login előtt is megtartja a szöveget.
  Csak a meglévő AuthGate által engedett főképernyő nyit importot.
- Login megszakítása után a folyamat memóriájában várhat tovább; nincs cloud/disk inbox.
- A főképernyő csak resumed állapotban, saját aktuális route-ján indít importot.
  Másik route/dialog bezárását a kis NavigatorObserver jelzi; nincs polling és
  nincs új globális modal framework. A kiválasztott alsó fül nem változik.

## Egyszeri feldolgozás és több megosztás

A natív FIFO eseményenként UUID-t ad, a take eltávolítja az eseményt. Az Activity
intentjének text extrája és SEND actionje fogadás után elfogyasztottá válik.
Restored onCreate nem játssza újra az induló intentet. Initial poll és pending
callback ugyanazt a queue-elemet nem adja kétszer. Flutter event-ID dedupe is van,
512 azonosítós korláttal; azonos szöveg új szándékos share-ben új eventnek számít.

Aktív import/editor mellett az új szöveg FIFO-ban vár; a meglévő beírt szöveget
nem írja felül. Cancel vagy mentés után következhet a következő. A natív és Flutter
átvételi sor egyenként legfeljebb 10 várakozó szöveget tart; túlcsordulásnál érthető
újramegosztási jelzés jelenik meg. 20 000 Unicode karakter felett nincs csonkolás:
jelzés és elutasítás, a meglévő import szöveghatárához igazodva.

Activity-recreation: a még natív sorban levő adat process-local marad, az eredeti
intent nem nyílik újra. A Flutter sessionbe már átvett, még el nem mentett adat
nem tartós: process death / teljes Flutter engine újraindulás / fejlesztői hot
restart esetére nincs visszaállítás. Normál widget rebuild nem fogyaszt újra
eseményt. Ez az első verzió nem tartós inbox/restoration rendszer.

## Meglévő import újrahasználata

`showRecipeImportDialog(initialText: ...)` és `RecipeImportDialog(initialText: ...)`
opcionális előtöltést kapott. Kézi import initialText nélkül változatlanul üres.
A megosztott szöveg szerkeszthető; sem parse, sem mentés nem automatikus.
Feldolgozás → meglévő RecipeTextParser → meglévő AddRecipeScreen → explicit mentés.
Nincs második parser, preview, mapping vagy save út.

HTTP(S)/www URL-only esetén rövid snackbar kéri a recept szövegének kijelölését.
Nincs letöltés, linkmegnyitás, webimport vagy AI. Szövegbe ágyazott URL normál
szöveg marad. Ékezeteket, Unicode-ot és sortöréseket nem alakítunk át.

Free / unknown entitlement mellett is működik. A share rétegben nincs gate,
proof, billing vagy hálózati művelet. Normál auth és repository-szabályok maradtak.

## Érintett fájlok

- android/app/src/main/AndroidManifest.xml
- android/app/src/main/kotlin/com/bronxii/kuktam/MainActivity.kt
- android/app/src/main/java/com/bronxii/kuktam/TextShareInbox.java (új)
- android/app/src/test/java/com/bronxii/kuktam/TextShareInboxTest.java (új)
- lib/sharing/text_share_controller.dart (új)
- lib/main.dart
- lib/app/app.dart
- lib/home/presentation/screens/main_screen.dart
- lib/recipes/presentation/widgets/recipe_import_dialog.dart
- test/sharing/text_share_test.dart (új)
- A1_ANDROID_SHARE_TEXT_REPORT.md (új)

## Tesztek / build / privacy

- Célzott import/auth/feature-gate/share futás: **143 PASS**.
- Ezután további explicit shared-save és foreground teszt készült; mindkettő a
  teljes suite-ban futott. Összesen **12 új Flutter share teszt**.
- Teljes `flutter test --no-pub`: **1121 PASS / 1 korábbi skipped**.
- `flutter analyze --no-pub`: **CLEAN**.
- `flutter build apk --debug --no-pub`: **PASS** (végleges manifesttel).
- `git diff --check`: **PASS**.
- Dependency-free JVM natív inbox contract: **PASS**. Javac + `java -ea` futás;
  nem része automatikusan a Flutter suite-nak. Lefedés: initial/new delivery,
  EXTRA_TEXT hiány, MIME, SEND_MULTIPLE elutasítás, egyszeri consumption, Unicode,
  mérethatár, FIFO/kapacitás. Az Activity OS callbackjait a build ellenőrzi,
  tényleges Android instrumentációs teszt nem futott.
- Flutter: initial/new channel drain, duplicate ID, unknown/Free, pending login,
  prefill szerkesztés, meglévő parser/editor/explicit save, URL-only, más modal,
  rapid shares/cancel, background→resumed és normál importregresszió.
- Új kódban nincs payload/clipboard/token logging, URI végrehajtás vagy kliens
  extrából vett UID. A natív handler hibánál nem logolja az exception tartalmát.
- A build a korábban meglévő cloud_functions/KGP kompatibilitási figyelmeztetést
  jelezte; build sikeres, dependency upgrade szándékosan nem történt.
- Backend/functions teszt nem futott, mert ezek forrása nem változott.

## Manuális checklist – emulator / telefon

A) Cold start
1. Telepítsd a friss debug buildet, zárd be teljesen a Kuktámot.
2. Chrome-ban vagy Jegyzetben jelölj ki tényleges receptszöveget.
3. Megosztás → Kuktám; ellenőrizd, hogy a sharesheetben szerepel.
4. Normál indulás/login után pontosan egy receptimportablak jelenjen meg.
5. Ellenőrizd az ékezeteket és sortöréseket, szerkeszd az előtöltött szöveget.
6. Feldolgozás → meglévő editor → Mentés; ellenőrizd a mentett receptet.

B) Warm start / több share / modal
1. Futtasd a Kuktámot a Lista fülön, majd másik appból ossz meg új szöveget.
2. Egy ablak nyíljon, a megfelelő új szöveggel.
3. Nyitott import közben ossz meg másik szöveget: az első ne íródjon felül.
4. Az első bezárása/mentése után jelenjen meg a második.
5. Másik nyitott dialog vagy recepteditor mellett érkező share várjon annak bezárására.
6. Bezárás után a Lista fül és a Back/Recents/launcher navigáció maradjon használható.

C) Login
1. Biztonságos tesztfiókkal jelentkezz ki, majd ossz meg szöveget.
2. Login előtt ne legyen importmodal; sikeres login után a szöveg maradjon meg.
3. Google-login natív képernyő és share/back kombinációját is ellenőrizd:
   singleTask az Android activity-k fölötti stackre hatással lehet.

D) URL-only
1. Ossz meg kizárólag URL-t: érthető szöveges útmutatás, nincs webfetch/import.
2. URL-t is tartalmazó receptszöveg normál textimportba kerüljön.

E) Cancel / lifecycle
1. Share → Bezárás → Kilépés: az app használható, az eldobott import nem nyílik újra.
2. Háttér/előrehozás és képernyőforgatás után ne legyen ismételt import.
3. Normál kézi receptimport továbbra is üresen nyíljon.
4. Képmegosztásnál Kuktám ne legyen A1 share target.

## Következő lépés

A1 kódoldalon kész, Android készülékes smoke/UX ellenőrzésre átadható.
Képes share, Android→shopping chooser, export vagy más roadmap fázis nem indult el.

ANDROID SHARE TEXT: IMPLEMENTED
ANDROID SHARE IMAGE: NOT IMPLEMENTED
WEB IMPORT: NOT IMPLEMENTED
IMAGE AI IMPORT: NOT IMPLEMENTED
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PRODUCTION CHANGES: NONE
MONETIZATION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
