import 'dart:io';

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'models.dart';

final desktopDiscordPresenceService = DesktopDiscordPresenceService._();

class DesktopDiscordPresenceService {
  DesktopDiscordPresenceService._();

  static const _clientId = '1499482667429920959';
  static const _reconnectDelay = Duration(seconds: 15);
  static const _postConnectReplayDelay = Duration(milliseconds: 900);

  final DateTime _sessionStartedAt = DateTime.now();

  _DiscordRpcClient? _client;
  Future<_DiscordRpcClient?>? _connectInFlight;
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
    String? stateLabel,
  }) async {
    _settings = settings;
    _view = _DesktopPresenceView(
      screenLabel: screenLabel,
      provider: provider,
      routeName: routeName,
      stateLabel: stateLabel,
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

    final connection = await _ensureConnected();
    if (connection == null) {
      _scheduleReconnect();
      return;
    }

    final activity = _activityFromPayload(payload);
    try {
      await connection.client.setActivity(activity);
      _lastPayload = payload;
      if (connection.isFreshConnection) {
        _schedulePostConnectReplay(
          client: connection.client,
          payload: payload,
          activity: activity,
        );
      }
    } catch (_) {
      await _disconnect();
      _scheduleReconnect();
    }
  }

  Future<_DiscordRpcConnection?> _ensureConnected() async {
    final existingClient = _client;
    if (existingClient != null) {
      return _DiscordRpcConnection(
        client: existingClient,
        isFreshConnection: false,
      );
    }

    final inFlight = _connectInFlight;
    if (inFlight != null) {
      final client = await inFlight;
      if (client == null) {
        return null;
      }
      return _DiscordRpcConnection(client: client, isFreshConnection: false);
    }

    final connectFuture = _connectFreshClient();
    _connectInFlight = connectFuture;
    try {
      final client = await connectFuture;
      if (client == null) {
        return null;
      }
      return _DiscordRpcConnection(client: client, isFreshConnection: true);
    } finally {
      if (identical(_connectInFlight, connectFuture)) {
        _connectInFlight = null;
      }
    }
  }

  Future<_DiscordRpcClient?> _connectFreshClient() async {
    final now = DateTime.now();
    if (_nextReconnectAt != null && now.isBefore(_nextReconnectAt!)) {
      _scheduleReconnect();
      return null;
    }

    try {
      final client = _createClient();
      await client.connect();

      final settings = _settings;
      if (settings == null || !settings.desktopDiscordPresenceEnabled) {
        await client.disconnect();
        return null;
      }

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
    // The package transport writes JSON frames from UTF-16 code units,
    // which breaks non-ASCII presence strings on desktop IPC transports.
    if (Platform.isWindows) {
      return _WindowsDiscordRpcClient(clientId: _clientId);
    }
    return _UnixDiscordRpcClient(clientId: _clientId);
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

  _DiscordRpcActivity _activityFromPayload(_DesktopPresencePayload payload) {
    return _DiscordRpcActivity(
      details: payload.details,
      state: payload.state,
      iconName: payload.iconName,
      startedAt: _sessionStartedAt,
    );
  }

  void _schedulePostConnectReplay({
    required _DiscordRpcClient client,
    required _DesktopPresencePayload payload,
    required _DiscordRpcActivity activity,
  }) {
    unawaited(
      _replayPostConnectActivity(
        client: client,
        payload: payload,
        activity: activity,
      ),
    );
  }

  Future<void> _replayPostConnectActivity({
    required _DiscordRpcClient client,
    required _DesktopPresencePayload payload,
    required _DiscordRpcActivity activity,
  }) async {
    await Future<void>.delayed(_postConnectReplayDelay);

    final settings = _settings;
    if (_client != client || settings == null) {
      return;
    }
    if (!settings.desktopDiscordPresenceEnabled || _lastPayload != payload) {
      return;
    }

    try {
      await client.setActivity(activity);
    } catch (_) {
      await _disconnect();
      _scheduleReconnect();
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

    final iconName = settings.desktopDiscordShowProvider && view.provider != null
        ? _limitField(view.provider!.label)
        : null;

    String details;
    String? state;
    switch (view.screenLabel) {
      case '查看路線':
        details = '正在查看公車路線';
        if (showRouteName) {
          details = '$details $routeName';
        }
        state = settings.desktopDiscordShowScreen ? view.stateLabel : null;
        break;
      case 'YouBike':
        details = '正在尋找 YouBike 站點';
        state = settings.desktopDiscordShowScreen ? view.stateLabel : null;
        break;
      default:
        details = showRouteName ? routeName : view.screenLabel;
        state = settings.desktopDiscordShowScreen ? view.stateLabel : null;
        break;
    }

    return _DesktopPresencePayload(
      details: _limitField(details.isEmpty ? '使用中' : details),
      state: state == null ? null : _limitField(state),
      iconName: iconName,
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
    this.stateLabel,
  });

  final String screenLabel;
  final BusProvider? provider;
  final String? routeName;
  final String? stateLabel;
}

class _DesktopPresencePayload {
  const _DesktopPresencePayload({
    required this.details,
    this.state,
    this.iconName,
  });

  final String details;
  final String? state;
  final String? iconName;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _DesktopPresencePayload &&
        other.details == details &&
        other.state == state &&
        other.iconName == iconName;
  }

  @override
  int get hashCode => Object.hash(details, state, iconName);
}

class _DiscordRpcActivity {
  const _DiscordRpcActivity({
    required this.details,
    this.state,
    this.iconName,
    required this.startedAt,
  });

  final String details;
  final String? state;
  final String? iconName;
  final DateTime startedAt;
}

class _DiscordRpcConnection {
  const _DiscordRpcConnection({
    required this.client,
    required this.isFreshConnection,
  });

  final _DiscordRpcClient client;
  final bool isFreshConnection;
}

abstract class _DiscordRpcClient {
  Future<void> connect();

  Future<void> setActivity(_DiscordRpcActivity activity);

  Future<void> disconnect();
}

// ignore: unused_element
class _UnixDiscordRpcClient implements _DiscordRpcClient {
  _UnixDiscordRpcClient({required this.clientId});

  static const _opcodeHandshake = 0;
  static const _opcodeFrame = 1;
  static const _opcodeClose = 2;
  static const _opcodePing = 3;
  static const _opcodePong = 4;
  static const _connectTimeout = Duration(seconds: 5);

  final String clientId;

  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  Uint8List _pendingBytes = Uint8List(0);
  Completer<void>? _readyCompleter;
  bool _closing = false;
  int _nonceCounter = 0;

  @override
  Future<void> connect() async {
    final socket = await _openSocket();
    if (socket == null) {
      throw StateError('Discord IPC unavailable.');
    }

    _closing = false;
    _socket = socket;
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;
    _subscription = socket.listen(
      _handleChunk,
      onError: (Object error, StackTrace stackTrace) {
        _completeReadyError(error, stackTrace);
      },
      onDone: () {
        _completeReadyError(
          StateError('Discord IPC closed during handshake.'),
          StackTrace.current,
        );
        if (!_closing) {
          unawaited(disconnect());
        }
      },
      cancelOnError: false,
    );

    try {
      await _sendMessage(
        opcode: _opcodeHandshake,
        payload: <String, Object?>{'v': 1, 'client_id': clientId},
      );
      await readyCompleter.future.timeout(_connectTimeout);
    } catch (_) {
      await disconnect();
      rethrow;
    } finally {
      if (identical(_readyCompleter, readyCompleter)) {
        _readyCompleter = null;
      }
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
            if (activity.iconName != null) 'icon_name': activity.iconName,
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
    _completeReadyError(StateError('Discord IPC disconnected.'), null);

    final socket = _socket;
    _socket = null;
    _pendingBytes = Uint8List(0);

    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    if (socket == null) {
      return;
    }

    try {
      final payload = _encodeMessage(_opcodeClose, const <String, Object?>{});
      socket.add(payload);
      await socket.flush();
    } catch (_) {
      // Ignore disconnect write failures.
    }

    try {
      await socket.close();
    } catch (_) {
      socket.destroy();
    }
  }

  Future<Socket?> _openSocket() async {
    for (var index = 0; index < 10; index++) {
      final path = _socketPath(index);
      try {
        return await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix),
          0,
          timeout: const Duration(seconds: 3),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String _socketPath(int index) {
    final environment = Platform.environment;
    final prefix = environment['XDG_RUNTIME_DIR'] ??
        environment['TMPDIR'] ??
        environment['TMP'] ??
        environment['TEMP'] ??
        '/tmp';
    return '$prefix/discord-ipc-$index';
  }

  void _handleChunk(Uint8List chunk) {
    _pendingBytes = _appendBytes(_pendingBytes, chunk);

    while (true) {
      if (_pendingBytes.length < 8) {
        return;
      }

      final header = ByteData.sublistView(_pendingBytes, 0, 8);
      final opcode = header.getInt32(0, Endian.little);
      final payloadLength = header.getInt32(4, Endian.little);
      final totalLength = 8 + payloadLength;
      if (_pendingBytes.length < totalLength) {
        return;
      }

      final payloadBytes = Uint8List.sublistView(_pendingBytes, 8, totalLength);
      _pendingBytes = Uint8List.sublistView(_pendingBytes, totalLength);
      final payload = _decodePayload(payloadBytes);
      _handleMessage(opcode: opcode, payload: payload);
    }
  }

  void _handleMessage({
    required int opcode,
    required Map<String, Object?> payload,
  }) {
    if (opcode == _opcodePing) {
      unawaited(_sendMessage(opcode: _opcodePong, payload: payload));
      return;
    }

    if (opcode == _opcodeClose) {
      _completeReadyError(
        StateError('Discord IPC closed the connection.'),
        StackTrace.current,
      );
      if (!_closing) {
        unawaited(disconnect());
      }
      return;
    }

    if (opcode == _opcodeFrame && _isReadyEvent(payload)) {
      final readyCompleter = _readyCompleter;
      if (readyCompleter != null && !readyCompleter.isCompleted) {
        readyCompleter.complete();
      }
    }
  }

  Future<void> _sendMessage({
    required int opcode,
    required Map<String, Object?> payload,
  }) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('Discord IPC not connected.');
    }

    socket.add(_encodeMessage(opcode, payload));
    await socket.flush();
  }

  void _completeReadyError(Object error, StackTrace? stackTrace) {
    final readyCompleter = _readyCompleter;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(error, stackTrace ?? StackTrace.current);
    }
  }

  String _nextNonce() {
    _nonceCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_nonceCounter';
  }
}

class _WindowsDiscordRpcClient implements _DiscordRpcClient {
  _WindowsDiscordRpcClient({required this.clientId});

  static const _opcodeHandshake = 0;
  static const _opcodeFrame = 1;
  static const _opcodeClose = 2;
  static const _opcodePing = 3;
  static const _opcodePong = 4;
  static const _readPollInterval = Duration(milliseconds: 50);
  static const _genericRead = 0x80000000;
  static const _genericWrite = 0x40000000;
  static const _openExisting = 3;
  static const _invalidHandleValue = -1;

  static final ffi.DynamicLibrary _kernel32 = ffi.DynamicLibrary.open(
    'kernel32.dll',
  );
  static final _createFile = _kernel32.lookupFunction<
    ffi.IntPtr Function(
      ffi.Pointer<Utf16>,
      ffi.Uint32,
      ffi.Uint32,
      ffi.Pointer<ffi.Void>,
      ffi.Uint32,
      ffi.Uint32,
      ffi.IntPtr,
    ),
    int Function(
      ffi.Pointer<Utf16>,
      int,
      int,
      ffi.Pointer<ffi.Void>,
      int,
      int,
      int,
    )
  >('CreateFileW');
  static final _peekNamedPipe = _kernel32.lookupFunction<
    ffi.Int32 Function(
      ffi.IntPtr,
      ffi.Pointer<ffi.Void>,
      ffi.Uint32,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Uint32>,
    ),
    int Function(
      int,
      ffi.Pointer<ffi.Void>,
      int,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Uint32>,
    )
  >('PeekNamedPipe');
  static final _readFile = _kernel32.lookupFunction<
    ffi.Int32 Function(
      ffi.IntPtr,
      ffi.Pointer<ffi.Uint8>,
      ffi.Uint32,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Void>,
    ),
    int Function(
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Void>,
    )
  >('ReadFile');
  static final _writeFile = _kernel32.lookupFunction<
    ffi.Int32 Function(
      ffi.IntPtr,
      ffi.Pointer<ffi.Uint8>,
      ffi.Uint32,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Void>,
    ),
    int Function(
      int,
      ffi.Pointer<ffi.Uint8>,
      int,
      ffi.Pointer<ffi.Uint32>,
      ffi.Pointer<ffi.Void>,
    )
  >('WriteFile');
  static final _closeHandle = _kernel32.lookupFunction<
    ffi.Int32 Function(ffi.IntPtr),
    int Function(int)
  >('CloseHandle');

  final String clientId;

  int? _pipeHandle;
  Timer? _readTimer;
  bool _closing = false;
  bool _reading = false;
  int _nonceCounter = 0;
  Completer<void>? _readyCompleter;
  Uint8List _pendingBytes = Uint8List(0);

  @override
  Future<void> connect() async {
    final pipeHandle = _openPipe();
    if (pipeHandle == null) {
      throw StateError('Discord IPC unavailable.');
    }

    _closing = false;
    _pipeHandle = pipeHandle;
    _pendingBytes = Uint8List(0);
    final readyCompleter = Completer<void>();
    _readyCompleter = readyCompleter;
    _readTimer = Timer.periodic(_readPollInterval, (_) {
      unawaited(_pumpRead());
    });

    try {
      await _sendMessage(
        opcode: _opcodeHandshake,
        payload: <String, Object?>{'v': 1, 'client_id': clientId},
      );
      unawaited(_pumpRead());
      await readyCompleter.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      await disconnect();
      rethrow;
    } finally {
      if (identical(_readyCompleter, readyCompleter)) {
        _readyCompleter = null;
      }
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
            if (activity.iconName != null) 'icon_name': activity.iconName,
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
    _readTimer?.cancel();
    _readTimer = null;
    final readyCompleter = _readyCompleter;
    _readyCompleter = null;
    if (readyCompleter != null && !readyCompleter.isCompleted) {
      readyCompleter.completeError(
        StateError('Discord IPC disconnected.'),
        StackTrace.current,
      );
    }
    final pipeHandle = _pipeHandle;
    _pipeHandle = null;
    _pendingBytes = Uint8List(0);
    if (pipeHandle == null) {
      return;
    }

    try {
      _writeBytes(
        pipeHandle,
        _encodeMessage(_opcodeClose, const <String, Object?>{}),
      );
    } catch (_) {
      // Ignore disconnect write failures.
    }

    _closeHandle(pipeHandle);
  }

  int? _openPipe() {
    for (var index = 0; index < 10; index++) {
      final path = _pipePath(index).toNativeUtf16();
      try {
        final handle = _createFile(
          path,
          _genericRead | _genericWrite,
          0,
          ffi.nullptr,
          _openExisting,
          0,
          0,
        );
        if (handle != _invalidHandleValue) {
          return handle;
        }
      } finally {
        calloc.free(path);
      }
    }

    return null;
  }

  String _pipePath(int index) => r'\\?\pipe\discord-ipc-' '$index';

  Future<void> _pumpRead() async {
    if (_reading || _closing) {
      return;
    }

    _reading = true;
    try {
      while (!_closing) {
        final pipeHandle = _pipeHandle;
        if (pipeHandle == null) {
          return;
        }

        final availableBytes = _peekAvailableBytes(pipeHandle);
        if (availableBytes == null) {
          throw StateError('Discord IPC peek failed.');
        }
        if (availableBytes == 0) {
          return;
        }

        final chunk = _readAvailableBytes(pipeHandle, availableBytes);
        if (chunk == null || chunk.isEmpty) {
          throw StateError('Discord IPC closed during read.');
        }

        _pendingBytes = _appendBytes(_pendingBytes, chunk);
        _drainPendingMessages();
      }
    } catch (_) {
      if (!_closing) {
        await disconnect();
      }
    } finally {
      _reading = false;
    }
  }

  void _drainPendingMessages() {
    while (true) {
      if (_pendingBytes.length < 8) {
        return;
      }

      final header = ByteData.sublistView(_pendingBytes, 0, 8);
      final opcode = header.getInt32(0, Endian.little);
      final payloadLength = header.getInt32(4, Endian.little);
      final totalLength = 8 + payloadLength;
      if (_pendingBytes.length < totalLength) {
        return;
      }

      final payloadBytes = Uint8List.fromList(
        Uint8List.sublistView(_pendingBytes, 8, totalLength),
      );
      _pendingBytes = Uint8List.sublistView(_pendingBytes, totalLength);

      if (opcode == _opcodePing) {
        final payload = _decodePayload(payloadBytes);
        unawaited(_sendMessage(opcode: _opcodePong, payload: payload));
        continue;
      }

      if (opcode == _opcodeClose) {
        final readyCompleter = _readyCompleter;
        if (readyCompleter != null && !readyCompleter.isCompleted) {
          readyCompleter.completeError(
            StateError('Discord IPC closed the connection.'),
            StackTrace.current,
          );
        }
        return;
      }

      if (opcode == _opcodeFrame) {
        final payload = _decodePayload(payloadBytes);
        final readyCompleter = _readyCompleter;
        if (_isReadyEvent(payload) &&
            readyCompleter != null &&
            !readyCompleter.isCompleted) {
          readyCompleter.complete();
        }
      }
    }
  }

  int? _peekAvailableBytes(int pipeHandle) {
    final totalBytesAvail = calloc<ffi.Uint32>();
    try {
      final result = _peekNamedPipe(
        pipeHandle,
        ffi.nullptr,
        0,
        ffi.nullptr.cast<ffi.Uint32>(),
        totalBytesAvail,
        ffi.nullptr.cast<ffi.Uint32>(),
      );
      if (result == 0) {
        return null;
      }
      return totalBytesAvail.value;
    } finally {
      calloc.free(totalBytesAvail);
    }
  }

  Uint8List? _readAvailableBytes(int pipeHandle, int availableBytes) {
    final bytesToRead = availableBytes > 4096 ? 4096 : availableBytes;
    final chunk = calloc<ffi.Uint8>(bytesToRead);
    final bytesRead = calloc<ffi.Uint32>();
    try {
      final result = _readFile(
        pipeHandle,
        chunk,
        bytesToRead,
        bytesRead,
        ffi.nullptr,
      );
      if (result == 0) {
        return null;
      }

      final readCount = bytesRead.value;
      if (readCount == 0) {
        return Uint8List(0);
      }
      return Uint8List.fromList(chunk.asTypedList(readCount));
    } finally {
      calloc.free(bytesRead);
      calloc.free(chunk);
    }
  }

  Future<void> _sendMessage({
    required int opcode,
    required Map<String, Object?> payload,
  }) async {
    final pipeHandle = _pipeHandle;
    if (pipeHandle == null) {
      throw StateError('Discord IPC not connected.');
    }

    _writeBytes(pipeHandle, _encodeMessage(opcode, payload));
  }

  void _writeBytes(int pipeHandle, Uint8List message) {
    final messagePtr = calloc<ffi.Uint8>(message.length);
    final bytesWritten = calloc<ffi.Uint32>();
    try {
      messagePtr.asTypedList(message.length).setAll(0, message);
      final result = _writeFile(
        pipeHandle,
        messagePtr,
        message.length,
        bytesWritten,
        ffi.nullptr,
      );
      if (result == 0 || bytesWritten.value != message.length) {
        throw StateError('Discord IPC write failed.');
      }
    } finally {
      calloc.free(bytesWritten);
      calloc.free(messagePtr);
    }
  }

  String _nextNonce() {
    _nonceCounter += 1;
    return '${DateTime.now().microsecondsSinceEpoch}-$_nonceCounter';
  }
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
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
  return const <String, Object?>{};
}

Uint8List _appendBytes(Uint8List existing, Uint8List additional) {
  if (existing.isEmpty) {
    return Uint8List.fromList(additional);
  }
  if (additional.isEmpty) {
    return existing;
  }

  final combined = Uint8List(existing.length + additional.length)
    ..setAll(0, existing)
    ..setAll(existing.length, additional);
  return combined;
}

bool _isReadyEvent(Map<String, Object?> payload) {
  return payload['evt']?.toString() == 'READY';
}
