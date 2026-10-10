import 'package:flutter/material.dart';
import 'pro_controller.dart';
import 'pro_screen.dart';

class ProfileProCard extends StatefulWidget {
  const ProfileProCard({super.key, this.controller});
  final ProController? controller;
  @override
  State<ProfileProCard> createState() => _ProfileProCardState();
}

class _ProfileProCardState extends State<ProfileProCard> {
  bool _opening = false;
  Future<void> _open() async {
    if (_opening) return;
    _opening = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProScreen(controller: widget.controller),
        ),
      );
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.controller == null
      ? _card(context)
      : ListenableBuilder(
          listenable: widget.controller!,
          builder: (context, _) => _card(context),
        );
  Widget _card(BuildContext context) {
    final c = widget.controller;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Kuktám Pro', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                c?.statusLabel ?? 'A Pro állapot jelenleg nem ellenőrizhető.',
              ),
            ),
            if (c?.checking == true) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(
                semanticsLabel: 'Pro állapot ellenőrzése',
              ),
            ],
            const SizedBox(height: 8),
            const Text('Egyszeri vásárlás • Nincs előfizetés'),
            if (c?.isPro != true)
              const Text(
                'Gyorsabb receptbevitel, átszámítás és főzési ötletek.',
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _open,
              child: Text(
                c?.isPro == true ? 'Pro részletek' : 'Pro megtekintése',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
