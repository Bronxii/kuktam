# N6 – Profile / Pro UI + purchase / restore UX

Dátum: 2026-10-09

**Verdict: READY FOR N7 – helyi fejlesztési folytatásra. Nem production billing release-engedély.**

## 1. Profile audit és megvalósítás

A meglévő Profil belépő a MainScreen „Profil és beállítások” ikonja, amely MaterialPageRoute-tal a SettingsScreenre vezet. A képernyő ListView/ListTile alapú, a meglévő Material 3 témát használja. E-mail, accountbeállítások, visszajelzés, kijelentkezés és fióktörlés található rajta. A fióktörlés kétlépcsős megerősítése, újrahitelesítése és repositoryja megmaradt.

A SettingsScreen tetején új, visszafogott Card jelenik meg. Free állapotnál Pro megtekintése, aktív Pro esetén Pro részletek a CTA. Unknown/checking külön progresszállapot, nem Free. Az oldal ugyanazzal a navigációs mintával nyitja a ProScreen képernyőt; ismételt megnyitást helyi route-guard akadályoz meg.

A ProScreen görgethető, Material komponensekből épül. Tartalmazza az egyszeri vásárlás/nincs előfizetés üzenetet, a kényelmi funkciókat, a Free korlátlan kézi használatának és cloud syncjének leírását, valamint a Képes receptimport – hamarosan sort. Az utóbbi nem kattintható, jelenleg nem elérhető, dátumígéret nincs.

## 2. Fájlok

Új production fájlok:
- lib/pro/pro_controller.dart – presentation állapot, emberi üzenetek és service műveletek
- lib/pro/monetization_host.dart – app-szintű ownership, Auth UID stream, resume, ProScope
- lib/pro/profile_pro_card.dart – Profile entry és dupla navigáció elleni védelem
- lib/pro/pro_screen.dart – Pro részletek, ár, purchase/restore/retry, törlési figyelmeztetés szövege

Módosított production fájlok:
- lib/main.dart – egyetlen N5 coordinator létrehozása és app-szintű host; onlineEnabled: false
- lib/settings/settings_screen.dart – Pro kártya és aktív Pro jelzés átadása a törlési dialognak
- lib/features/auth/presentation/widgets/account_deletion_dialog.dart – opcionális hasPro és figyelmeztetés

Új tesztek:
- test/pro/pro_ui_test.dart – 36 widget/állapot/elrendezés teszt
- test/pro/pro_integration_test.dart – 23 service/widget/auth/navigation/deletion integrációs teszt

Dokumentáció: N6_REPORT.md.

A korábban már meglévő, commit nélküli N1–N5 fájlokat és dependency változásokat megőriztük. A billing core, backend, rules, Firestore schema és N5 contractok N6-ban nem változtak. A SettingsScreen korábbi, nem kapcsolódó formázását nem írtuk át.

## 3. Állapotok és UX

| Forrásállapot | Felhasználói megjelenítés / művelet |
|---|---|
| UNKNOWN / CHECKING | Pro állapot ellenőrzése, progressz; nincs Free felvillanás és purchase CTA |
| FREE | Kuktám Free, Pro részletek; vásárlás csak betöltött ajánlattal és engedélyezett szolgáltatással |
| PRO_ONLINE | Kuktám Pro – Aktív; nincs új vásárlási gomb vagy hangsúlyos ár |
| PRO_OFFLINE_GRACE | Kuktám Pro – offline módban; továbbra is Pro |
| Lejárt offline bizonyíték | Internetes ellenőrzést kér; nem állítja, hogy a lifetime vásárlás lejárt |
| Product loading | Szöveges állapot és progressz; nem üres oldal |
| Launching | Google Play vásárlás megnyitása; újabb vásárlás tiltott |
| Pending | A vásárlás még feldolgozás alatt van; nincs Pro és újravásárlás |
| Verifying / proof refresh | Vásárlás ellenőrzése / Pro állapot frissítése; nincs korai siker |
| Completed + tényleges Pro | Visszafogott inline siker, restore esetén „A Kuktám Pro helyreállítva.” |
| Completed + nem Pro | Nincs sikerállítás; az ellenőrzés még nem fejeződött be |
| Canceled | Semleges „A vásárlás megszakadt.”; explicit új vásárlás megengedett |
| Retryable error | Emberi üzenet és Újraellenőrzés; nincs automatikus retry loop |
| Already owned | N5 restore útvonal; Korábbi vásárlás ellenőrzése, nem automatikus Pro |
| Restore, nincs találat | „Nem találtunk visszaállítható Kuktám Pro vásárlást.” |
| Support / binding conflict | Emberi, fiókhoz kapcsolási probléma; másolható kuktam.support@gmail.com |
| Account DELETING / DELETED | Purchase és restore nem indítható |
| Billing unavailable | Google Play vásárlás jelenleg nem érhető el; meglévő Pro nem vész el |
| Product unavailable | Nincs kamu ár; a termék jelenleg nem vásárolható meg |
| Configuration error | Egyszerű elérhetetlenségi üzenet, technikai részletek nélkül |

