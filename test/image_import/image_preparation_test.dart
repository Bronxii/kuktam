import 'dart:io';
import 'package:archive/archive.dart' show getCrc32;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kuktam/image_import/image_import_model.dart';
import 'package:kuktam/image_import/local_image_preparation.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('kuktam-image-test-');
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
  });
  List<int> run(
    List<int> data, [
    ImageImportPolicy policy = const ImageImportPolicy(),
  ]) {
    final source = File('${dir.path}/input')..writeAsBytesSync(data);
    return prepareImageFile(source.path, '${dir.path}/out.jpg', policy);
  }

  img.Image image([int w = 30, int h = 20]) => img.fill(
    img.Image(width: w, height: h, numChannels: 4),
    color: img.ColorRgba8(150, 70, 20, 255),
  );
  for (final png in [false, true]) {
    test('valid ${png ? 'PNG' : 'JPEG'} no upscale and metadata stripped', () {
      final source = image();
      source.exif.imageIfd.make = 'PRIVATE CAMERA';
      source.exif.gpsIfd[1] = img.IfdValueAscii('N');
      source.textData = {'private': 'secret'};
      final result = run(png ? img.encodePng(source) : img.encodeJpg(source));
      expect(result.sublist(1), [30, 20]);
      final bytes = File('${dir.path}/out.jpg').readAsBytesSync();
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.exif.gpsIfd.isEmpty, isTrue);
      expect(decoded.exif.imageIfd.make, isNull);
      expect(String.fromCharCodes(bytes), isNot(contains('PRIVATE CAMERA')));
    });
  }
  test('JPEG orientation baked into actual pixels/dimensions', () {
    final source = image();
    source.exif.imageIfd.orientation = 6;
    final result = run(img.encodeJpg(source));
    expect(result.sublist(1), [20, 30]);
    expect(
      img
          .decodeJpg(File('${dir.path}/out.jpg').readAsBytesSync())!
          .exif
          .imageIfd
          .orientation,
      isNull,
    );
  });
  test('resize preserves ratio and both derived caps', () {
    final result = run(
      img.encodePng(image(200, 100)),
      const ImageImportPolicy(derivedSide: 80, derivedPixels: 2000),
    );
    expect(result[1], lessThanOrEqualTo(80));
    expect(result[1] * result[2], lessThanOrEqualTo(2000));
    expect(result[1] / result[2], closeTo(2, 0.06));
  });
  test('transparent PNG becomes white, no dark alpha background', () {
    run(img.encodePng(img.Image(width: 8, height: 8, numChannels: 4)));
    final pixel = img
        .decodeJpg(File('${dir.path}/out.jpg').readAsBytesSync())!
        .getPixel(2, 2);
    expect(pixel.r, greaterThan(245));
    expect(pixel.g, greaterThan(245));
    expect(pixel.b, greaterThan(245));
  });
  for (final data in [
    <int>[],
    [1, 2, 3],
    [255, 216, 255],
    'GIF89a'.codeUnits,
    'RIFFxxxxWEBP'.codeUnits,
    '%PDF'.codeUnits,
  ]) {
    test(
      'invalid/unsupported bytes ${data.length}/${data.firstOrNull} controlled',
      () {
        expect(() => run(data), throwsA(isA<ImageImportFailure>()));
        expect(File('${dir.path}/out.jpg').existsSync(), isFalse);
      },
    );
  }
  test('original size cap before decode', () {
    expect(
      () =>
          run(List.filled(101, 0), const ImageImportPolicy(originalBytes: 100)),
      throwsA(isA<ImageImportFailure>().having((e) => e.code, 'code', 'size')),
    );
  });
  test('dimension and pixel caps', () {
    final data = img.encodePng(image(30, 20));
    for (final policy in [
      const ImageImportPolicy(originalSide: 29),
      const ImageImportPolicy(originalPixels: 599),
    ]) {
      expect(
        () => run(data, policy),
        throwsA(
          isA<ImageImportFailure>().having((e) => e.code, 'code', 'size'),
        ),
      );
    }
  });
  test('huge PNG dimensions rejected before full decoding', () {
    final bytes = img.encodePng(image());
    ByteData.sublistView(bytes).setUint32(16, 9999999);
    expect(
      () => run(bytes),
      throwsA(isA<ImageImportFailure>().having((e) => e.code, 'code', 'size')),
    );
  });
  test('derived size failure does not write output', () {
    expect(
      () => run(
        img.encodePng(image()),
        const ImageImportPolicy(derivedBytes: 10),
      ),
      throwsA(isA<ImageImportFailure>()),
    );
    expect(File('${dir.path}/out.jpg').existsSync(), isFalse);
  });
  test('default longest side cap is 2560', () {
    final result = run(img.encodePng(image(2600, 26)));
    expect(result[1], 2560);
    expect(result[2], 25);
  });
  test('PNG EXIF orientation honored without retaining metadata', () {
    final source = img.encodePng(image());
    final exif = img.ExifData();
    exif.imageIfd.orientation = 6;
    exif.imageIfd.make = 'PRIVATE';
    final output = img.OutputBuffer();
    exif.write(output);
    final bytes = [
      ...source.take(33),
      ...pngChunk('eXIf', output.getBytes()),
      ...source.skip(33),
    ];
    expect(run(bytes).sublist(1), [20, 30]);
    expect(
      img
          .decodeJpg(File('${dir.path}/out.jpg').readAsBytesSync())!
          .exif
          .imageIfd
          .make,
      isNull,
    );
  });
  test('PNG decompression bomb rejected before bitmap decode', () {
    final source = img.encodePng(image(1, 1));
    final bytes = [
      ...source.take(33),
      ...pngChunk('IDAT', ZLibEncoder().convert(List.filled(100000, 0))),
      ...pngChunk('IEND', []),
    ];
    expect(() => run(bytes), throwsA(isA<ImageImportFailure>()));
  });
  test('animated PNG not silently reduced to a single frame', () {
    final source = img.encodePng(image());
    expect(
      () => run([
        ...source.take(33),
        ...pngChunk('acTL', List.filled(8, 0)),
        ...source.skip(33),
      ]),
      throwsA(
        isA<ImageImportFailure>().having((e) => e.code, 'code', 'format'),
      ),
    );
  });
  test('isolate pipeline and cleanup never delete original', () async {
    final source = File('${dir.path}/original.png')
      ..writeAsBytesSync(img.encodePng(image()));
    final service = LocalImagePreparation(temp: () async => dir);
    final output = await service.prepare(
      SelectedImportImage(id: 'a', localFile: source.path),
      const ImageImportPolicy(),
    );
    expect(File(output.localFile).existsSync(), isTrue);
    expect(output.mimeType, 'image/jpeg');
    await service.release([output]);
    expect(File(output.localFile).existsSync(), isFalse);
    expect(source.existsSync(), isTrue);
    await service.release([
      PreparedImportImage(
        id: 'evil',
        localFile: source.path,
        byteLength: 1,
        width: 1,
        height: 1,
      ),
    ]);
    expect(source.existsSync(), isTrue);
  });
  test('failed preparation removes temporary job folder', () async {
    final service = LocalImagePreparation(temp: () async => dir);
    await expectLater(
      service.prepare(
        const SelectedImportImage(id: 'x', localFile: '/missing'),
        const ImageImportPolicy(),
      ),
      throwsA(isA<ImageImportFailure>()),
    );
    expect(Directory('${dir.path}/kuktam_image_prepared').listSync(), isEmpty);
  });
}

List<int> pngChunk(String name, List<int> data) {
  final chunk = Uint8List(data.length + 12);
  final view = ByteData.sublistView(chunk);
  view.setUint32(0, data.length);
  chunk.setRange(4, 8, name.codeUnits);
  chunk.setRange(8, 8 + data.length, data);
  view.setUint32(
    data.length + 8,
    getCrc32(Uint8List.sublistView(chunk, 4, data.length + 8)),
  );
  return chunk;
}
