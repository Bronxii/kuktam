// Test-only SDK doubles: sealed annotation is not a runtime restriction.
// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/export/data/recipe_export_source.dart';
import 'package:kuktam/export/domain/recipe_export.dart';
import 'export_test.dart' show SessionFixture, Port, data;

class Db extends Fake implements FirebaseFirestore {
  final calls = <String>[];
  @override
  Future<void> waitForPendingWrites() async {
    calls.add('wait');
  }

  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    calls.add(path);
    return Collection(this);
  }
}

class Collection extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  Collection(this.db);
  final Db db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    db.calls.add(path!);
    return Document(db);
  }

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    expect(options!.source, Source.server);
    db.calls.add('server');
    return Snapshot();
  }
}

class Document extends Fake implements DocumentReference<Map<String, dynamic>> {
  Document(this.db);
  final Db db;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    db.calls.add(path);
    return Collection(db);
  }
}

class Snapshot extends Fake implements QuerySnapshot<Map<String, dynamic>> {
  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
  @override
  SnapshotMetadata get metadata => Metadata();
}

class Metadata extends Fake implements SnapshotMetadata {
  @override
  bool get isFromCache => false;
  @override
  bool get hasPendingWrites => false;
}

void main() {
  test(
    'production Firestore port waits and reads unfiltered entire server collection',
    () async {
      final db = Db();
      final s = SessionFixture();
      addTearDown(s.dispose);
      expect(
        await RecipeExportSource(FirestoreExportReadPort(db)).load(s.session),
        isEmpty,
      );
      expect(db.calls, ['wait', 'users', 'a', 'recipes', 'server']);
      // Fake throws for any unexpected query/orderBy/limit/cache fallback.
    },
  );
  test(
    'permission denied is controlled and no partial result escapes',
    () async {
      final s = SessionFixture();
      addTearDown(s.dispose);
      final p = Port()
        ..error = FirebaseException(
          plugin: 'firestore',
          code: 'permission-denied',
        );
      await expectLater(
        RecipeExportSource(p).load(s.session),
        throwsA(
          isA<ExportFailure>().having((e) => e.code, 'code', 'permission'),
        ),
      );
    },
  );
  test(
    'Hungarian sorting and private doc identity tie-break are deterministic',
    () async {
      final s = SessionFixture();
      addTearDown(s.dispose);
      final p = Port()
        ..snapshot = ExportSnapshot([
          (
            id: 'z',
            data: {
              ...data(name: 'Alma'),
              'preparation': 'second',
            },
          ),
          (id: 'b', data: data(name: 'Zeller')),
          (
            id: 'a',
            data: {
              ...data(name: 'Alma'),
              'preparation': 'first',
            },
          ),
        ]);
      final result = await RecipeExportSource(p).load(s.session);
      expect(result.map((r) => r.name), ['Alma', 'Alma', 'Zeller']);
      expect(result.first.preparation, 'first');
    },
  );
}
