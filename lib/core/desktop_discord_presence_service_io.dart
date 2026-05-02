import 'dart:io';

import 'package:discord_rich_presence/discord_rich_presence.dart';

import 'models.dart';

final desktopDiscordPresenceService = DesktopDiscordPresenceService._();

class DesktopDiscordPresenceService {
  DesktopDiscordPresenceService._();

  static const _clientId = '1499482667429920959';
  static const _reconnectDelay = Duration(seconds: 15);

  final DateTime _sessionStartedAt = DateTime.now();

  Client? _client;
  DateTime? _nextReconnectAt;
  AppSettings? _settings;
  _DesktopPresenceView _view = const _DesktopPresenceView(screenLabel: '公車首頁');
  _DesktopPresencePayload? _lastPayload;

  bool get _supportsPlatform =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  Future<void> updateScreen({
    required AppSettings settings,
    required String screenLabel,
    BusProvider? provider,
    String? routeName,
  }) async {
    _settings = settings;
    _view = _DesktopPresenceView(
      screenLabel: screenLabel,
      provider: provider,
      routeName: routeName,
    );
    await _apply();
  }

  Future<void> refresh({required AppSettings settings}) async {
    _settings = settings;
    await _apply();
  }

  Future<void> dispose() async {
    await _disconnect();
  }

  Future<void> _apply() async {
    if (!_supportsPlatform) {
      return;
    }

    final settings = _settings;
    if (settings == null) {
      return;
    }
    if (!settings.desktopDiscordPresenceEnabled) {
      await _disconnect();
      return;
    }

    final payload = _buildPayload(settings, _view);
    if (_client != null && payload == _lastPayload) {
      return;
    }

    final client = await _ensureConnected();
    if (client == null) {
      return;
    }

    try {
      await client.setActivity(
        Activity(
          name: 'YetAnotherBusApp',
          type: ActivityType.playing,
          details: payload.details,
          state: payload.state,
          timestamps: ActivityTimestamps(start: _sessionStartedAt),
        ),
      );
      _lastPayload = payload;
    } catch (_) {
      await _disconnect();
    }
  }

  Future<Client?> _ensureConnected() async {
    if (_client != null) {
      return _client;
    }
    final now = DateTime.now();
    if (_nextReconnectAt != null && now.isBefore(_nextReconnectAt!)) {
      return null;
    }

    try {
      final client = Client(clientId: _clientId);
      await client.connect();
      _client = client;
      _nextReconnectAt = null;
      return client;
    } catch (_) {
      _nextReconnectAt = now.add(_reconnectDelay);
      return null;
    }
  }

  Future<void> _disconnect() async {
    final client = _client;
    _client = null;
    _lastPayload = null;
    if (client == null) {
      return;
    }
    try {
      await client.disconnect();
    } catch (_) {
      // Ignore transport shutdown errors.
    }
  }

  _DesktopPresencePayload _buildPayload(
    AppSettings settings,
    _DesktopPresenceView view,
  ) {
    final routeName = view.routeName?.trim();
    final showRouteName =
        settings.desktopDiscordShowRouteName &&
        routeName != null &&
        routeName.isNotEmpty;

    final secondaryLines = <String>[
      if (settings.desktopDiscordShowScreen) view.screenLabel,
      if (settings.desktopDiscordShowProvider && view.provider != null)
        view.provider!.label,
    ];

    String? details = showRouteName ? routeName : null;
    if (details == null && secondaryLines.isNotEmpty) {
      details = secondaryLines.removeAt(0);
    }
    final state = secondaryLines.isEmpty ? null : secondaryLines.join(' · ');

    return _DesktopPresencePayload(
      details: _limitField(details ?? '使用中'),
      state: state == null ? null : _limitField(state),
    );
  }

  String _limitField(String value) {
    final normalized = value.trim();
    if (normalized.length <= 120) {
      return normalized;
    }
    return '${normalized.substring(0, 117)}...';
  }
}

class _DesktopPresenceView {
  const _DesktopPresenceView({
    required this.screenLabel,
    this.provider,
    this.routeName,
  });

  final String screenLabel;
  final BusProvider? provider;
  final String? routeName;
}

class _DesktopPresencePayload {
  const _DesktopPresencePayload({required this.details, this.state});

  final String details;
  final String? state;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _DesktopPresencePayload &&
        other.details == details &&
        other.state == state;
  }

  @override
  int get hashCode => Object.hash(details, state);
}
