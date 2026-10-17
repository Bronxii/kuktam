import 'dart:math';

/// Engineering defaults; benchmark validation required. Five is a product limit.
class ImageImportPolicy {
  const ImageImportPolicy({
    this.originalBytes = 20 * 1024 * 1024,
    this.originalPixels = 24000000,
    this.originalSide = 12000,
    this.derivedSide = 2560,
    this.derivedPixels = 6000000,
    this.derivedBytes = 3 * 1024 * 1024,
    this.jpegQuality = 90,
  });
  static const maxImages = 5;
  final int originalBytes, originalPixels, originalSide;
  final int derivedSide, derivedPixels, derivedBytes, jpegQuality;
}

class ImageImportFailure implements Exception {
  const ImageImportFailure(this.code);
  final String code;
  String get message => switch (code) {
    'empty' => 'Nincs kiválasztott kép.',
    'limit' =>
      'Legfeljebb 5 kép választható. A kiválasztás nem lett hozzáadva.',
    'format' => 'Nem támogatott képformátum. JPEG vagy PNG képet válassz.',
    'size' => 'Túl nagy kép. Válassz kisebb képet.',
    'session' => 'A munkamenet megváltozott. Nyisd meg újra a képimportot.',
    'credits' =>
      'Nincs elegendő próbakredit. Valódi kreditlevonás nem történik.',
    'busy' => 'Már folyamatban van egy képkiválasztás.',
    'prepare' => 'A kép helyi előkészítése sikertelen. Próbáld újra.',
    _ => 'Sérült vagy nem olvasható kép. Válassz másikat.',
  };
}

/// Adapter-owned private local copy. Never an Android URI or user original.
class SelectedImportImage {
  const SelectedImportImage({required this.id, this.localFile, this.failure});
  final String id;
  final String? localFile;
  final ImageImportFailure? failure;
}

class PreparedImportImage {
  const PreparedImportImage({
    required this.id,
    required this.localFile,
    required this.byteLength,
    required this.width,
    required this.height,
  });
  final String id, localFile;
  final int byteLength, width, height;
  String get mimeType => 'image/jpeg';
}

/// List position is the ordinal. No account, provider or settlement data.
class PreparedImageOperation {
  PreparedImageOperation(this.operationId, List<PreparedImportImage> images)
    : images = List.unmodifiable(images);
  final String operationId;
  final List<PreparedImportImage> images;
  int get creditCost => images.length;
}

abstract interface class ImageImportPickerPort {
  Future<List<SelectedImportImage>> pick(
    int remaining,
    ImageImportPolicy policy,
  );
  Future<void> release(List<SelectedImportImage> images);
}

abstract interface class ImagePreparationPort {
  Future<PreparedImportImage> prepare(
    SelectedImportImage image,
    ImageImportPolicy policy,
  );
  Future<void> release(List<PreparedImportImage> images);
}

abstract interface class ImageCreditPreviewPort {
  int get balance;
}

class LocalImageCreditPreview implements ImageCreditPreviewPort {
  const LocalImageCreditPreview({this.balance = 20});
  @override
  final int balance;
}

String newImageOperationId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
