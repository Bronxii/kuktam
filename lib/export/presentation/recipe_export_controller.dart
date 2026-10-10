import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../data/recipe_export_source.dart';
import '../data/export_file_gateway.dart';
import '../domain/recipe_export.dart';

enum ExportPhase { idle, loading, ready, saving, sharing, failed }

class RecipeExportController extends ChangeNotifier {
  RecipeExportController({
    required this.session,
    required this.source,
    required this.files,
    required this.packageInfo,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now {
    session.addListener(_invalidated);
  }
  factory RecipeExportController.production() => RecipeExportController(
    session: ExportSession.firebase(),
    source: RecipeExportSource(
      FirestoreExportReadPort(FirebaseFirestore.instance),
    ),
    files: AndroidExportFileGateway(),
    packageInfo: () async {
      final p = await PackageInfo.fromPlatform();
      return (p.version, p.buildNumber);
    },
  );
  final ExportSession session;
  final RecipeExportSource source;
  final ExportFileGateway files;
  final Future<(String, String)> Function() packageInfo;
  final DateTime Function() clock;
  ExportPhase phase = ExportPhase.idle;
  ExportArtifact? artifact;
  String? message;
  bool _disposed = false;
  static bool _building = false;
  bool get busy => const [
    ExportPhase.loading,
    ExportPhase.saving,
    ExportPhase.sharing,
  ].contains(phase);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _check() {
    if (_disposed) throw const ExportFailure('session');
    session.check();
  }

  void _invalidated() {
    unawaited(_cleanup(files.cancel));
    message = _message('session');
    _notify();
  }

  Future<void> start() async {
    if (busy || artifact != null || _disposed) return;
    if (_building) {
      phase = ExportPhase.failed;
      message = "Egy korábbi export még lezárul. Próbáld újra rövidesen.";
      _notify();
      return;
    }
    _building = true;
    phase = ExportPhase.loading;
    message = null;
    _notify();
    ExportArtifact? made;
    try {
      _check();
      final recipes = await source.load(session);
      _check();
      final info = await packageInfo();
      _check();
      made = await files.build(recipes, clock().toUtc(), info.$1, info.$2);
      _check();
      artifact = made;
      phase = ExportPhase.ready;
    } catch (e) {
      if (made != null) await _cleanup(() => files.discard(made!));
      phase = ExportPhase.failed;
      message = _message(e is ExportFailure ? e.code : 'build');
    } finally {
      _building = false;
    }
    _notify();
  }

  Future<void> save() => _deliver(false);
  Future<void> share() => _deliver(true);
  Future<void> _deliver(bool share) async {
    if (busy || artifact == null || _disposed) return;
    phase = share ? ExportPhase.sharing : ExportPhase.saving;
    message = null;
    _notify();
    try {
      _check();
      if (share) {
        // share_plus copies to its cache. Never delete that copy on chooser return.
        await files.share(artifact!, _check);
        _check();
        message =
            'A megosztási ablak bezárult. Ellenőrizd a mentést a fogadó alkalmazásban.';
      } else {
        final saved = await files.save(artifact!, _check);
        _check();
        message = saved
            ? 'A ZIP mentése befejeződött.'
            : 'A mentést megszakítottad.';
      }
    } catch (e) {
      message = _message(
        e is ExportFailure
            ? e.code
            : share
            ? 'share'
            : 'save',
      );
    }
    if (_disposed && artifact != null) {
      await _cleanup(() => files.discard(artifact!));
    }
    phase = ExportPhase.ready;
    _notify();
  }

  static Future<void> _cleanup(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      /* Best effort, no payload logging. */
    }
  }

  static String _message(String code) => switch (code) {
    'session' =>
      'A fiók állapota megváltozott. Zárd be az exportot, majd indítsd újra.',
    'network' || 'incomplete' =>
      'A teljes exporthoz internet és befejezett szinkronizálás szükséges. Próbáld újra.',
    'permission' =>
      'A receptek szerveres olvasása nem engedélyezett. Nem készült export.',
    'malformed' =>
      'Hibás receptadat miatt nem készült export. Egyetlen receptet sem hagytunk ki.',
    'save' => 'A fájl mentése nem sikerült. Próbáld újra.',
    'share' => 'Nem sikerült megnyitni a megosztást. Próbáld újra.',
    _ =>
      'Nem sikerült elkészíteni a teljes exportot. Ellenőrizd a szabad tárhelyet, és próbáld újra.',
  };
  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_invalidated);
    session.dispose();
    unawaited(_cleanup(files.cancel));
    if (artifact != null && !busy) {
      unawaited(_cleanup(() => files.discard(artifact!)));
    }
    super.dispose();
  }
}
