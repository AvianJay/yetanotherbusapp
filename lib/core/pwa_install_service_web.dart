// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/foundation.dart';

import 'pwa_install_service.dart';

class _WebPwaInstallService extends PwaInstallService {
  _WebPwaInstallService() {
    html.window.addEventListener(
      'yabus-pwa-install-state',
      _handleInstallStateChanged,
    );
    _refreshState();
  }

  final ValueNotifier<PwaInstallState> _state = ValueNotifier(
    const PwaInstallState(
      isSupported: false,
      canInstall: false,
      isInstalled: false,
    ),
  );

  @override
  ValueListenable<PwaInstallState> get stateListenable => _state;

  @override
  Future<PwaInstallPromptOutcome> promptInstall() async {
    final bridge = _bridge;
    if (bridge == null) {
      return PwaInstallPromptOutcome.unavailable;
    }

    try {
      final completer = Completer<PwaInstallPromptOutcome>();
      final callback = js.JsFunction.withThis((_, Object? outcome) {
        if (!completer.isCompleted) {
          completer.complete(_parseOutcome(outcome));
        }
      });
      bridge.callMethod('promptInstall', [callback]);
      final outcome = await completer.future;
      _refreshState();
      return outcome;
    } catch (_) {
      _refreshState();
      return PwaInstallPromptOutcome.unavailable;
    }
  }

  js.JsObject? get _bridge {
    final value = js.context['__yabusPwaInstall'];
    return value is js.JsObject ? value : null;
  }

  void _handleInstallStateChanged(html.Event _) {
    _refreshState();
  }

  void _refreshState() {
    final bridge = _bridge;
    if (bridge == null) {
      _state.value = const PwaInstallState(
        isSupported: false,
        canInstall: false,
        isInstalled: false,
      );
      return;
    }

    final rawState = bridge.callMethod('getState');
    if (rawState is! js.JsObject) {
      _state.value = const PwaInstallState(
        isSupported: false,
        canInstall: false,
        isInstalled: false,
      );
      return;
    }

    _state.value = PwaInstallState(
      isSupported: rawState['supported'] == true,
      canInstall: rawState['canInstall'] == true,
      isInstalled: rawState['installed'] == true,
    );
  }

  PwaInstallPromptOutcome _parseOutcome(Object? outcome) {
    return switch (outcome?.toString()) {
      'accepted' => PwaInstallPromptOutcome.accepted,
      'dismissed' => PwaInstallPromptOutcome.dismissed,
      _ => PwaInstallPromptOutcome.unavailable,
    };
  }
}

PwaInstallService createPlatformPwaInstallService() => _WebPwaInstallService();