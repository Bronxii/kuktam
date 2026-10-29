import 'dart:async';
import 'package:flutter/foundation.dart';
import 'pending_family_invite.dart';

/// Incoming URI validation only. Membership always requires server preview/JOIN.
String? familyInviteToken(String raw) {
  if (raw.length > 256) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.authority != 'kuktam-67768.web.app' ||
      uri.path != '/family/invite' ||
      uri.hasFragment ||
      !raw.startsWith('https://') ||
      raw != uri.toString()) {
    return null;
  }
  // Current canonical unpadded base64url credential. Reject encoded aliases,
  // duplicate/extra query keys, whitespace, padding and noncanonical pad bits.
  if (!RegExp(
    r'^token=[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$',
  ).hasMatch(uri.query)) {
    return null;
  }
  return uri.queryParameters['token'];
}

/// One active navigation and one serialized optional pending auth continuation.
class FamilyLinkRouter extends ChangeNotifier {
  FamilyLinkRouter({
    required this.currentUid,
    required this.canNavigate,
    required this.open,
    required this.notice,
    this.pendingStore,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final String? Function() currentUid;
  final bool Function() canNavigate;
  final Future<void> Function(String token) open;
  final void Function(String message) notice;
  final DateTime Function() _now;
  final PendingFamilyInviteStore? pendingStore;
  String? _pending, _unsaved;
  bool _disposed = false;
  String? storageError;
  bool get hasPending => _pending != null;
  Future<void> _tail = Future<void>.value();
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serial(Future<void> Function() work, {bool clearError = true}) {
    final next = _tail.then((_) async {
      if (_disposed) return;
      try {
        await work();
        if (clearError) storageError = null;
      } catch (_) {
        storageError =
            'A meghívó mentése vagy megnyitása nem sikerült. Próbáld újra.';
      }
      _changed();
    });
    _tail = next;
    return next;
  }

  Future<void> restore() => _serial(() async {
    _pending = await pendingStore?.read();
  });
  Future<void> retryPending() => _serial(() async {
    final token = _unsaved;
    if (token != null) {
      await pendingStore!.write(token);
      _pending = token;
      _unsaved = null;
    } else {
      _pending = await pendingStore?.read();
    }
  });
  Future<void> cancelPending() => _serial(() async {
    await pendingStore?.clear();
    _pending = null;
    _unsaved = null;
  });
  Future<void> resume() => _serial(() async {
    if (storageError != null) return;
    final token = _pending;
    final uid = currentUid();
    if (token == null || uid == null || _opening || !canNavigate()) return;
    // Durable deletion succeeds before route ownership. Failure keeps pending.
    await pendingStore!.clear();
    if (_disposed || currentUid() != uid || !canNavigate()) {
      await pendingStore!.write(token);
      return;
    }
    _pending = null;
    unawaited(_openToken(token, uid));
  }, clearError: false);
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  bool _opening = false;
  String? _lastToken, _lastUid;
  DateTime? _lastAt;

  Future<void> receive(String raw) async {
    final token = familyInviteToken(raw);
    if (token == null) {
      notice('Ez nem érvényes Kuktám családi meghívólink.');
      return;
    }
    final uid = currentUid();
    if (uid == null) {
      _lastToken = null;
      _lastUid = null;
      if (pendingStore != null && !_opening) {
        await _serial(() async {
          if (_pending == token) return;
          _unsaved = token;
          await pendingStore!.write(token);
          _pending = token;
          _unsaved = null;
        });
        await resume();
      } else {
        notice('Jelentkezz be, majd nyisd meg újra a meghívólinket.');
      }
      return;
    }
    if (hasPending && pendingStore != null) {
      await _serial(() async {
        if (_opening) return;
        _unsaved = token;
        if (_pending != token) await pendingStore!.write(token);
        _pending = token;
        _unsaved = null;
      });
      await resume();
      return;
    }
    await _openToken(token, uid);
  }

  Future<void> _openToken(String token, String uid) async {
    final now = _now();
    if (_lastToken == token &&
        _lastUid == uid &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 5)) {
      return;
    }
    if (_opening || !canNavigate()) {
      notice(
        'Előbb fejezd be a megnyitott folyamatot, majd nyisd meg újra a meghívólinket.',
      );
      return;
    }
    _opening = true;
    _lastToken = token;
    _lastUid = uid;
    _lastAt = now;
    try {
      await open(token);
    } finally {
      _opening = false;
    }
  }
}
