import 'dart:async';
import 'package:kuktam/sharing/recipe_file_receiver.dart';
import 'package:kuktam/core/account_deletion_signal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuktam/image_import/image_import_controller.dart';
import 'package:kuktam/image_import/image_import_model.dart';

class FakePicker implements ImageImportPickerPort {
  List<SelectedImportImage> next = [];
  Completer<List<SelectedImportImage>>? pending;
  int calls = 0;
  final released = <String>[];
  @override
  Future<List<SelectedImportImage>> pick(
    int remaining,
    ImageImportPolicy policy,
  ) async {
    calls++;
    return pending == null ? next : pending!.future;
  }

  @override
  Future<void> release(List<SelectedImportImage> images) async {
    released.addAll(images.map((i) => i.id));
  }
}

class FakePreparation implements ImagePreparationPort {
  final released = <String>[];
  final calls = <String>[];
  String? fail;
  Completer<PreparedImportImage>? pending;
  @override
  Future<PreparedImportImage> prepare(
    SelectedImportImage image,
    ImageImportPolicy policy,
  ) async {
    calls.add(image.id);
    if (fail == image.id) throw const ImageImportFailure('read');
    return pending == null ? output(image.id) : pending!.future;
  }

  static PreparedImportImage output(String id) => PreparedImportImage(
    id: id,
    localFile: '/fake/$id.jpg',
    byteLength: 20,
    width: 10,
    height: 10,
  );
  @override
  Future<void> release(List<PreparedImportImage> images) async {
    released.addAll(images.map((i) => i.id));
  }
}

List<SelectedImportImage> selection(int n, [int start = 0]) => List.generate(
  n,
  (i) => SelectedImportImage(id: '${i + start}', localFile: '/fake/original'),
);

