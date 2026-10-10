import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/account_deletion_signal.dart';
import '../../recipes/domain/models/recipe.dart';
import '../../recipes/domain/services/hungarian_recipe_name_comparator.dart';
import '../domain/recipe_export.dart';

class ExportSession extends ChangeNotifier {
  ExportSession({required this.currentUid, required Stream<String?> users}) {
    _initial = currentUid();
    _watch = users.listen(
      (uid) {
        if (uid != _initial) {
          invalid = true;
          notifyListeners();
        }
      },
      onError: (Object _) {
        invalid = true;
        notifyListeners();
      },
    );
    AccountDeletionSignal.generation.addListener(_deleted);
  }
  factory ExportSession.firebase() {
    final auth = FirebaseAuth.instance;
    return ExportSession(
      currentUid: () => auth.currentUser?.uid,
      users: auth.authStateChanges().map((u) => u?.uid),
    );
  }
  final String? Function() currentUid;
  String? _initial;
  late final StreamSubscription<String?> _watch;
  bool invalid = false;
  String get uid {
    check();
    return _initial!;
  }

  void _deleted() {
    invalid = true;
    notifyListeners();
  }

  void check() {
    if (invalid ||
        _initial == null ||
        currentUid() != _initial ||
        AccountDeletionSignal.active) {
      throw const ExportFailure('session');
    }
  }

  @override
  void dispose() {
    AccountDeletionSignal.generation.removeListener(_deleted);
    unawaited(_watch.cancel());
    super.dispose();
  }
}

typedef ExportDocument = ({String id, Map<String, dynamic> data});

class ExportSnapshot {
  const ExportSnapshot(
    this.documents, {
    this.fromCache = false,
    this.pendingWrites = false,
  });
  final List<ExportDocument> documents;
  final bool fromCache, pendingWrites;
}

abstract interface class ExportReadPort {
  Future<void> waitForPendingWrites();
  Future<ExportSnapshot> serverRecipes(String uid);
}

class FirestoreExportReadPort implements ExportReadPort {
  FirestoreExportReadPort(this.db);
  final FirebaseFirestore db;
  @override
  Future<void> waitForPendingWrites() => db.waitForPendingWrites();
  @override
  Future<ExportSnapshot> serverRecipes(String uid) async {
    final snapshot = await db
        .collection('users')
        .doc(uid)
        .collection('recipes')
        .get(const GetOptions(source: Source.server));
    return ExportSnapshot(
      [for (final d in snapshot.docs) (id: d.id, data: d.data())],
      fromCache: snapshot.metadata.isFromCache,
      pendingWrites: snapshot.metadata.hasPendingWrites,
    );
  }
}

class RecipeExportSource {
  RecipeExportSource(this.port, {this.timeout = const Duration(seconds: 30)});
  final ExportReadPort port;
  final Duration timeout;
  Future<List<ExportRecipe>> load(ExportSession session) async {
    try {
      final uid = session.uid;
      await port.waitForPendingWrites().timeout(timeout);
      session.check();
      final snap = await port.serverRecipes(uid).timeout(timeout);
      session.check();
      if (snap.fromCache || snap.pendingWrites) {
        throw const ExportFailure('incomplete');
      }
      final recipes = <Recipe>[];
      try {
        for (final doc in snap.documents) {
          final recipe = Recipe.fromMap(doc.data, id: doc.id);
          ExportRecipe.fromRecipe(
            recipe,
          ); // Validate all records before exposing any.
          recipes.add(recipe);
        }
      } catch (_) {
        throw const ExportFailure('malformed');
      }
      recipes.sort((a, b) {
        final order = compareHungarianRecipeNames(a.name, b.name);
        return order != 0 ? order : a.id!.compareTo(b.id!);
      });
      session.check();
      return List.unmodifiable(recipes.map(ExportRecipe.fromRecipe));
    } on ExportFailure {
      rethrow;
    } on TimeoutException {
      throw const ExportFailure('network');
    } on FirebaseException catch (e) {
      throw ExportFailure(
        e.code == 'permission-denied' ? 'permission' : 'network',
      );
    } catch (_) {
      throw const ExportFailure('network');
    }
  }
}
