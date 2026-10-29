import 'dart:async';
import 'package:flutter/material.dart';
import 'family_join.dart';
import 'family_mutation.dart';
import 'family_repository.dart';
import 'family_state.dart';

/// Uses the existing Family repository. Credentials and consent are route-local.
class FamilyJoinScreen extends StatefulWidget {
  const FamilyJoinScreen({
    super.key,
    required this.repository,
    this.initialToken,
  });
  final String? initialToken;
  final FamilyRepository repository;
  @override
  State<FamilyJoinScreen> createState() => _FamilyJoinScreenState();
}

class _FamilyJoinScreenState extends State<FamilyJoinScreen> {
  final _input = TextEditingController();
  StreamSubscription<void>? _session;
  FamilyInvitePreview? _preview;
  FamilyJoinMode? _mode;
  FamilyJoinHandle? _handle;
  FamilyJoinProgress? _progress;
  String? _token, _error;
  bool _busy = false,
      _started = false,
      _uncertain = false,
      _invalidSession = false;
  int _generation = 0;
  bool _valid(int generation) =>
      mounted && !_invalidSession && generation == _generation;
  @override
  void initState() {
    super.initState();
    final initialToken = widget.initialToken;
    if (initialToken != null) {
      _input.text = initialToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_invalidSession) unawaited(_validate());
      });
    }
    _session = widget.repository.sessionChanges.listen((_) {
      if (!mounted) return;
      _generation++;
      _input.clear();
      setState(() {
        _invalidSession = true;
        _token = null;
        _preview = null;
        _mode = null;
        _handle = null;
        _progress = null;
        _busy = false;
        _error = 'A bejelentkezés megváltozott. Nyisd meg újra ezt az oldalt.';
      });
    });
  }

  @override
  void dispose() {
    _generation++;
    _input.dispose();
    _session?.cancel();
    super.dispose();
  }

  String _safe(Object e) => e is FamilyJoinException
      ? e.message
      : e is FamilyMutationException &&
            e.reason == FamilyMutationFailure.signedOut
      ? e.message
      : const FamilyJoinException('UNAVAILABLE').message;
  Future<void> _validate() async {
    if (_busy || _invalidSession) return;
    final token = _input.text.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$').hasMatch(token)) {
      setState(() => _error = 'Adj meg egy érvényes meghívókódot.');
      return;
    }
    final g = _generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = await widget.repository.previewInvite(token);
      if (_valid(g)) {
        _input.clear();
        setState(() {
          _token = token;
          _preview = preview;
        });
      }
    } catch (e) {
      if (_valid(g)) setState(() => _error = _safe(e));
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm({required bool destructive}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(
            destructive ? 'Saját lista eldobása?' : 'Saját lista hozzáadása?',
          ),
          content: Text(
            destructive
                ? 'A saját bevásárlólistád jelenlegi tételei nem kerülnek át a családi listába, és a csatlakozás során törlődnek. Ezt utána nem lehet visszavonni.'
                : 'A saját listád tételei bekerülnek a közös családi listába, ahol az összeillő tételek egyesülhetnek. Ezután a saját lista jelenlegi tételei törlődnek. A csatlakozás a feldolgozás megkezdése után nem vonható vissza.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Mégse'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                destructive
                    ? 'Csatlakozás és saját lista eldobása'
                    : 'Hozzáadás és csatlakozás',
              ),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _start() async {
    if (_busy ||
        _started ||
        _mode == null ||
        _token == null ||
        _invalidSession) {
      return;
    }
    final g = _generation;
    setState(() => _busy = true);
    try {
      if (_mode == FamilyJoinMode.add) {
        final yes = await _confirm(destructive: false);
        if (!_valid(g) || !yes) return;
      }
      if (!_valid(g)) return;
      setState(() {
        _started = true;
        _error = null;
        _uncertain = true;
      });
      await _advance(g);
    } catch (e) {
      if (_valid(g)) {
        setState(() {
          _error = _safe(e);
          if (_handle == null &&
              e is FamilyJoinException &&
              const [
                'INVALID_ARGUMENT',
                'NOT_FOUND',
                'EXPIRED',
                'USED',
                'REVOKED',
                'FAMILY_FULL',
                'SELF_INVITE',
                'ACCOUNT_UNAVAILABLE',
                'ACCOUNT_NOT_READY',
                'FEATURE_DISABLED',
                'OWNER_NOT_PRO',
                'OWNER_UNAVAILABLE',
                'FAMILY_UNAVAILABLE',
              ].contains(e.code)) {
            _started = false;
            _uncertain = false;
          }
        });
      }
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  Future<void> _advance(int g) async {
    // Check current membership first, including after an unobserved commit.
    final family = await widget.repository.load();
    if (!_valid(g)) return;
    if (family.status == FamilyStatus.activeMember) {
      _finish();
      return;
    }
    if (family.status == FamilyStatus.activeOwner) {
      throw const FamilyJoinException('ALREADY_IN_FAMILY');
    }
    // Repeating the SAME token/mode reuses the deterministic server operation.
    // Never re-preview a reserved token or choose another mode after submission.
    _handle ??= await widget.repository.startJoin(_token!, _mode!);
    if (!_valid(g)) return;
    final progress = _progress == null
        ? await widget.repository.prepareJoin(_handle!)
        : await widget.repository.readJoin(_handle!);
    if (!_valid(g)) return;
    if (_progress?.committed == true && !progress.committed) {
      throw const FamilyJoinException('UNAVAILABLE');
    }
    setState(() {
      _progress = progress;
      _uncertain = false;
      _error = null;
    });
    if (progress.status == 'DONE') {
      final refreshed = await widget.repository.load();
      if (_valid(g) && refreshed.status == FamilyStatus.activeMember) _finish();
    }
  }

  void _finish() {
    _token = null;
    _input.clear();
    _preview = null;
    _mode = null;
    Navigator.pop(context, true);
  }

  Future<void> _refresh() async {
    if (_busy || _invalidSession) return;
    final g = _generation;
    setState(() => _busy = true);
    try {
      await _advance(g);
    } catch (e) {
      if (_valid(g)) {
        setState(() {
          _uncertain = true;
          _error = _safe(e);
        });
      }
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  Future<void> _deleteConsent() async {
    final progress = _progress;
    if (_busy ||
        _uncertain ||
        progress?.needsConsent != true ||
        _invalidSession) {
      return;
    }
    final g = _generation;
    setState(() => _busy = true);
    try {
      // Never skip this dialog, including count == 0. No cached/implicit consent.
      final yes = await _confirm(destructive: true);
      if (!_valid(g) || !yes) return;
      setState(() => _uncertain = true);
      await widget.repository.confirmJoinDelete(progress!);
      if (_valid(g)) await _advance(g);
    } catch (e) {
      if (_valid(g)) setState(() => _error = _safe(e));
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy ||
        _uncertain ||
        _progress?.canCancel != true ||
        _invalidSession) {
      return;
    }
    final g = _generation;
    setState(() {
      _busy = true;
      _uncertain = true;
    });
    try {
      await widget.repository.cancelJoin(_handle!);
      if (_valid(g)) await _advance(g);
    } catch (e) {
      if (_valid(g)) setState(() => _error = _safe(e));
    } finally {
      if (_valid(g)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _progress;
    return PopScope(
      canPop:
          !_busy &&
          (!_started ||
              p?.committed == true ||
              p?.terminal == true ||
              _invalidSession),
      child: Scaffold(
        appBar: AppBar(title: const Text('Csatlakozás családhoz')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Csatlakozás feldolgozása',
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Semantics(liveRegion: true, child: Text(_error!)),
              ),
            if (!_invalidSession && !_started && _preview == null) ...[
              TextField(
                controller: _input,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.none,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _validate(),
                decoration: const InputDecoration(
                  labelText: 'Meghívókód',
                  helperText:
                      'Illeszd be a család tulajdonosától kapott kódot.',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _validate,
                child: const Text('Meghívó ellenőrzése'),
              ),
            ] else if (!_invalidSession && !_started && _preview != null) ...[
              Text(
                'Érvényes meghívó',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text('Tulajdonos: ${_preview!.ownerEmail ?? 'Ismeretlen tag'}'),
              Text(
                'Lejárat: ${MaterialLocalizations.of(context).formatMediumDate(_preview!.expiresAt.toLocal())}',
              ),
              const SizedBox(height: 16),
              const Text('Mi történjen a saját bevásárlólistáddal?'),
              const SizedBox(height: 8),
              ChoiceChip(
                label: const Text('Saját listám hozzáadása'),
                selected: _mode == FamilyJoinMode.add,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _mode = FamilyJoinMode.add),
              ),
              const Text(
                'A tételeid bekerülnek a közös listába. Az összeillő tételek egyesülhetnek, majd a saját listád jelenlegi tételei törlődnek.',
              ),
              const SizedBox(height: 16),
              ChoiceChip(
                label: const Text('Saját listám eldobása'),
                selected: _mode == FamilyJoinMode.delete,
                onSelected: _busy
                    ? null
                    : (_) => setState(() => _mode = FamilyJoinMode.delete),
              ),
              const Text(
                'A saját bevásárlólistád jelenlegi tételei nem kerülnek át a családi listába, és a csatlakozás során törlődnek. Ehhez később külön megerősítés szükséges.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy || _mode == null ? null : _start,
                child: const Text('Csatlakozás indítása'),
              ),
            ] else if (!_invalidSession) ...[
              Text(
                p?.status == 'ABORTED'
                    ? 'A csatlakozás megszakadt'
                    : p?.status == 'OPERATOR'
                    ? 'A csatlakozás ellenőrzést igényel'
                    : 'Csatlakozás folyamatban…',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                p?.committed == true
                    ? 'A csatlakozás már nem vonható vissza. Frissíts később az eredményért.'
                    : _uncertain
                    ? 'A művelet eredményét ellenőrizzük. Frissíts az állapot lekéréséhez.'
                    : 'A lista előkészítése folyamatban van. Frissíts később.',
              ),
              if (p?.needsConsent == true && !_uncertain)
                FilledButton(
                  onPressed: _busy ? null : _deleteConsent,
                  child: const Text('Eldobás megerősítése'),
                ),
              if (p?.canCancel == true && !_uncertain)
                TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Csatlakozás megszakítása'),
                ),
              OutlinedButton(
                onPressed: _busy ? null : _refresh,
                child: const Text('Állapot frissítése'),
              ),
              if (p?.terminal == true)
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Vissza a családi oldalra'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
