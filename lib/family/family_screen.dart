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
  const FamilyScreen({super.key, this.repository, this.initialInviteToken});
  final String? initialInviteToken;
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
  bool _incomingHandled = false;
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
      if (mounted && request == _request) {
        setState(() => _loading = false);
        final token = widget.initialInviteToken;
        if (!_incomingHandled && token != null && _failure == null) {
          _incomingHandled = true;
          if (_state?.status == FamilyStatus.privateOnly) {
            unawaited(_join(initialToken: token));
          } else if (_state?.status != FamilyStatus.inProgress &&
              _failure == null) {
            setState(
              () => _message =
                  'Már családhoz tartozol. Új meghívóval most nem csatlakozhatsz.',
            );
          }
        }
      }
    }
  }

  Future<void> _join({String? initialToken}) async {
    if (_busy || _state?.status != FamilyStatus.privateOnly) return;
    setState(() => _busy = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<bool>(
          builder: (_) => FamilyJoinScreen(
            repository: _repository,
            initialToken: initialToken,
          ),
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

  Future<void> _copy({bool link = false}) async {
    final invite = _invite;
    if (invite == null) return;
    try {
      await Clipboard.setData(
        ClipboardData(text: link ? invite.inviteUrl : invite.code),
      );
      if (mounted && identical(_invite, invite)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(link ? 'Meghívólink másolva' : 'Meghívókód másolva'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'A másolás nem sikerült. Próbáld újra.');
      }
    }
  }

  Future<void> _dissolve() async {
    if (_busy || _state?.status != FamilyStatus.activeOwner) return;
    final request = _request;
    setState(() {
      _busy = true;
      _message = null;
      _invite = null;
    });
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: const Text('Család megszüntetése'),
          content: const Text(
            'Ez az egész családot érinti. A családtagok visszatérnek a saját privát bevásárlólistájukhoz. A közös lista tartalma a te privát listádba kerül; az összeillő tételek összevonódhatnak. A függő meghívók többé nem lesznek használhatók. A megszüntetést nem tudod visszavonni.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Mégse'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Család végleges megszüntetése'),
            ),
          ],
        ),
      );
      if (!mounted || request != _request || yes != true) return;
      Object? failure;
      try {
        await _repository.startDissolution();
      } catch (error) {
        failure = error;
      }
      if (!mounted || request != _request) return;
      final refreshRequest = _request + 1;
      await _load();
      if (!mounted || _request != refreshRequest || _failure != null) return;
      if (_state?.status == FamilyStatus.activeOwner) {
        setState(
          () => _message = failure is FamilyDissolutionException
              ? failure.message
              : const FamilyDissolutionException('UNAVAILABLE').message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exit(FamilyParticipant target, {required bool removal}) async {
    final state = _state;
    if (_busy ||
        state == null ||
        state.status !=
            (removal ? FamilyStatus.activeOwner : FamilyStatus.activeMember)) {
      return;
    }
    if (!state.participants.contains(target) ||
        target.role != FamilyRole.member ||
        (removal
            ? target.uid == state.currentUid
            : target.uid != state.currentUid) ||
        target.membershipInviteId == null) {
      setState(
        () => _message = const FamilyExitException('UNAVAILABLE').message,
      );
      return;
    }
    final request = _request;
    setState(() {
      _busy = true;
      _message = null;
      _invite = null;
    });
    try {
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(removal ? 'Tag eltávolítása' : 'Kilépés a családból'),
          content: Text(
            removal
                ? '${target.label} kikerül a családból, és visszatér a saját privát bevásárlólistájához. A közös családi lista a többi tagnál megmarad. A tag fiókja és privát adatai nem törlődnek.'
                : 'Kilépsz a családból, és visszatérsz a saját privát bevásárlólistádhoz. A közös családi lista többé nem lesz az aktív listád. A többi családtag és a családi bevásárlólista változatlanul megmarad.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Mégse'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(removal ? 'Tag eltávolítása' : 'Kilépés'),
            ),
          ],
        ),
      );
      if (!mounted || request != _request || yes != true) return;
      Object? failure;
      try {
        if (removal) {
          await _repository.removeMember(target);
        } else {
          await _repository.leaveFamily(target);
        }
      } catch (error) {
        failure = error;
      }
      if (!mounted || request != _request) return;
      // Read after success AND uncertainty/staleness. Never replay the captured
      // binding automatically, and never manufacture a private/removed state.
      final refreshRequest = _request + 1;
      await _load();
      if (!mounted || _request != refreshRequest || _failure != null) return;
      final fresh = _state!;
      final completed = removal
          ? fresh.status == FamilyStatus.activeOwner &&
                !fresh.participants.any((p) => p.uid == target.uid)
          : fresh.status == FamilyStatus.privateOnly;
      if (!completed) {
        setState(
          () => _message = failure == null
              ? 'A friss családi állapot még nem igazolja a művelet befejezését. Ellenőrizd az állapotot később.'
              : (failure is FamilyExitException
                        ? failure
                        : const FamilyExitException('UNAVAILABLE'))
                    .message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
              'A linket vagy a kódot csak annak add át, akit meg szeretnél hívni. E-mailt nem küldtünk. A link megnyitása még nem indít csatlakozást az alkalmazásban; a meghívókód kézzel megadható.',
            ),
            Text('Lejárat: $expiry'),
            SelectableText(invite.inviteUrl),
            FilledButton.icon(
              onPressed: () => _copy(link: true),
              icon: const Icon(Icons.link),
              label: const Text('Link másolása'),
            ),
            const Text('Meghívókód kézi megadáshoz'),
            SelectableText(invite.code),
            OutlinedButton.icon(
              onPressed: () => _copy(),
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
                              trailing:
                                  state.status == FamilyStatus.activeOwner &&
                                      member.role == FamilyRole.member &&
                                      member.uid != state.currentUid
                                  ? PopupMenuButton<String>(
                                      key: ValueKey(
                                        'family-member-menu-${member.uid}',
                                      ),
                                      tooltip: 'Tag kezelése',
                                      enabled:
                                          !_busy &&
                                          member.membershipInviteId != null,
                                      onSelected: (_) =>
                                          _exit(member, removal: true),
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Tag eltávolítása'),
                                        ),
                                      ],
                                    )
                                  : null,
                            ),
                        ],
                      ),
                    ),
                    if (state.status == FamilyStatus.activeOwner)
                      OutlinedButton(
                        onPressed: _busy ? null : _dissolve,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        child: const Text('Család megszüntetése'),
                      ),
                    if (state.status == FamilyStatus.activeMember)
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _exit(
                                state.participants.firstWhere(
                                  (p) => p.uid == state.currentUid,
                                ),
                                removal: false,
                              ),
                        child: const Text('Kilépés a családból'),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
