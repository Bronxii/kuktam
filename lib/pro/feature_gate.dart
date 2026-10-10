import 'dart:async';
import 'package:flutter/material.dart';
import '../entitlements/domain/repositories/entitlement_repository.dart';
import '../entitlements/domain/models/feature_access_decision.dart';
import '../entitlements/domain/models/pro_feature.dart';
import 'monetization_host.dart';
import 'pro_screen.dart';
export '../entitlements/domain/models/pro_feature.dart';

/// Injection only; no repository or alternative entitlement is created here.
class FeatureAccessScope extends InheritedWidget {
  const FeatureAccessScope({
    super.key,
    required this.repository,
    required super.child,
  });
  final EntitlementRepository? repository;
  @override
  bool updateShouldNotify(FeatureAccessScope oldWidget) =>
      repository != oldWidget.repository;
}

abstract final class FeatureGate {
  static EntitlementRepository? repository(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FeatureAccessScope>()
          ?.repository ??
      ProScope.maybeOf(context)?.entitlements;
  static ClientEntitlementState state(BuildContext context) =>
      repository(context)?.current ??
      const ClientEntitlementState(ClientEntitlementStatus.unknown);
  static FeatureAccessDecision check(BuildContext context, ProFeature feature) {
    final session = context
        .dependOnInheritedWidgetOfExactType<_FeatureSession>();
    if (session != null && session.uid != state(context).uid) {
      return FeatureAccessDecision.checking;
    }
    return state(context).access(feature);
  }

  static bool allowed(BuildContext context, ProFeature feature) =>
      check(context, feature) == FeatureAccessDecision.allowed;
  static String title(ProFeature feature) => switch (feature) {
    ProFeature.recipeScaling => 'A receptátszámítás',
    ProFeature.scaledRecipeToShopping =>
      'Az átszámított recept bevásárlólistához adása',
    ProFeature.whatToCook => 'A Mit főzzek?',
    ProFeature.imageImport => 'A képes receptimport',
  };
  static String message(BuildContext context, ProFeature feature) {
    final failure = state(context).failure;
    if (failure == EntitlementFailure.accountDeleting ||
        failure == EntitlementFailure.accountDeleted) {
      return 'Ehhez a törlés alatt álló vagy törölt fiókhoz már nem indítható Pro funkció.';
    }
    return switch (check(context, feature)) {
      FeatureAccessDecision.allowed => '',
      FeatureAccessDecision.requiresPro =>
        '${title(feature)} a Kuktám Pro része.',
      FeatureAccessDecision.checking =>
        'A Pro állapot ellenőrzése folyamatban van. Próbáld meg újra egy kicsit később.',
      FeatureAccessDecision.requiresConnection =>
        'A Pro jogosultság ellenőrzéséhez internetkapcsolat szükséges.',
      FeatureAccessDecision.featureUnavailable =>
        'Ez a funkció még nem érhető el. Hamarosan érkezik.',
    };
  }

  static final _open = <NavigatorState>{};
  static Future<bool> request(BuildContext context, ProFeature feature) async {
    if (allowed(context, feature)) return true;
    final navigator = Navigator.of(context);
    if (!_open.add(navigator)) return false;
    final controller = ProScope.maybeOf(context);
    final entitlements = repository(context);
    try {
      final showPro = await showDialog<bool>(
        context: context,
        builder: (_) => FeatureAccessScope(
          repository: entitlements,
          child: _FeaturePrompt(feature: feature),
        ),
      );
      if (showPro == true && context.mounted && navigator.mounted) {
        await navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => ProScreen(controller: controller),
          ),
        );
      }
    } finally {
      _open.remove(navigator);
    }
    return false; // No surprise auto-resume after purchase/navigation.
  }

  static Future<void> openPro(BuildContext context) async {
    final navigator = Navigator.of(context);
    if (!_open.add(navigator)) return;
    final controller = ProScope.maybeOf(context);
    try {
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ProScreen(controller: controller),
        ),
      );
    } finally {
      _open.remove(navigator);
    }
  }

  /// Re-read immediately before execution. Never cache ALLOWED as a permit.
  static bool execute(BuildContext context, ProFeature feature) {
    if (allowed(context, feature)) return true;
    unawaited(request(context, feature));
    return false;
  }
}

