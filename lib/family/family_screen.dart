import 'dart:async';
import 'package:flutter/material.dart';
import 'callable_family_repository.dart';
import 'family_repository.dart';
import 'family_state.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key, this.repository});
  final FamilyRepository? repository;
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
  late final FamilyRepository _repository;
  StreamSubscription<void>? _session;
  FamilyState? _state;
  FamilyFailure? _failure;
  bool _loading = true;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? CallableFamilyRepository();
    _session = _repository.sessionChanges.listen((_) {
      if (!mounted) return;
      _request++;
      setState(() {
        _state = null;
        _loading = false;
        _failure = FamilyFailure.signedOut;
      });
    });
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _state = null;
      _failure = null;
    });
    try {
      final state = await _repository.load();
      if (mounted && request == _request) setState(() => _state = state);
    } catch (error) {
      if (mounted && request == _request) {
        setState(
          () => _failure = error is FamilyReadException
              ? error.reason
              : FamilyFailure.unavailable,
        );
      }
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _request++;
    _session?.cancel();
    super.dispose();
  }

  Widget _message(IconData icon, String title, String text) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(text),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Családi megosztás'),
        actions: [
          IconButton(
            tooltip: 'Frissítés',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Családi adatok betöltése',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_failure != null) ...[
                  _message(
                    Icons.info_outline,
                    'A családi adatok nem érhetők el',
                    _failure == FamilyFailure.signedOut
                        ? 'A bejelentkezés megváltozott. Nyisd meg újra ezt az oldalt.'
                        : _failure == FamilyFailure.network
                        ? 'Ellenőrizd az internetkapcsolatot, majd próbáld újra.'
                        : 'Most nem sikerült lekérni a családi állapotot. Próbáld újra később.',
                  ),
                  if (_failure != FamilyFailure.signedOut)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Újrapróbálás'),
                      ),
                    ),
                ] else if (state?.status == FamilyStatus.privateOnly)
                  _message(
                    Icons.family_restroom_outlined,
                    'Még nem vagy család tagja',
                    'A családi megosztással közös bevásárlólistát használhattok. Jelenleg a saját privát listádat használod.',
                  )
                else if (state?.status == FamilyStatus.inProgress)
                  _message(
                    Icons.hourglass_top,
                    'Folyamatban lévő családi művelet',
                    'A családi állapot frissül. Nézz vissza később, vagy frissítsd az oldalt.',
                  )
                else if (state != null) ...[
                  _message(
                    Icons.family_restroom_outlined,
                    'Aktív család',
                    '${state.status == FamilyStatus.activeOwner ? 'Tulajdonos vagy' : 'Tag vagy'} · ${state.participants.length} résztvevő',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Családtagok',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Card(
                    child: Column(
                      children: [
                        for (final member in state.participants)
                          ListTile(
                            leading: Icon(
                              member.role == FamilyRole.owner
                                  ? Icons.manage_accounts_outlined
                                  : Icons.person_outline,
                            ),
                            title: Text(member.label),
                            subtitle: Text(
                              '${member.role == FamilyRole.owner ? 'Tulajdonos' : 'Tag'}${member.uid == state.currentUid ? ' · Te' : ''}',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
