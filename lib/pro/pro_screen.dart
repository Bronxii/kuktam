import 'package:flutter/material.dart';
import '../billing/billing_contracts.dart';
import '../entitlements/domain/repositories/entitlement_repository.dart';
import 'pro_controller.dart';

const proDeletionWarning =
    'A Kuktám-fiók törlésével a fiókhoz tartozó Pro jogosultság is megszűnik. '
    'A vásárlás nem vihető át automatikusan egy új Kuktám-fiókba. '
    'A fióktörlés nem jelent automatikus Google Play-visszatérítést.';

class ProScreen extends StatefulWidget {
  const ProScreen({super.key, this.controller});
  final ProController? controller;
  @override
  State<ProScreen> createState() => _ProScreenState();
}

class _ProScreenState extends State<ProScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller?.load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kuktám Pro')),
    body: widget.controller == null
        ? _content(context)
        : ListenableBuilder(
            listenable: widget.controller!,
            builder: (context, _) => _content(context),
          ),
  );
  Widget _content(BuildContext context) {
    final c = widget.controller;
    final pro = c?.isPro ?? false;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              c?.statusLabel ?? 'A Pro állapot jelenleg nem ellenőrizhető.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (c?.checking == true || c?.processing == true) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(
              semanticsLabel: 'Pro adatok feldolgozása',
            ),
          ],
          const SizedBox(height: 16),
          const Text(
            'Kevesebb gépelés, kevesebb számolás.',
            style: TextStyle(fontSize: 20),
          ),
          const SizedBox(height: 8),
          const Text(
            'Egyszeri vásárlás • Nincs előfizetés\nA Pro kényelmi funkciókkal időt és munkát spórol.',
          ),
          const SizedBox(height: 16),
          const Card(
            child: Column(
              children: [
                _Feature(
                  Icons.calculate_outlined,
                  'Receptátszámítás',
                  'Számold át a mennyiségeket más adagszámra.',
                ),
                _Feature(
                  Icons.shopping_basket_outlined,
                  'Átszámított recept → bevásárlólista',
                  'Add a módosított mennyiségeket a listádhoz.',
                ),
                _Feature(
                  Icons.restaurant_menu,
                  'Mit főzzek?',
                  'Keress ötletet a kiválasztott alapanyagokból.',
                ),
                _Feature(
                  Icons.photo_camera_outlined,
                  'Képes receptimport – hamarosan',
                  'Tervezett funkció, jelenleg még nem használható.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'A Kuktám Free korlátlan kézi recept- és bevásárlólista-kezelést, keresést és felhőszinkronizálást ad, reklámok nélkül.',
          ),
          const SizedBox(height: 20),
          if (!pro && c?.flow.offer != null)
            Text(
              c!.flow.offer!.localizedPrice,
              key: const Key('pro-price'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          if (c?.message != null || c == null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                c?.message ??
                    'A vásárlás és a visszaállítás jelenleg nem érhető el.',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (c?.flow.status == PurchaseFlowStatus.supportRequired)
            const SelectableText(
              'kuktam.support@gmail.com',
              semanticsLabel:
                  'Kuktám ügyfélszolgálat: kuktam.support@gmail.com',
            ),
          if (!pro && c?.checking != true) ...[
            FilledButton.icon(
              key: const Key('pro-buy'),
              onPressed: c?.canBuy == true ? c!.buy : null,
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text(
                'Kuktám Pro megvásárlása',
                textAlign: TextAlign.center,
              ),
            ),
            const Text(
              'Egyszeri vásárlás, nincs előfizetés.',
              textAlign: TextAlign.center,
            ),
          ],
          if (!pro)
            TextButton(
              key: const Key('pro-restore'),
              onPressed: c?.canRestore == true ? c!.restore : null,
              child: const Text(
                'Korábbi vásárlás visszaállítása',
                textAlign: TextAlign.center,
              ),
            ),
          if (c?.canRetry == true)
            OutlinedButton(
              key: const Key('pro-retry'),
              onPressed: c!.retry,
              child: const Text('Újraellenőrzés'),
            ),
          if (c != null &&
              !c.checking &&
              !pro &&
              !c.closed &&
              c.entitlement.status == ClientEntitlementStatus.unavailable &&
              c.paymentsEnabled)
            TextButton(
              onPressed: c.processing ? null : c.refresh,
              child: const Text('Pro állapot ellenőrzése'),
            ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.title, this.description);
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(description),
  );
}
