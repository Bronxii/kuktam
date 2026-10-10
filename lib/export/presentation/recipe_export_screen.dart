import 'package:flutter/material.dart';
import 'recipe_export_controller.dart';

class RecipeExportScreen extends StatefulWidget {
  const RecipeExportScreen({super.key, this.createController});
  final RecipeExportController Function()? createController;
  @override
  State<RecipeExportScreen> createState() => _RecipeExportScreenState();
}

class _RecipeExportScreenState extends State<RecipeExportScreen> {
  late final controller =
      (widget.createController ?? RecipeExportController.production)();
  @override
  void initState() {
    super.initState();
    controller.start();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('Saját adatok exportálása')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Összes recept exportálása',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 12),
            const Text(
              'JSON és olvasható TXT fájlok egy ZIP-ben. Bevásárlólista és fiókadatok nélkül.',
            ),
            const SizedBox(height: 24),
            if (controller.busy) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
              Text(switch (controller.phase) {
                ExportPhase.loading =>
                  'Receptek szerveres betöltése és ZIP készítése…',
                ExportPhase.saving => 'Mentés folyamatban…',
                _ => 'Megosztás folyamatban…',
              }),
            ],
            if (controller.artifact != null) ...[
              Text('${controller.artifact!.count} recept. A ZIP elkészült.'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: controller.busy ? null : controller.save,
                icon: const Icon(Icons.save_alt),
                label: const Text('Mentés'),
              ),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : controller.share,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Megosztás'),
              ),
            ],
            if (controller.message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  controller.message!,
                  semanticsLabel: controller.message,
                ),
              ),
            if (controller.phase == ExportPhase.failed)
              FilledButton(
                onPressed: controller.start,
                child: const Text('Újra'),
              ),
          ],
        ),
      ),
    ),
  );
}
