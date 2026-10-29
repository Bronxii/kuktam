import 'package:kuktam/family/pending_family_invite.dart';

class MemoryPendingInviteStore implements PendingFamilyInviteStore {
  String? value;
  int writes = 0, clears = 0;
  bool failWrite = false, failClear = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    if (failWrite) throw StateError('storage');
    writes++;
    value = token;
  }

  @override
  Future<void> clear() async {
    if (failClear) throw StateError('storage');
    clears++;
    value = null;
  }
}
