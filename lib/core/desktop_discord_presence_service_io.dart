import 'dart:io';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:discord_rich_presence/discord_rich_presence.dart';

import 'models.dart';

final desktopDiscordPresenceService = DesktopDiscordPresenceService._();

class DesktopDiscordPresenceService {
  DesktopDiscordPresenceService._();

  static const _clientId = '1499482667429920959';
  static const _reconnectDelay = Duration(seconds: 15);

  final DateTime _sessionStartedAt = DateTime.now();

  _DiscordRpcClient? _client;
  Timer? _retryTimer;
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
      _scheduleReconnect();
      return;
    }

    try {
      await client.setActivity(
        _DiscordRpcActivity(
          details: payload.details,
          state: payload.state,
          startedAt: _sessionStartedAt,
        ),
      );
      _lastPayload = payload;
    } catch (_) {
      await _disconnect();
      _scheduleReconnect();
    }
  }

  Future<_DiscordRpcClient?> _ensureConnected() async {
    if (_client != null) {
      return _client;
    }
    final now = DateTime.now();
    if (_nextReconnectAt != null && now.isBefore(_nextReconnectAt!)) {
      _scheduleReconnect();
      return null;
    }

    try {
      final client = _createClient();
      await client.connect();
      _client = client;
      _nextReconnectAt = null;
      _retryTimer?.cancel();
      _retryTimer = null;
      return client;
    } catch (_) {
      _nextReconnectAt = now.add(_reconnectDelay);
      _scheduleReconnect();
      return null;
    }
  }

  _DiscordRpcClient _createClient() {
    if (Platform.isWindows) {
      return _WindowsDiscordRpcClient(clientId: _clientId);
    }
    return _PackageDiscordRpcClient(clientId: _clientId);
  }

  void _scheduleReconnect() {
    if (_retryTimer?.isActive == true) {
      return;
    }
    final settings = _settings;
    if (settings == null || !settings.desktopDiscordPresenceEnabled) {
      return;
    }
    final nextReconnectAt = _nextReconnectAt;
    final delay = nextReconnectAt == null
        ? _reconnectDelay
        : nextReconnectAt.difference(DateTime.now());
    _retryTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
      _retryTimer = null;
      unawaited(_apply());
    });
  }

  Future<void> _disconnect() async {
    _retryTimer?.cancel();
    _retryTimer = null;
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

class _DiscordRpcActivity {
  const _DiscordRpcActivity({
    required this.details,
    this.state,
    required this.startedAt,
  });

  final String details;
  final String? state;
  final DateTime startedAt;
}

abstract class _DiscordRpcClient {
  Future<void> connect();

  Future<void> setActivity(_DiscordRpcActivity activity);

  Future<void> disconnect();
}

class _PackageDiscordRpcClient implements _DiscordRpcClient {
  _PackageDiscordRpcClient({required String clientId})
    : _client = Client(clientId: clientId);

  final Client _client;

  @override
  Future<void> connect() {
    return _client.connect();
  }

  @override
  Future<void> setActivity(_DiscordRpcActivity activity) {
    return _client.setActivity(
      Activity(
        name: 'YetAnotherBusApp',
        type: ActivityType.playing,
        details: activity.details,
        state: activity.state,
        timestamps: ActivityTimestamps(start: activity.startedAt),
      ),
    );
  }

  @override
  Future<void> disconnect() {
    return _client.disconnect();
  }
}

class _WindowsDiscordRpcClient implements _DiscordRpcClient {
  _WindowsDiscordRpcClient({required this.clientId});

  static const _opcodeHandshake = 0;
  static const _opcodeFrame = 1;
  static const _opcodeClose = 2;
  static const _opcodePing = 3;
  static const _opcodePong = 4;

  final String clientId;

  RandomAccessFile? _pipe;
  bool _closing = false;
  int _nonceCounter = 0;

  @override
  Future<void> connect() async {
    final pipe = await _openPipe();
    if (pipe == null) {
      throw StateError('Discord IPC unavailable.');
    }

    _closing = false;
    _pipe = pipe;
    unawaited(_readLoop());
    try {
      await _sendMessage(
        opcode: _opcodeHandshake,
        payload: <String, Object?>{'v': 1, 'client_id': clientId},
      );
    } catch (_) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> setActivity(_DiscordRpcActivity activity) {
    return _sendMessage(
      opcode: _opcodeFrame,
      payload: <String, Object?>{
        'cmd': 'SET_ACTIVITY',
        'args': <String, Object?>{
          'pid': pid,
          'activity': <String, Object?>{
            'name': 'YetAnotherBusApp',
            'type': 0,
            'details': activity.details,
            if (activity.state != null) 'state': activity.state,
            'timestamps': <String, Object?>{
              'start': activity.startedAt.millisecondsSinceEpoch,
            },
          },
        },
        'evt': '',
        'nonce': _nextNonce(),
      },
    );
  }

  @override
  Future<void> disconnect() async {
    _closing = true;
    final pipe = _pipe;
    _pipe = null;
    if (pipe == null) {
      return;
    }

    try {
      final payload = _encodeMessage(
        _opcodeClose,
        const <String, Object?>{},
      );
      await pipe.writeFrom(payload);
    } catch (_) {
      // Ignore disconnect write failures.
    }

    try {
      await pipe.close();
    } catch (_) {
      // Ignore close errors.
    }
  }

  Future<RandomAccessFile?> _openPipe() async {
    for (var index = 0; index < 10; index++) {
      try {
        return await File(_pipePath(index)).open(mode: FileMode.write);
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _pipePath(int index) => '\\\\?\\pipe\\discord-ipc-$index';

  Future<void> _readLoop() async {
    try {
      while (!_closing) {
        final headerBytes = await _readExact(8);
        if (headerBytes == null) {
          break;
        }

        final header = ByteData.sublistView(headerBytes);
        final opcode = header.getInt32(0, Endian.little);
        final payloadLength = header.getInt32(4, Endian.little);
        final payloadBytes = payloadLength == 0
            ? Uint8List(0)
            : await _readExact(payloadLength);
        if (payloadBytes == null) {
          break;
        }

        if (opcode == _opcodePing) {
          final payload = _decodePayload(payloadBytes);
          await _sendMessage(opcode: _opcodePong, payload: payload);
          continue;
        }
        if (opcode == _opcodeClose) {
          break;
        }
      }
    } catch (_) {
      // Ignore transport read errors; the service will reconnect on next update.
    } finally {
      if (!_closing) {
        await disconnect();
      }
    }
  }

  Future<Uint8List?> _readExact(int byteCount) async {
    final pipe = _pipe;
    if (pipe == null) {
      return null;
    }

    final builder = BytesBuilder(copy: false);
    while (builder.length < byteCount) {
      final remaining = byteCount - builder.length;
      final chunk = await pipe.read(remaining);
      if (chunk.isEmpty) {
        return null;
      }
      builder.add(chunk);
    }
    return builder.toBytes();
  }

  Future<void> _sendMessage({
    required int opcode,
    required Map<String, Object?> payload,
  }) async {
    final pipe = _pipe;
    if (pipe == null) {
      throw StateError('Discord IPC not connected.');
    }

    final message = _encodeMessage(opcode, payload);
    await pipe.writeFrom(message);
  }

  Uint8List _encodeMessage(int opcode, Map<String, Object?> payload) {
    final body = utf8.encode(jsonEncode(payload));
    final header = ByteData(8)
      ..setInt32(0, opcode, Endian.little)
      ..setInt32(4, body.length, Endian.little);
    final builder = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(body);
    return builder.toBytes();
  }

  Map<String, Object?> _decodePayload(Uint8List payloadBytes) {
    if (payloadBytes.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(utf8.decode(payloadBytes));
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return const <String, Object?>{};
  }

  String _nextNonce() {
    _nonceCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_nonceCounter';
  }
}
