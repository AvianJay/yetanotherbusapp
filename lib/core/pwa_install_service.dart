import 'package:flutter/foundation.dart';

import 'pwa_install_service_stub.dart'
    if (dart.library.html) 'pwa_install_service_web.dart';

enum PwaInstallPromptOutcome {
  accepted,
  dismissed,
  unavailable,
}

class PwaInstallState {
  const PwaInstallState({
    required this.isSupported,
    required this.canInstall,
    required this.isInstalled,
  });

  final bool isSupported;
  final bool canInstall;
  final bool isInstalled;

  bool get shouldShowInstallAction =>
      isSupported && canInstall && !isInstalled;
}

abstract class PwaInstallService {
  const PwaInstallService();

  ValueListenable<PwaInstallState> get stateListenable;

  Future<PwaInstallPromptOutcome> promptInstall();
}

final PwaInstallService pwaInstallService = createPlatformPwaInstallService();

PwaInstallService createPwaInstallService() => pwaInstallService;