void main() {
  late FakePicker picker;
  late FakePreparation prep;
  late ValueNotifier<int> session;
  late ImageImportController c;
  ImageImportController create({int balance = 20}) => ImageImportController(
    picker: picker,
    preparation: prep,
    sessionChanges: session,
    validateSession: () {
      if (session.value != 0) throw StateError('changed');
    },
    credits: LocalImageCreditPreview(balance: balance),
    operationId: () => 'one-job',
  );
  setUp(() {
    picker = FakePicker();
    prep = FakePreparation();
    session = ValueNotifier(0);
    c = create();
  });
  tearDown(() {
    c.dispose();
    session.dispose();
  });
  for (final n in [1, 3, 5]) {
    test(
      '$n images = $n credits; start is local and double-tap safe',
      () async {
        picker.next = selection(n);
        await c.add();
        expect(c.creditCost, n);
        await c.prepare();
        expect(c.state, ImageImportState.readyToImport);
        c.start();
        final op = c.operation;
        c.start();
        expect(identical(c.operation, op), isTrue);
        expect(op!.images.length, n);
        expect(op.operationId, 'one-job');
        expect(c.credits.balance, 20);
        expect(c.state, ImageImportState.processingPlaceholder);
      },
    );
  }
  test('six returned images rejected as a whole, never truncated', () async {
    picker.next = selection(6);
    await c.add();
    expect(c.images, isEmpty);
    expect(c.error!.code, 'limit');
    expect(picker.released.length, 6);
  });
  test(
    'sixth request blocked; remove/add/reorder preserves actual order',
    () async {
      picker.next = selection(5);
      await c.add();
      await c.add();
      expect(picker.calls, 1);
      c.remove(4);
      expect(c.creditCost, 4);
      picker.next = selection(1, 9);
      await c.add();
      c.move(0, 2);
      expect(c.images.map((i) => i.id), ['1', '2', '0', '3', '9']);
      expect(c.creditCost, 5);
      await c.prepare();
      c.start();
      expect(c.operation!.images.map((i) => i.id), ['1', '2', '0', '3', '9']);
    },
  );
  test('picker cancel empty result preserves existing state', () async {
    await c.add();
    expect(c.state, ImageImportState.idle);
    expect(c.error, isNull);
    picker.next = selection(1);
    await c.add();
    picker.next = [];
    await c.add();
    expect(c.creditCost, 1);
  });
  test(
    'same content separately selected is not silently deduplicated',
    () async {
      picker.next = selection(2);
      await c.add();
      expect(c.creditCost, 2);
      expect(c.images[0].localFile, c.images[1].localFile);
    },
  );
  test('empty preparation controlled', () async {
    await c.prepare();
    expect(c.error!.code, 'empty');
  });
  test('one corrupt item blocks whole job, remove repairs readiness', () async {
    picker.next = selection(3);
    prep.fail = '1';
    await c.add();
    await c.prepare();
    c.start();
    expect(c.operation, isNull);
    expect(c.failures.keys, ['1']);
    expect(c.state, ImageImportState.error);
    c.remove(1);
    expect(c.state, ImageImportState.readyToImport);
    c.start();
    expect(c.operation!.creditCost, 2);
  });
  test('native per-image failure remains identifiable', () async {
    picker.next = [
      const SelectedImportImage(id: 'bad', failure: ImageImportFailure('size')),
    ];
    await c.add();
    await c.prepare();
    c.start();
    expect(c.failures['bad']!.code, 'size');
    expect(prep.calls, isEmpty);
    expect(c.operation, isNull);
  });
  test('insufficient fake balance blocks without mutation', () async {
    c.dispose();
    c = create(balance: 0);
    picker.next = selection(1);
    await c.add();
    await c.prepare();
    c.start();
    expect(c.operation, isNull);
    expect(c.error!.code, 'credits');
    expect(c.credits.balance, 0);
  });
  test('double picker tap starts once', () async {
    picker.pending = Completer();
    final first = c.add();
    await c.add();
    expect(picker.calls, 1);
    picker.pending!.complete(selection(1));
    await first;
  });
  test('logout during picker releases delayed private copies', () async {
    picker.pending = Completer();
    final first = c.add();
    session.value = 1;
    picker.pending!.complete(selection(2));
    await first;
    expect(c.images, isEmpty);
    expect(picker.released, ['0', '1']);
    expect(c.error!.code, 'session');
  });
  test('A to B to A generation invalidates preparation and result', () async {
    picker.next = selection(1);
    await c.add();
    prep.pending = Completer();
    final pending = c.prepare();
    session.value = 1;
    session.value = 0;
    prep.pending!.complete(FakePreparation.output('0'));
    await pending;
    c.start();
    expect(c.operation, isNull);
    expect(c.prepared, isEmpty);
    expect(prep.released, ['0']);
    expect(c.invalidated, isTrue);
  });
  test(
    'session validation checked even before listener notification',
    () async {
      var valid = true;
      c.dispose();
      c = ImageImportController(
        picker: picker,
        preparation: prep,
        sessionChanges: session,
        validateSession: () {
          if (!valid) throw StateError('session');
        },
      );
      picker.next = selection(1);
      await c.add();
      await c.prepare();
      valid = false;
      c.start();
      expect(c.operation, isNull);
      expect(c.images, isEmpty);
    },
  );
  test('dispose during preparation releases late output', () async {
    final other = create();
    picker.next = selection(1);
    await other.add();
    prep.pending = Completer();
    final work = other.prepare();
    other.dispose();
    prep.pending!.complete(FakePreparation.output('0'));
    await work;
    expect(prep.released, ['0']);
    expect(picker.released, ['0']);
  });
  test(
    'existing session generation and account deletion invalidate local job',
    () async {
      final receiver = RecipeFileReceiver();
      receiver.updateSession('A');
      final generation = receiver.generation;
      final local = ImageImportController(
        picker: picker,
        preparation: prep,
        sessionChanges: receiver,
        validateSession: () => receiver.check(generation),
      );
      picker.next = selection(1);
      await local.add();
      await local.prepare();
      AccountDeletionSignal.begin();
      try {
        local.start();
        expect(local.operation, isNull);
        expect(local.invalidated, isTrue);
      } finally {
        AccountDeletionSignal.end();
        local.dispose();
        receiver.dispose();
      }
    },
  );
  test('removal cleans input and output', () async {
    picker.next = selection(1);
    await c.add();
    await c.prepare();
    c.remove(0);
    await Future<void>.delayed(Duration.zero);
    expect(picker.released, ['0']);
    expect(prep.released, ['0']);
    expect(c.state, ImageImportState.idle);
  });
}