/// Protects public constructors too. Keeps an already-open same-user draft,
/// hides it after loss of access, and drops it on account switch.
class FeatureBoundary extends StatefulWidget {
  const FeatureBoundary({
    super.key,
    required this.feature,
    required this.builder,
    this.dialog = false,
  });
  final ProFeature feature;
  final WidgetBuilder builder;
  final bool dialog;
  @override
  State<FeatureBoundary> createState() => _FeatureBoundaryState();
}

class _FeatureBoundaryState extends State<FeatureBoundary> {
  Widget? _content;
  String? _uid;
  @override
  Widget build(BuildContext context) => StreamBuilder<ClientEntitlementState>(
    stream: FeatureGate.repository(context)?.changes,
    builder: (context, _) {
      final uid = FeatureGate.state(context).uid;
      if (_uid != uid) {
        _uid = uid;
        _content = null;
      }
      final allowed = FeatureGate.allowed(context, widget.feature);
      if (allowed) {
        _content ??= _FeatureSession(
          key: ValueKey(uid),
          uid: uid,
          child: widget.builder(context),
        );
      }
      if (_content == null) return _blocked(context);
      return Stack(
        children: [
          Offstage(offstage: !allowed, child: _content),
          if (!allowed) _blocked(context),
        ],
      );
    },
  );
  Widget _blocked(BuildContext context) => widget.dialog
      ? AlertDialog(
          scrollable: true,
          title: const Text('Kuktám Pro funkció'),
          content: _FeaturePanel(feature: widget.feature),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Bezárás'),
            ),
          ],
        )
      : Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _FeaturePanel(feature: widget.feature),
          ),
        );
}

class _FeaturePrompt extends StatefulWidget {
  const _FeaturePrompt({required this.feature});
  final ProFeature feature;
  @override
  State<_FeaturePrompt> createState() => _FeaturePromptState();
}

class _FeaturePromptState extends State<_FeaturePrompt> {
  bool _finished = false;
  void _close(bool showPro) {
    if (_finished) return;
    _finished = true;
    Navigator.of(context).pop(showPro);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Kuktám Pro funkció'),
    scrollable: true,
    content: _FeaturePanel(
      feature: widget.feature,
      onViewPro: () => _close(true),
    ),
    actions: [
      TextButton(onPressed: () => _close(false), child: const Text('Mégse')),
    ],
  );
}

class _FeaturePanel extends StatelessWidget {
  const _FeaturePanel({required this.feature, this.onViewPro});
  final ProFeature feature;
  final VoidCallback? onViewPro;
  @override
  Widget build(BuildContext context) => StreamBuilder<ClientEntitlementState>(
    stream: FeatureGate.repository(context)?.changes,
    builder: (context, _) {
      final decision = FeatureGate.check(context, feature);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            decision == FeatureAccessDecision.allowed
                ? 'A Pro funkció már elérhető. Zárd be ezt az üzenetet, és indítsd újra.'
                : FeatureGate.message(context, feature),
          ),
          if (decision == FeatureAccessDecision.requiresPro) ...[
            const SizedBox(height: 12),
            const Text(
              'A Pro egyszeri vásárlással érhető el, előfizetés nélkül.',
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (onViewPro != null) {
                  onViewPro!();
                } else {
                  FeatureGate.openPro(context);
                }
              },
              child: const Text(
                'Kuktám Pro megtekintése',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      );
    },
  );
}

class ProFeatureIcon extends StatelessWidget {
  const ProFeatureIcon({super.key, required this.feature, required this.icon});
  final ProFeature feature;
  final IconData icon;
  @override
  Widget build(BuildContext context) => StreamBuilder<ClientEntitlementState>(
    stream: FeatureGate.repository(context)?.changes,
    builder: (context, _) =>
        FeatureGate.check(context, feature) == FeatureAccessDecision.requiresPro
        ? Semantics(
            label: 'Pro funkció',
            child: Badge(label: const Text('PRO'), child: Icon(icon)),
          )
        : Icon(icon),
  );
}

class _FeatureSession extends InheritedWidget {
  const _FeatureSession({super.key, required this.uid, required super.child});
  final String? uid;
  @override
  bool updateShouldNotify(_FeatureSession oldWidget) => uid != oldWidget.uid;
}
