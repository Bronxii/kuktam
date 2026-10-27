import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pro/monetization_host.dart';
import '../pro/profile_pro_card.dart';
import 'callable_family_repository.dart';
import 'family_repository.dart';
import 'family_state.dart';
import 'family_mutation.dart';
import 'family_join_screen.dart';

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
  bool _loading = true, _busy = false;
  int _request = 0;
  String? _message;
  FamilyInviteResult? _invite;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? CallableFamilyRepository();
    _session = _repository.sessionChanges.listen((_) {
      if (!mounted) return;
      _request++;
      setState(() {
        _state = null;
        _invite = null;
        _message = null;
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
      _message = null;
      _invite = null;
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

  Future<void> _join() async {
    if (_busy || _state?.status != FamilyStatus.privateOnly) return;
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<bool>(
          builder: (_) => FamilyJoinScreen(repository: _repository),
        ),
      );
      if (mounted && _failure != FamilyFailure.signedOut) await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _safeError(Object error) =>
      (error is FamilyMutationException
              ? error
              : const FamilyMutationException(
                  FamilyMutationFailure.unavailable,
                ))
          .message;
  Future<void> _create() async {
    if (_busy ||
        _state?.status != FamilyStatus.privateOnly ||
        ProScope.maybeOf(context)?.isPro != true) {
      return;
    }
    final request = _request;
    setState(() => _busy = true);
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Család létrehozása'),
          content: const Text(
            'Te leszel a család tulajdonosa. A jelenlegi privát bevásárlólistád átkerül a közös családi listára, amelyet a családtagok együtt használhatnak.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Mégse'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Létrehozás'),
            ),
          ],
        ),
      );
      if (!mounted ||
          request != _request ||
          yes != true ||
          ProScope.maybeOf(context)?.isPro != true) {
        return;
      }
      setState(() => _message = null);
      final result = await _repository.createFamily();
      if (!mounted || request != _request) return;
      await _load();
      if (mounted && _failure == null && result == FamilyCreation.inProgress) {
        setState(
          () => _message = 'A létrehozás folyamatban van. Frissíts később.',
        );
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _message = _safeError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createInvite() async {
    if (_busy || _state?.status != FamilyStatus.activeOwner) return;
    final request = _request;
    setState(() {
      _busy = true;
      _message = null;
      _invite = null;
    });
    try {
      final invite = await _repository.createInvite();
      if (!mounted || request != _request) return;
      await _load();
      if (mounted && _failure != FamilyFailure.signedOut) {
        setState(() => _invite = invite);
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _message = _safeError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final invite = _invite;
    if (invite == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: invite.code));
      if (mounted && identical(_invite, invite)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Meghívókód másolva')));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'A másolás nem sikerült. Próbáld újra.');
      }
    }
  }

  @override
  void dispose() {
    _request++;
    _session?.cancel();
    super.dispose();
  }

  Widget _card(IconData icon, String title, String body) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body),
        ],
      ),
    ),
  );
  Widget _result(FamilyInviteResult invite) {
    final local = invite.expiresAt.toLocal(),
        formats = MaterialLocalizations.of(context);
    final expiry =
        '${formats.formatMediumDate(local)} ${formats.formatTimeOfDay(TimeOfDay.fromDateTime(local), alwaysUse24HourFormat: true)}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Meghívó elkészült',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Text(
              'A kódot csak annak add át, akit meg szeretnél hívni. E-mailt nem küldtünk. A meghívó elfogadása ebben a verzióban még nem érhető el.',
            ),
            Text('Lejárat: $expiry'),
            SelectableText(invite.code),
            OutlinedButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy),
              label: const Text('Kód másolása'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Családi megosztás'),
          actions: [
            IconButton(
              tooltip: 'Frissítés',
              onPressed: _loading || _busy ? null : _load,
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
                  if (_busy)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Családi művelet folyamatban',
                    ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(_message!),
                      ),
                    ),
                  if (_invite != null) _result(_invite!),
                  if (_failure != null) ...[
                    _card(
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
                          onPressed: _busy ? null : _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Újrapróbálás'),
                        ),
                      ),
                  ] else if (state?.status == FamilyStatus.privateOnly) ...[
                    _card(
                      Icons.family_restroom_outlined,
                      'Még nem vagy család tagja',
                      'A családi megosztással közös bevásárlólistát használhattok. Jelenleg a saját privát listádat használod.',
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _join,
                      child: const Text('Meghívókód megadása'),
                    ),
                    if (ProScope.maybeOf(context)?.isPro == true)
                      FilledButton(
                        onPressed: _busy ? null : _create,
                        child: const Text('Család létrehozása'),
                      )
                    else ...[
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Család létrehozásához Kuktám Pro szükséges.',
                        ),
                      ),
                      ProfileProCard(controller: ProScope.maybeOf(context)),
                    ],
                  ] else if (state?.status == FamilyStatus.inProgress)
                    _card(
                      Icons.hourglass_top,
                      'Folyamatban lévő családi művelet',
                      'A családi állapot frissül. Nézz vissza később, vagy frissítsd az oldalt.',
                    )
                  else if (state != null) ...[
                    _card(
                      Icons.family_restroom_outlined,
                      'Aktív család',
                      '${state.status == FamilyStatus.activeOwner ? 'Tulajdonos vagy' : 'Tag vagy'} · ${state.participants.length} résztvevő',
                    ),
                    if (state.status == FamilyStatus.activeOwner) ...[
                      if (state.participants.length >= 8)
                        const Text('A család megtelt · 8 résztvevő'),
                      FilledButton(
                        onPressed: _busy || state.participants.length >= 8
                            ? null
                            : _createInvite,
                        child: const Text('Tag meghívása'),
                      ),
                      for (final invite in state.pendingInvites)
                        ListTile(
                          leading: const Icon(Icons.mail_outline),
                          title: Text(
                            invite.reserved
                                ? 'Foglalt meghívó'
                                : 'Függő meghívó',
                          ),
                          subtitle: Text(
                            'Lejárat: ${MaterialLocalizations.of(context).formatMediumDate(invite.expiresAt.toLocal())}',
                          ),
                        ),
                    ],
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
      ),
    );
  }
}
