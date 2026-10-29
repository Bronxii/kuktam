import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

bool validFamilyInviteToken(String token) =>
    RegExp(r'^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$').hasMatch(token);

abstract interface class PendingFamilyInviteStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Capability credential only. No UID, URL, preview, expiry or JOIN metadata.
class SecurePendingFamilyInviteStore implements PendingFamilyInviteStore {
  SecurePendingFamilyInviteStore({
    FlutterSecureStorage? storage,
    Future<void> Function()? flush,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(
               storageNamespace: 'kuktam_family_invite',
               resetOnError: false,
               migrateWithBackup: false,
             ),
           ),
       _flush = flush ?? _nativeFlush;
  final FlutterSecureStorage _storage;
  final Future<void> Function() _flush;
  static const key = 'pending_invite_v1';
  static Future<void> _nativeFlush() => const MethodChannel(
    'kuktam/family_invite_durability',
  ).invokeMethod<void>('flush');
  @override
  Future<String?> read() async {
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      if (raw.length > 128) throw const FormatException();
      final data = jsonDecode(raw);
      if (data is! Map ||
          data.length != 2 ||
          data['version'] != 1 ||
          data['token'] is! String ||
          !validFamilyInviteToken(data['token'] as String)) {
        throw const FormatException();
      }
      return data['token'] as String;
    } on FormatException {
      await clear();
      throw const FormatException('Pending invitation unavailable');
    }
  }

  @override
  Future<void> write(String token) async {
    if (!validFamilyInviteToken(token)) {
      throw const FormatException('Invalid invitation');
    }
    await _storage.write(
      key: key,
      value: jsonEncode({'version': 1, 'token': token}),
    );
    await _flush();
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: key);
    await _flush();
  }
}
