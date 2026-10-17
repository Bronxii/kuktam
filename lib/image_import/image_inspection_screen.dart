import 'dart:io';
import 'package:flutter/material.dart';
import 'image_import_controller.dart';
import 'image_import_model.dart';

/// Read-only inspection of the same ordered, prepared images. No preprocessing.
class ImageInspectionScreen extends StatefulWidget {
  const ImageInspectionScreen({
    super.key,
    required this.controller,
    required this.initialId,
  });
  final ImageImportController controller;
  final String initialId;
  @override
  State<ImageInspectionScreen> createState() => _ImageInspectionScreenState();
}

class _ImageInspectionScreenState extends State<ImageInspectionScreen> {
  late String selectedId = widget.initialId;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final images = c.images;
      // Invalidation immediately removes all image widgets, including zoomed pixels.
      if (c.invalidated || images.isEmpty) {
        return Scaffold(
          appBar: AppBar(title: const Text('Képelőnézet')),
          body: const Center(
            child: Text(
              'A munkamenet megváltozott. Nyisd meg újra a képimportot.',
            ),
          ),
        );
      }
      final found = images.indexWhere((i) => i.id == selectedId);
      final index = found < 0 ? 0 : found;
      final item = images[index];
      final ready = c.prepared.where((i) => i.id == item.id).firstOrNull;
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Előnézet bezárása',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('${index + 1} / ${images.length}'),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ready == null
                    ? const Center(
                        child: Text('A kép előnézete nem érhető el.'),
                      )
                    : _ZoomImage(key: ValueKey(item.id), image: ready),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Előző kép',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: index > 0
                          ? () => setState(
                              () => selectedId = images[index - 1].id,
                            )
                          : null,
                    ),
                    const Flexible(child: Text('Csippentéssel nagyítható')),
                    IconButton(
                      tooltip: 'Következő kép',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: index + 1 < images.length
                          ? () => setState(
                              () => selectedId = images[index + 1].id,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Only the inspected prepared image is decoded at its full (already bounded)
/// resolution. Evict it on page change/close; small list variants remain cached.
class _ZoomImage extends StatefulWidget {
  const _ZoomImage({super.key, required this.image});
  final PreparedImportImage image;
  @override
  State<_ZoomImage> createState() => _ZoomImageState();
}

class _ZoomImageState extends State<_ZoomImage> {
  late final provider = FileImage(File(widget.image.localFile));
  @override
  void dispose() {
    provider.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: SizedBox(
        width: box.maxWidth,
        height: box.maxHeight,
        child: Image(
          image: provider,
          fit: BoxFit.contain,
          semanticLabel: 'Nagyított képelőnézet',
          errorBuilder: (_, _, _) =>
              const Center(child: Text('A kép előnézete nem érhető el.')),
        ),
      ),
    ),
  );
}
