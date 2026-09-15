import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kuktam/features/walkthrough/data/walkthrough_store.dart';

class Preferences implements SharedPreferencesAsync {
  Preferences(this.disk, {this.failRead = false, this.failWrite = false});
  final Map<String, Object> disk;
  final bool failRead, failWrite;
  @override
  Future<bool?> getBool(String key) async {
    if (failRead) throw StateError('read');
    return disk[key] as bool?;
  }

  @override
  Future<void> setBool(String key, bool value) async {
    if (failWrite) throw StateError('write');
    disk[key] = value;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test(
    'persistent adapter writes only app-level completion and survives a new instance',
    () async {
      final disk = <String, Object>{'unrelated': 'keep'};
      var store = SharedPreferencesWalkthroughStore(
        preferences: Preferences(disk),
      );
      expect(await store.isCompleted(), isFalse);
      await store.complete();
      expect(disk, {'unrelated': 'keep', 'walkthroughCompleted': true});
      store = SharedPreferencesWalkthroughStore(preferences: Preferences(disk));
      expect(await store.isCompleted(), isTrue);
    },
  );
  test(
    'adapter exposes persistence failures to gate without inventing success',
    () async {
    final preferences = Preferences({}, failRead: true, failWrite: true);
      final store = SharedPreferencesWalkthroughStore(preferences: preferences);
      await expectLater(store.isCompleted(), throwsStateError);
      await expectLater(store.complete(), throwsStateError);
      expect(preferences.disk, isEmpty);
    },
  );
}
