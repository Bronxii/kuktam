import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../sharing/recipe_file_receiver.dart';
import 'android_image_picker.dart';
import 'image_import_controller.dart';
import 'image_import_model.dart';
import 'local_image_preparation.dart';
import 'image_inspection_screen.dart';

class ImageImportScreen extends StatefulWidget {
  const ImageImportScreen({super.key, this.controller});
  final ImageImportController? controller;
  @override
  State<ImageImportScreen> createState() => _ImageImportScreenState();
}

class _ImageImportScreenState extends State<ImageImportScreen> {
  late final ImageImportController c;
  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      c = widget.controller!;
    } else {
      final session = RecipeFileReceiver.instance;
      final generation = session.generation;
      final preparation = LocalImagePreparation();
      unawaited(preparation.cleanupStale().catchError((Object _) {}));
      c = ImageImportController(
        picker: const AndroidImageImportPicker(),
        preparation: preparation,
        validateSession: () => session.check(generation),
        sessionChanges: session,
      );
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Recept képből')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'AI képimport – helyi előkészítés',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Egy recepthez 1–5 képet válassz, majd ellenőrizd a sorrendet. A szöveges import továbbra is ingyenes.',
          ),
          const SizedBox(height: 8),
          const Text(
            'Helyi próba: AI-feldolgozás még nincs. A képek az eszközön maradnak, valódi kreditlevonás nem történik.',
          ),
          const SizedBox(height: 12),
          Text('${c.creditCost} kép kiválasztva'),
          Text('Feldolgozás költsége: ${c.creditCost} kredit'),
          Text(
            'Próbaegyenleg: ${c.credits.balance} kredit (nem valódi egyenleg)',
          ),
          OutlinedButton.icon(
            onPressed: c.editable && c.creditCost < ImageImportPolicy.maxImages
                ? () async {
                    final before = c.creditCost;
                    await c.add();
                    if (mounted && c.creditCost > before) await c.prepare();
                  }
                : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Képek hozzáadása'),
          ),
          if (c.busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: LinearProgressIndicator(),
            ),
          for (var i = 0; i < c.images.length; i++) _item(i),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(c.error!.message, semanticsLabel: c.error!.message),
            ),
          OutlinedButton(
            onPressed: c.editable && c.creditCost > 0 ? c.prepare : null,
            child: const Text('Képek előkészítése'),
          ),
          FilledButton(
            onPressed: c.editable && c.state == ImageImportState.readyToImport
                ? c.start
                : null,
            child: Text('Importálás – ${c.creditCost} kredit'),
          ),
          if (c.state == ImageImportState.readyToImport)
            const Text('Minden kép előkészítve. A helyi próba indítható.'),
          if (c.state == ImageImportState.processingPlaceholder)
            const Text(
              'Helyi előkészítés kész. AI-feldolgozás nem indult és kredit nem fogyott. Recept nem lett mentve.',
            ),
        ],
      ),
    ),
  );
  Widget _item(int index) {
    final item = c.images[index];
    final ready = c.prepared.where((e) => e.id == item.id).firstOrNull;
    final failure = c.failures[item.id];
    return Card(
      key: ValueKey('image-card-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${index + 1}. kép',
                    semanticsLabel: '${index + 1}. kép az ${c.creditCost}-ből',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Kép feljebb',
                  onPressed: c.editable && index > 0
                      ? () => c.move(index, index - 1)
                      : null,
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: 'Kép lejjebb',
                  onPressed: c.editable && index + 1 < c.creditCost
                      ? () => c.move(index, index + 1)
                      : null,
                  icon: const Icon(Icons.arrow_downward),
                ),
                IconButton(
                  tooltip: 'Kép eltávolítása',
                  onPressed: c.editable ? () => c.remove(index) : null,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final aspect = ready == null
                    ? null
                    : ready.width / ready.height;
                // ~one third of the viewport; bounded on tablets and in landscape.
                final target = math.min(
                  MediaQuery.sizeOf(context).height * .33,
                  math.min(constraints.maxWidth * 1.25, 480.0),
                );
                final height = aspect != null && aspect > 1
                    ? math.min(target, constraints.maxWidth / aspect)
                    : target;
                final displayWidth = aspect == null
                    ? constraints.maxWidth
                    : math.min(constraints.maxWidth, height * aspect);
                return SizedBox(
                  key: ValueKey('image-preview-${item.id}'),
                  height: height,
                  width: double.infinity,
                  child: ready == null
                      ? const Center(
                          child: Icon(Icons.image_outlined, size: 48),
                        )
                      : Semantics(
                          button: true,
                          label:
                              'Kép nagyítása, ${index + 1}. kép az ${c.creditCost}-ből',
                          child: InkWell(
                            onTap: c.invalidated
                                ? null
                                : () => Navigator.of(context).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => ImageInspectionScreen(
                                        controller: c,
                                        initialId: item.id,
                                      ),
                                    ),
                                  ),
                            child: Image.file(
                              File(ready.localFile),
                              cacheWidth: math.max(
                                1,
                                math.min(
                                  ready.width,
                                  (displayWidth *
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ))
                                      .ceil(),
                                ),
                              ),
                              fit: BoxFit.contain,
                              excludeFromSemantics: true,
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                        ),
                );
              },
            ),
            if (failure != null) Text('${index + 1}. kép: ${failure.message}'),
            if (ready == null && failure == null)
              const Text(
                'Az előnézet biztonságos előkészítés után jelenik meg.',
              ),
          ],
        ),
      ),
    );
  }
}