Az entitlement és a purchase flow külön marad. A controller nem állít Pro-t, és nem ír repositoryt vásárlás alapján. Sikert csak N5 Pro állapot és befejezett folyamat együtt jelez. PROMO/ADMIN/TEST forrásokat nem ír ki. Az inline siker nem indít minden rebuildnél új Snackbart vagy dialogot.

Az ár kizárólag a PurchaseFlowState.offer.localizedPrice értékéből jön, amely az N5 Billing ProductDetails útvonalon töltődik. Nincs hardcoded pénzösszeg, pénznem vagy ár-helyettesítő.

## 4. Purchase és restore műveletek

A widgetek kizárólag a ProController műveleteit hívják. Az N5 PurchaseOrchestrator végzi a loadOffer, buyPro és restore munkát. Nincs Billing plugin hívás widgetből, client acknowledge vagy consume.

A presentation réteg azonnali command guardot és az N5 flow állapotát is figyeli. Dupla koppintás nem indít két műveletet; az N5 in-flight védelem változatlanul megmaradt. Retry vásárlás helyett ownership/restore ellenőrzést végez, kivéve az ajánlatbetöltés explicit újrapróbálását.

A no-purchase eredmény a restore → idle állapotváltásból származik, mert az N5 contract üres ownership querynél idle-t ad. Ehhez nem módosítottuk a core contractot. Sessionváltáskor ez és az előző művelet presentation állapota törlődik; régi command completion nem oldhatja fel az új session műveleti védelmét.

## 5. App-level composition és production endpoint hiánya

A main egyetlen AndroidBillingAdaptert és MonetizationCoordinatort hoz létre. A coordinator egyetlen entitlement repositoryt és purchase orchestratort birtokol. A MonetizationHost a Navigator fölött él, figyeli az Auth UID-változásokat, továbbítja a logout/accountváltást és az app resume eseményét.

A Profile/Pro route csak kölcsönkapja a controllert. Back vagy screen dispose nem dispose-olja a globális Billing szolgáltatást. A host megszűnése bontja a subscriptionöket és a szolgáltatásokat.

A normál main composition explicit onlineEnabled: false. Emiatt nincs éles Functions endpoint kiválasztva, nincs prepare/verify/proof hívás, és a Profile megnyitása nem indít Play-vásárlást vagy restore-t. A UI emberi elérhetetlenségi állapotot mutat. Ez nem egy user-facing debug toggle.

A teljes aktív purchase/restore UX fake transport és fake Play adapter mellett, a valódi N5 coordinator/repository/orchestrator/gateway használatával tesztelt. Az éles endpoint és valós adapter bekötése későbbi production infrastruktúra-fázis.

## 6. Fióktörlés

Aktív online vagy offline Pro esetén a meglévő megerősítés kiegészül:

„A Kuktám-fiók törlésével a fiókhoz tartozó Pro jogosultság is megszűnik. A vásárlás nem vihető át automatikusan egy új Kuktám-fiókba. A fióktörlés nem jelent automatikus Google Play-visszatérítést.”

Free esetén nincs Pro-specifikus plusz figyelmeztetés. A kétlépcsős confirm, jelszavas/Google újrahitelesítés, delete repository és production deletion flow változatlan. Production billing kiadás előtt továbbra is szükséges a korábban tervezett deletion transport koordinációja; N6 ezt nem implementálta.

## 7. Accessibility, navigáció és privacy

A tartós státuszok inline, szövegesen láthatók. A progress indicator szemantikus labelt kap, az állapot live region. A CTA-k teljes magyar nevűek, a disabled állapothoz szöveges ok tartozik. A feature ikonok mellett mindig szöveg van.

A Profile kártyát és a részletező oldalt 320×568 viewporttal és 2.5-szörös szövegmérettel is ellenőriztük. Hosszú lokalizált ár, support szöveg és feature lista mellett nincs RenderFlex overflow. Nincs új UI library, asset vagy golden infrastruktúra.

