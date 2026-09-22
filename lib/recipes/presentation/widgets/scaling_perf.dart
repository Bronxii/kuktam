// Temporary opt-in diagnostics. Never enabled in a release build.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

const scalingPerfEnabled =
    !kReleaseMode && bool.fromEnvironment('SCALING_PERF');
const _detail = bool.fromEnvironment('SCALING_PERF_DETAIL');

class ScalingPerf extends WidgetsBindingObserver {
  ScalingPerf(int rows) {
    if (_detail) {
      debugProfileBuildsEnabled = true;
      debugProfileLayoutsEnabled = true;
      debugProfilePaintsEnabled = true;
    }
    WidgetsBinding.instance.addObserver(this);
    SchedulerBinding.instance.addTimingsCallback(_timings);
    event('open', {'rows': rows, 'detail': _detail, 'profile': kProfileMode});
  }

  final _oldBuild = debugProfileBuildsEnabled;
  final _oldLayout = debugProfileLayoutsEnabled;
  final _oldPaint = debugProfilePaintsEnabled;
  final started = developer.Timeline.now;
  final List<Map<String, Object?>> events = [];
  ui.FlutterView? view;
  int dropped = 0;

  void event(String name, [Map<String, Object?> data = const {}]) {
    if (events.length >= 20000) {
      dropped++;
      return;
    }
    events.add({'event': name, 'tUs': developer.Timeline.now, ...data});
    developer.Timeline.instantSync('[SCALING_PERF] $name', arguments: data);
  }

  void _timings(List<ui.FrameTiming> frames) {
    for (final f in frames) {
      final start = f.timestampInMicroseconds(ui.FramePhase.buildStart);
      if (start < started) continue;
      event('frame', {
        'frame': f.frameNumber,
        'vsyncUs': f.timestampInMicroseconds(ui.FramePhase.vsyncStart),
        'buildStartUs': start,
        'uiUs': f.buildDuration.inMicroseconds,
        'rasterUs': f.rasterDuration.inMicroseconds,
        'totalUs': f.totalSpan.inMicroseconds,
      });
    }
  }

  @override
  void didChangeMetrics() {
    final v = view;
    if (v == null) return;
    event('metrics', {
      'bottom': v.viewInsets.bottom / v.devicePixelRatio,
      'height': v.physicalSize.height / v.devicePixelRatio,
      'refreshHz': v.display.refreshRate,
    });
  }

  void close() {
    WidgetsBinding.instance.removeObserver(this);
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    if (_detail) {
      debugProfileBuildsEnabled = _oldBuild;
      debugProfileLayoutsEnabled = _oldLayout;
      debugProfilePaintsEnabled = _oldPaint;
    }
    event('close', {'dropped': dropped});
    // Buffer during the interaction: console output must not stall IME frames.
    for (final e in events) {
      debugPrint('[SCALING_PERF] ${jsonEncode(e)}');
    }
  }

  Widget observe(Widget child) => NotificationListener<ScrollNotification>(
    onNotification: (n) {
      event('scroll', {
        'type': n.runtimeType.toString(),
        'depth': n.depth,
        'axis': n.metrics.axis.name,
        'pixels': n.metrics.pixels,
        'viewport': n.metrics.viewportDimension,
      });
      return false;
    },
    child: _PerfProbe(perf: this, child: child),
  );
}

class _PerfProbe extends SingleChildRenderObjectWidget {
  const _PerfProbe({required this.perf, required super.child});
  final ScalingPerf perf;

  @override
  RenderObject createRenderObject(BuildContext context) => _PerfRender(perf);
}

class _PerfRender extends RenderProxyBox {
  _PerfRender(this.perf);
  final ScalingPerf perf;

  @override
  void performLayout() {
    final start = developer.Timeline.now;
    developer.Timeline.timeSync(
      '[SCALING_PERF] dialog.layout',
      super.performLayout,
    );
    perf.event('layout', {'us': developer.Timeline.now - start});
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final start = developer.Timeline.now;
    developer.Timeline.timeSync(
      '[SCALING_PERF] dialog.paint',
      () => super.paint(context, offset),
    );
    perf.event('paint', {'us': developer.Timeline.now - start});
  }

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    perf.event('showOnScreen', {
      'durationMs': duration.inMilliseconds,
      'source': descendant.runtimeType.toString(),
    });
    super.showOnScreen(
      descendant: descendant,
      rect: rect,
      duration: duration,
      curve: curve,
    );
  }
}
