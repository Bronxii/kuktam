import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'image_import_model.dart';

class LocalImagePreparation implements ImagePreparationPort {
  LocalImagePreparation({Future<Directory> Function()? temp})
    : _temp = temp ?? getTemporaryDirectory;
  final Future<Directory> Function() _temp;
  Future<Directory> _root() async {
    final root = Directory('${(await _temp()).path}/kuktam_image_prepared');
    await root.create(recursive: true);
    return root;
  }

  /// Only this feature's old private job directories, bounded and no symlinks.
  Future<void> cleanupStale() async {
    final root = await _root();
    var count = 0;
    await for (final entry in root.list(followLinks: false)) {
      if (++count > 100) break;
      if (entry is Directory &&
          DateTime.now().difference((await entry.stat()).modified).inHours >=
              24) {
        await entry.delete(recursive: true);
      }
    }
  }

  @override
  Future<PreparedImportImage> prepare(
    SelectedImportImage image,
    ImageImportPolicy policy,
  ) async {
    final root = await _root();
    final job = await root.createTemp('item-');
    final output = '${job.path}/image.jpg';
    try {
      final path = image.localFile;
      if (path == null) throw const ImageImportFailure('read');
      final result = await Isolate.run(
        () => prepareImageFile(path, output, policy),
      );
      return PreparedImportImage(
        id: image.id,
        localFile: output,
        byteLength: result[0],
        width: result[1],
        height: result[2],
      );
    } catch (_) {
      try {
        await job.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<void> release(List<PreparedImportImage> images) async {
    final root = (await _root()).absolute.path;
    for (final image in images) {
      final dir = File(image.localFile).parent;
      // Only an immediate generated child, never a caller's original file.
      if (dir.parent.absolute.path != root ||
          !dir.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last
              .startsWith('item-')) {
        continue;
      }
      if (await FileSystemEntity.type(dir.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}

/// Runs in an isolate; no logs and no image bytes returned over the boundary.
List<int> prepareImageFile(String input, String output, ImageImportPolicy p) {
  try {
    final file = File(input);
    final length = file.lengthSync();
    if (length <= 0) throw const ImageImportFailure('read');
    if (length > p.originalBytes) throw const ImageImportFailure('size');
    final handle = file.openSync();
    late Uint8List bytes;
    try {
      bytes = handle.readSync(p.originalBytes + 1);
    } finally {
      handle.closeSync();
    }
    if (bytes.length > p.originalBytes) throw const ImageImportFailure('size');
    final png =
        bytes.length >= 8 &&
        bytes[0] == 137 &&
        bytes[1] == 80 &&
        bytes[2] == 78 &&
        bytes[3] == 71 &&
        bytes[4] == 13 &&
        bytes[5] == 10 &&
        bytes[6] == 26 &&
        bytes[7] == 10;
    final jpeg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (!png && !jpeg) throw const ImageImportFailure('format');
    int? orientation;
    if (png) {
      if (bytes.length < 33) throw const ImageImportFailure('read');
      final data = ByteData.sublistView(bytes);
      _dimensions(data.getUint32(16), data.getUint32(20), p);
      // Remove ancillary metadata before decoder parsing: compressed text/ICC
      // must not allocate arbitrary metadata buffers. Keep transparency only.
      final compressed = <Uint8List>[];
      final clean = BytesBuilder(copy: false)
        ..add(Uint8List.sublistView(bytes, 0, 8));
      var offset = 8;
      var ended = false;
      while (offset + 12 <= bytes.length) {
        final size = data.getUint32(offset);
        if (size > bytes.length - offset - 12) {
          throw const ImageImportFailure('read');
        }
        final type = String.fromCharCodes(
          bytes.sublist(offset + 4, offset + 8),
        );
        if (type == 'IDAT') {
          compressed.add(
            Uint8List.sublistView(bytes, offset + 8, offset + 8 + size),
          );
        }
        if (type == 'acTL') throw const ImageImportFailure('format');
        if (type == 'eXIf') {
          if (size > 65536) throw const ImageImportFailure('read');
          orientation = img.ExifData.fromInputBuffer(
            img.InputBuffer(
              Uint8List.sublistView(bytes, offset + 8, offset + 8 + size),
            ),
          ).imageIfd.orientation;
        }
        if ((bytes[offset + 4] & 32) == 0 || type == 'tRNS') {
          clean.add(Uint8List.sublistView(bytes, offset, offset + size + 12));
        }
        offset += size + 12;
        if (type == 'IEND') {
          ended = true;
          break;
        }
      }
      if (!ended) throw const ImageImportFailure('read');
      // Streaming size preflight prevents tiny-header / huge-DEFLATE bombs.
      final sink = _InflatedLimit(
        data.getUint32(16) * data.getUint32(20) * 8 +
            data.getUint32(20) * 7 +
            128,
      );
      final inflater = ZLibDecoder().startChunkedConversion(sink);
      for (final part in compressed) {
        for (var i = 0; i < part.length; i += 1024) {
          inflater.add(
            Uint8List.sublistView(part, i, min(i + 1024, part.length)),
          );
        }
      }
      inflater.close();
      bytes = clean.takeBytes();
    }
    final img.Decoder decoder = png ? img.PngDecoder() : img.JpegDecoder();
    final info = decoder.startDecode(bytes);
    if (info == null) throw const ImageImportFailure('read');
    _dimensions(info.width, info.height, p);
    var decoded = decoder.decodeFrame(0);
    if (decoded == null) throw const ImageImportFailure('read');
    if (orientation != null) decoded.exif.imageIfd.orientation = orientation;
    decoded = img.bakeOrientation(decoded);
    final scale = min(
      1.0,
      min(
        p.derivedSide / max(decoded.width, decoded.height),
        sqrt(p.derivedPixels / (decoded.width * decoded.height)),
      ),
    );
    if (scale < 1) {
      decoded = img.copyResize(
        decoded,
        width: max(1, (decoded.width * scale).floor()),
        height: max(1, (decoded.height * scale).floor()),
        interpolation: img.Interpolation.average,
      );
    }
    // A fresh RGB canvas carries no EXIF/GPS/ICC/text/embedded thumbnail.
    final clean = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 3,
    );
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, decoded);
    final encoded = img.encodeJpg(clean, quality: p.jpegQuality);
    if (encoded.length > p.derivedBytes) throw const ImageImportFailure('size');
    File(output).writeAsBytesSync(encoded, flush: true);
    return [encoded.length, clean.width, clean.height];
  } on ImageImportFailure {
    rethrow;
  } catch (_) {
    throw const ImageImportFailure('read');
  }
}

void _dimensions(int width, int height, ImageImportPolicy p) {
  if (width <= 0 || height <= 0) throw const ImageImportFailure('read');
  if (width > p.originalSide ||
      height > p.originalSide ||
      width * height > p.originalPixels) {
    throw const ImageImportFailure('size');
  }
}

class _InflatedLimit implements Sink<List<int>> {
  _InflatedLimit(this.limit);
  final int limit;
  int count = 0;
  @override
  void add(List<int> bytes) {
    count += bytes.length;
    if (count > limit) throw const ImageImportFailure('size');
  }

  @override
  void close() {}
}
