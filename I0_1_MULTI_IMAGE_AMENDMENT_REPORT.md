# I0.1 – Multi-image termékdöntés átvezetése

2026-10-11 · DESIGN UPDATE ONLY

**Verdict: a teljes I0 specifikáció frissítve; implementáció nem indult.**

## Végleges termékszabályok

- Egy importművelet: egy recept, 1–5 kép, egy operationId, egy közös provider-feldolgozás és egy szerkeszthető draft.
- Galéria/screenshot multi-select; hozzáadás, törlés, sorrendezés és sorszámos előnézet. Közvetlen kamera nincs V1-ben.
- N feldolgozott kép = N kredit. Indítás előtt képszám, teljes költség, egyenleg és „Importálás – N kredit” gomb.
- Minden kép külön előkészítendő; egy lokális hiba blokkolja az egész indítást, reservation és providerhívás nélkül.
- Tartós képtárolás nincs. Több külön recept továbbra is multipleRecipes outcome, nem tömeges import.

## A teljes specifikáció változásai

A single-image V1 feltételezés kikerült az ajánlásból, UX-ből, pickerből, preprocessingből, requestből, kreditmodellből, benchmarkból, teszttervből, fázisokból és nyitott kérdésekből. A schema ordered images[] inputot és képindexhez köthető ideiglenes warningokat kapott; az output továbbra is egy recept. Átfedés, folytatáshiány, bizonytalan sorrend és oda nem tartozó kép külön kezelendő. A meglévő editor és explicit mentés marad.

## Kredit és idempotency

N kredit atomikus reservation/finalize/release, nincs képenkénti részleges elszámolás. Valid recipe/noRecipe/unreadable/multipleRecipes outcome N kreditet fogyaszt; definite technical failure teljes N release. Az esetleges részleges providerköltség Kuktám-költség, nem részleges userterhelés. Dupla tap ugyanazzal az operationId-val nem foglalhat kétszer. Bizonytalan providerkimenet nem enged vak újrahívást; rendezési határidő még engineering döntés.

## Transport és privacy

Öt 3 MiB-os kép 15 MiB bináris, körülbelül 20 MiB base64 adat plusz JSON: a régi 4.5 MiB requestterv nem skálázható át.

Az I0 összeveti: A) szigorúan kisebb inline cap; B) privát, operationhöz kötött temporary upload; C) authenticated multipart streaming. **B az ajánlás, nem végleges transportdöntés.** Kis callable control + authenticated binary upload proxy; nincs public image URL, kliens bucket-hozzáférés vagy kliens által választott objektumútvonal.

A terv tartalmaz immutable ordered manifestet, byte/hash ellenőrzést, UID/account-generation fencinget, success/failure/partial/crash cleanupot, expiry utáni hozzáférés-tiltást, bounded sweepet és account deletion integrációt. Cloud outage alatt pontos fizikai törlési idő nem garantálható; backlog monitoring és helyreállítás release-kapu. A byte/pixel/időlimitek javaslatok, benchmark/prototípus igazolja őket.

## Benchmark és fázisterv

15 recipe job, 32 kép-előfordulás. Első kör: 3 modell × 5 job = 15 extraction / 42 képbemenet; második kör: 2 modell × 10 job = 20 extraction / 36 képbemenet. Maximum **35 extraction / 78 képbemenet**, nem 35 kép.

Kötelező esetek: 1/2/3/5 kép, overlap, levágott szélek, rossz sorrend, idegen kép és két külön recept. Fő metric a menthető recepthez szükséges kézi javítás; külön összefűzés/duplikáció/kihagyás/sorrend/hallucináció pontozás. USD5 javasolt hard cap, előzetes rate research és teljes job-költség újraszámolása szükséges; most nincs költési engedély vagy futás.

Sorrend: I1 multi-image UI/preprocess → I2 draft/editor/warnings → I3 kutatás és külön engedélyezett capped benchmark → I4 adapter/transport → I5 kreditbackend → I6 Play consumables → I7 teljes UI/session/recovery → I8 engedélyezett production wiring → I9 release QA → I10 onboarding.

## Ellenőrzés és nyitott döntések

Dokumentumkonzisztencia és benchmarkszámolás ellenőrizve; teszt/build nem futott, mert nincs implementáció. Az amendment két Markdown dokumentumot érint; korábbi munkákhoz nem nyúltunk.

Nyitott: exact preprocessing/transport, provider/model és tényleges költség, csomagár, globális budget/rate, App Check időzítés, temporary result retention, UNKNOWN rendezés, Play refund/debt. A multi-image, max 5, kamera nélküli V1, 1 kép/1 kredit és permanent retention NONE már végleges.

IMPLEMENTATION: NOT STARTED
SOURCE CHANGES: NONE
DEPENDENCY CHANGES: NONE
AI API CALLS: NONE
AI COST: ZERO
BACKEND CHANGES: NONE
FIREBASE CHANGES: NONE
PLAY CHANGES: NONE
PRODUCTION CHANGES: NONE
COMMIT: NONE
PUSH: NONE
