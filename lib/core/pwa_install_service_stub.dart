import 'package:flutter/foundation.dart';

import 'pwa_install_service.dart';

class _StubPwaInstallService extends PwaInstallService {
  _StubPwaInstallService();

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
    return PwaInstallPromptOutcome.unavailable;
  }
}

PwaInstallService createPlatformPwaInstallService() => _StubPwaInstallService();