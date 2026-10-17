import 'package:flutter/services.dart';
import 'image_import_model.dart';

/// Native URIs terminate here; core only receives adapter-owned local copies.
class AndroidImageImportPicker implements ImageImportPickerPort {
  const AndroidImageImportPicker({
    this.channel = const MethodChannel('kuktam/image_import'),
  });
  final MethodChannel channel;
  @override
  Future<List<SelectedImportImage>> pick(
    int remaining,
    ImageImportPolicy policy,
  ) async {
    try {
      final result = await channel.invokeListMethod<Object?>('pick', {
        'remaining': remaining,
        'maxBytes': policy.originalBytes,
      });
      return (result ?? []).map((row) {
        final map = row as Map;
        return SelectedImportImage(
          id: map['id'] as String,
          localFile: map['path'] as String?,
          failure: map['error'] == null
              ? null
              : ImageImportFailure(map['error'] as String),
        );
      }).toList();
    } on PlatformException catch (e) {
      throw ImageImportFailure(
        const ['limit', 'size', 'format', 'busy'].contains(e.code)
            ? e.code
            : 'read',
      );
    } on MissingPluginException {
      throw const ImageImportFailure('read');
    }
  }

  @override
  Future<void> release(List<SelectedImportImage> images) async {
    if (images.isNotEmpty) {
      await channel.invokeMethod<void>(
        'release',
        images.map((e) => e.id).toList(),
      );
    }
  }
}
