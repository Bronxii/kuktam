import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../entitlements/domain/repositories/entitlement_repository.dart';
import '../entitlements/data/entitlement_contracts.dart';
import '../entitlements/data/entitlement_cache.dart';

/// One encrypted record contains proof AND clock checkpoint. Android Keystore
/// protects encryption keys. No client secret/signature or purchase evidence.
final class SecureEntitlementStorage implements EntitlementCacheStorage {
  SecureEntitlementStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'kuktam_entitlement',
              resetOnError: false,
              migrateWithBackup: false,
            ),
          );
  final FlutterSecureStorage _storage;
  static const key = 'effective_pro_v1';
  static const _durability = MethodChannel('kuktam/entitlement_durability');
  Future<void> _flush() => _durability.invokeMethod<void>('flush');
  void _validate(String value) {
    if (value.length > 16384) throw const FormatException('Invalid cache');
    final json = jsonDecode(value);
    if (json is! Map || json['uid'] is! String) {
      throw const FormatException('Invalid cache');
    }
    EntitlementCache.decode(value, json['uid'] as String);
  }

  @override
  Future<String?> read() async {
    try {
      final value = await _storage.read(key: key);
      if (value != null) _validate(value);
      return value;
    } catch (_) {
      try {
        await _storage.delete(key: key);
        await _flush();
      } catch (_) {
        /* Repository fails closed. */
      }
      throw const EntitlementBackendException(
        EntitlementFailure.storageFailure,
      );
    }
  }

  @override
  Future<void> write(String value) async {
    _validate(value);
    await _storage.write(key: key, value: value);
    await _flush();
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: key);
    await _flush();
  }
}