Nem kerül UI-ba token, binding, source enum, exception vagy backend technikai üzenet. A support cím másolható szöveg, új launcher dependency nélkül. A tesztekben a platform callback fake nem használ Flutter expect hívást a pump őrzött aszinkron szakaszában; az ellenőrzések a teszt törzsében maradnak.

## 8. Teszteredmények

| Ellenőrzés | Eredmény |
|---|---|
| Új N6 widget állapot-/UX tesztek | 36 PASS |
| Új N6 valódi N5 service + widget integráció | 23 PASS |
| Összes új N6 teszt | 59 PASS |
| Teljes Flutter suite, N1/N5.1/N5.2/N5.3 és meglévő app regresszióval | 1008 PASS / 1 skipped |
| flutter analyze --no-pub | CLEAN |
| Android debug APK build --no-pub | PASS |
| Formázás az új/átformázott fájlokon | PASS |
| git diff --check + új, untracked fájlok ellenőrzése | CLEAN |

Az integráció lefedi a dupla buy/restore/retry tapot, pendinget, purchased → verifying → trusted proof sikert, verified + Free esetet, already-owned recoveryt, no-purchase állapotot, support konfliktust, delete rejectiont, offline grace-t, cached Free-t, accountváltást késői verify/restore eredménnyel, route-visszalépést folyamat közben, késői session inicializálást, disabled production compositiont és a valós Settings → törlési dialog plumbingot.

A meglévő recipe/shopping import, scaling, Mit főzzek?, Auth és account deletion tesztek a teljes suite részeként sikeresek. Nem történt backend módosítás; backend unit/emulator és TypeScript build N6-ban nem lett újrafuttatva. Az N5.3 korábbi backend baseline nem új N6 teszteredmény.

## 9. Closure audit

- Play callbackből közvetlen Pro/siker: NINCS.
- Hardcoded ár/pénznem a production UI-ban: NINCS.
- Előfizetést vagy havi díjat ígérő copy: NINCS; kifejezetten nincs előfizetés.
- 15/15 limit, usage counter vagy slotmodell: NINCS.
- Raw exception/token/binding/source leakage: NINCS az új UI-ban.
- Billing plugin közvetlen hívása widgetből: NINCS.
- Buildenként létrejövő Billing/repository példány: NINCS.
- Unknown/checking Free-ként kezelése: NINCS.
- Restore közvetlen Pro aktiválás: NINCS.
- Automatikus transfer/refund ígéret: NINCS.
- N7 feature gate: NINCS. A kényelmi funkciók a szándékos átmeneti állapot szerint továbbra is elérhetők.
- Új dependency: NINCS.
- Backend/rules/schema változás: NINCS.

## 10. Korlátok és következő fázis

Az N6 helyi UI/service scope-ban nem maradt ismert P0/P1 hiba.

P2 / korábbról ismert: a cloud_functions plugin Kotlin Gradle Plugin figyelmeztetése megmaradt. A jelenlegi debug build sikeres, későbbi Flutter/plugin upgrade előtt felülvizsgálandó. Az N5.3 riport dependency-audit megállapításai továbbra is külön production előtti feladatok; N6 nem végzett dependency upgrade-et vagy új npm auditot.

Későbbi release kapuk: valós Play termék és tesztvásárlás, production transport/API/IAM beállítások, account-deletion transport bekötés, fizikai készülékes Billing/KeyStore és accessibility ellenőrzés. Ezeket N6 nem helyettesíti.

A widgettesztek nem fizikai TalkBack-tesztek és nem élő Play UI tesztek. A backend nélküli normál app nem tud új online Pro státuszt igazolni; ez kontrollált, látható állapot.

N7 helyben megkezdhető: a központi feature access contract és az app-szintű service ownership rendelkezésre áll. N7 külön scope-ban adhat gate-et a két importhoz, scalinghez, scaled shoppinghoz és Mit főzzek?-hez, a kézi Free CRUD/cloud sync változatlanul hagyásával. N7-et nem kezdtük el. Éles billing release előtt a fenti production kapuk továbbra is kötelezők.

PRODUCTION FIREBASE CHANGES: NONE
PLAY CONSOLE CHANGES: NONE
PRODUCTION DEPLOY: NONE
REAL PLAY PURCHASE TEST: NOT PERFORMED
FEATURE GATES: NOT STARTED
COMMIT: NONE
PUSH: NONE
