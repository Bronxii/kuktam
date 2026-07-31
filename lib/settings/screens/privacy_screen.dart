import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const String _supportEmail = 'kuktam.support@gmail.com';

  Future<void> _openSupportEmail(BuildContext context) async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: const {
        'subject': 'Kuktám – adatvédelmi kérdés',
      },
    );

    final launched = await launchUrl(emailUri);

    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nem sikerült megnyitni a levelezőalkalmazást.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adatvédelem'),
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Adatvédelmi Tájékoztató',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Kuktám mobilalkalmazás',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Hatálybalépés: 2026. augusztus',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 32),

            const _PrivacySection(
              title: '1. Bevezetés',
              content:
              'Jelen adatvédelmi tájékoztató ismerteti, hogy a Kuktám '
                  'mobilalkalmazás használata során milyen személyes adatokat '
                  'kezelünk, milyen célból, milyen jogalapon, mennyi ideig és '
                  'milyen biztonsági intézkedések mellett.',
            ),

            const _PrivacySection(
              title: '2. Az adatkezelő',
              content:
              'Adatkezelő: Király Gábor\n'
                  'Kapcsolati e-mail: kuktam.support@gmail.com\n\n'
                  'Az adatkezelésre az Európai Parlament és a Tanács '
                  '(EU) 2016/679 rendelete (GDPR), valamint a hatályos '
                  'magyar jogszabályok irányadók.',
            ),

            const _PrivacySection(
              title: '3. Az alkalmazás működése',
              content:
              'A Kuktám egy személyes receptkezelő alkalmazás. '
                  'Elsődleges célja receptek, hozzávalók, fűszerek, '
                  'elkészítési leírások és bevásárlólisták tárolása, '
                  'valamint a felhasználói adatok felhőalapú elérése.\n\n'
                  'A felhasználók adatai egymástól elkülönítve kerülnek '
                  'tárolásra.',
            ),

            const _PrivacySection(
              title: '4. A kezelt adatok köre',
              content:
              'A regisztráció és bejelentkezés során kezelt adatok:\n'
                  '• e-mail-cím\n'
                  '• Firebase felhasználói azonosító (UID)\n'
                  '• a bejelentkezési szolgáltató típusa\n\n'
                  'A felhasználó által létrehozott tartalom:\n'
                  '• receptek neve és elkészítési leírása\n'
                  '• hozzávalók, mennyiségek és mértékegységek\n'
                  '• fűszerek\n'
                  '• bevásárlólista tételei\n\n'
                  'Az alkalmazás jelenlegi verziója nem kér hozzáférést '
                  'a helyadatokhoz, névjegyekhez, SMS-ekhez, kamerához '
                  'vagy mikrofonhoz.',
            ),

            const _PrivacySection(
              title: '5. Az adatkezelés célja',
              content:
              'Az adatkezelés célja:\n'
                  '• a felhasználói fiók létrehozása és működtetése\n'
                  '• a felhasználó azonosítása\n'
                  '• a receptek és bevásárlólisták tárolása\n'
                  '• az adatok eszközök közötti elérése\n'
                  '• az alkalmazás funkcióinak biztosítása\n'
                  '• visszajelzések és hibabejelentések kezelése',
            ),

            const _PrivacySection(
              title: '6. Az adatkezelés jogalapja',
              content:
              'A felhasználói fiók létrehozásához és az alkalmazás '
                  'szolgáltatásainak biztosításához szükséges adatkezelés '
                  'jogalapja a GDPR 6. cikk (1) bekezdés b) pontja szerinti '
                  'szerződés teljesítése, illetve a szerződés megkötését '
                  'megelőző lépések megtétele.\n\n'
                  'A felhasználó által önként elküldött kapcsolatfelvételi '
                  'adatok kezelése a GDPR 6. cikk (1) bekezdés a) pontja '
                  'szerinti hozzájáruláson alapulhat.',
            ),

            const _PrivacySection(
              title: '7. Külső szolgáltatók',
              content:
              'Az alkalmazás működéséhez a Google Firebase '
                  'szolgáltatásait használjuk:\n\n'
                  '• Firebase Authentication – regisztráció és bejelentkezés\n'
                  '• Cloud Firestore – a felhasználói tartalmak tárolása\n'
                  '• Google Sign-In – Google-fiókkal történő bejelentkezés\n\n'
                  'A szolgáltatások működtetője a Google. A külső '
                  'szolgáltatók saját adatvédelmi feltételeik szerint '
                  'kezelhetnek adatokat.',
            ),

            const _PrivacySection(
              title: '8. Nemzetközi adattovábbítás',
              content:
              'A Google szolgáltatásainak használata miatt egyes adatok '
                  'az Európai Gazdasági Térségen kívül is feldolgozásra '
                  'kerülhetnek. Az adattovábbítás során a szolgáltató által '
                  'biztosított, alkalmazandó adatvédelmi garanciák kerülnek '
                  'alkalmazásra.',
            ),

            const _PrivacySection(
              title: '9. Adatbiztonság',
              content:
              'Az alkalmazás és a Firebase szolgáltatások közötti '
                  'kommunikáció titkosított kapcsolaton keresztül történik.\n\n'
                  'A Firestore biztonsági szabályai alapján a felhasználó '
                  'kizárólag a saját fiókjához tartozó receptekhez és '
                  'bevásárlólista-adatokhoz férhet hozzá.\n\n'
                  'Az adatkezelő megfelelő technikai és szervezési '
                  'intézkedéseket alkalmaz a személyes adatok jogosulatlan '
                  'hozzáférése, megváltoztatása, továbbítása, törlése vagy '
                  'megsemmisítése ellen.',
            ),

            const _PrivacySection(
              title: '10. Adatmegőrzés',
              content:
              'A felhasználói fiókhoz tartozó adatok főszabály szerint '
                  'a fiók fennállásáig kerülnek megőrzésre.\n\n'
                  'A felhasználó kérheti személyes adatainak és saját '
                  'tartalmainak törlését. Jogszabályi kötelezettség esetén '
                  'egyes adatok a szükséges időtartamig tovább is '
                  'megőrizhetők.',
            ),

            const _PrivacySection(
              title: '11. Kapcsolat és visszajelzés',
              content:
              'A Kuktám alkalmazásból a felhasználó saját '
                  'levelezőalkalmazásának használatával küldhet e-mailt '
                  'a fejlesztő részére.\n\n'
                  'A fejlesztő kizárólag az e-mailben önkéntesen megadott '
                  'adatokat kezeli a kérdés megválaszolása, a visszajelzés '
                  'feldolgozása vagy a jelzett hiba kivizsgálása céljából.',
            ),

            const _PrivacySection(
              title: '12. A felhasználó jogai',
              content:
              'A felhasználó jogosult:\n'
                  '• tájékoztatást kérni személyes adatainak kezeléséről\n'
                  '• hozzáférést kérni személyes adataihoz\n'
                  '• kérni a pontatlan adatok helyesbítését\n'
                  '• kérni személyes adatainak törlését\n'
                  '• kérni az adatkezelés korlátozását\n'
                  '• tiltakozni az adatkezelés ellen, ahol ez alkalmazható\n'
                  '• élni az adathordozhatósághoz való jogával, ahol ez '
                  'alkalmazható\n'
                  '• panaszt benyújtani a felügyeleti hatósághoz\n'
                  '• bírósághoz fordulni',
            ),

            const _PrivacySection(
              title: '13. Panasz és jogorvoslat',
              content:
              'Adatkezeléssel kapcsolatos kérdés vagy panasz esetén '
                  'elsősorban a fejlesztővel érdemes kapcsolatba lépni.\n\n'
                  'Nemzeti Adatvédelmi és Információszabadság Hatóság '
                  '(NAIH)\n'
                  'Cím: 1055 Budapest, Falk Miksa utca 9–11.\n'
                  'Postacím: 1363 Budapest, Pf. 9.\n'
                  'E-mail: ugyfelszolgalat@naih.hu\n'
                  'Telefon: +36 1 391 1400\n'
                  'Weboldal: naih.hu',
            ),

            const _PrivacySection(
              title: '14. A tájékoztató módosítása',
              content:
              'Az adatkezelő fenntartja a jogot a tájékoztató '
                  'módosítására, különösen jogszabályváltozás vagy az '
                  'alkalmazás funkcióinak és adatkezelési folyamatainak '
                  'megváltozása esetén.\n\n'
                  'A mindenkor hatályos változat a Kuktám alkalmazás '
                  'Beállítások → Adatvédelem menüpontjában érhető el.',
            ),

            const _PrivacySection(
              title: '15. Záró rendelkezések',
              content:
              'A Kuktám kizárólag az alkalmazás működéséhez szükséges '
                  'adatokat kezeli.\n\n'
                  'A felhasználók adatait nem értékesítjük, nem használjuk '
                  'fel reklámcélú profilalkotásra, és nem adjuk át '
                  'harmadik félnek marketingcélból.',
            ),

            const Divider(height: 48),

            Text(
              'Adatvédelmi kérdésed van?',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Center(
              child: FilledButton.icon(
                onPressed: () => _openSupportEmail(context),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Kapcsolatfelvétel'),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection({
    required this.title,
    required this.content,
  });

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}