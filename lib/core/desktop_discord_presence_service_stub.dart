import 'models.dart';

class DesktopDiscordPresenceService {
  const DesktopDiscordPresenceService();

  Future<void> updateScreen({
    required AppSettings settings,
    required String screenLabel,
    BusProvider? provider,
    String? routeName,
  }) async {}

  Future<void> refresh({required AppSettings settings}) async {}

  Future<void> dispose() async {}
}

const desktopDiscordPresenceService = DesktopDiscordPresenceService();
