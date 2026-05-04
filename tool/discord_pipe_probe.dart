import 'dart:ffi' as ffi;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

Future<void> main() async {
  final pipe = _openPipe();
  if (pipe == null) {
    stderr.writeln('failed to open pipe');
    exitCode = 1;
    return;
  }

  try {
    _send(
      pipe,
      0,
      <String, Object?>{'v': 1, 'client_id': '1499482667429920959'},
    );
    stdout.writeln('sent handshake');

    final header = _readExact(pipe, 8);
    stdout.writeln('header length: ${header.length}');
    stdout.writeln('header bytes: ${header.toList()}');
    if (header.length != 8) {
      return;
    }

    final headerData = ByteData.sublistView(Uint8List.fromList(header));
    final opcode = headerData.getInt32(0, Endian.little);
    final payloadLength = headerData.getInt32(4, Endian.little);
    stdout.writeln('opcode: $opcode payloadLength: $payloadLength');

    final payloadBytes = _readExact(pipe, payloadLength);
    stdout.writeln('payload bytes length: ${payloadBytes.length}');
    stdout.writeln(
      'payload first bytes: ${payloadBytes.take(24).toList()}',
    );
    stdout.writeln('payload text: ${utf8.decode(payloadBytes, allowMalformed: true)}');
    final decoded = jsonDecode(utf8.decode(payloadBytes));
    stdout.writeln('payload evt: ${(decoded as Map<String, dynamic>)['evt']}');

    _send(
      pipe,
      1,
      <String, Object?>{
        'cmd': 'SET_ACTIVITY',
        'args': <String, Object?>{
          'pid': pid,
          'activity': <String, Object?>{
            'name': 'YetAnotherBusApp',
            'type': 0,
            'details': '公車首頁',
            'state': '使用中',
            'timestamps': <String, Object?>{
              'start': DateTime.now().millisecondsSinceEpoch,
            },
          },
        },
        'evt': '',
        'nonce': 'probe-1',
      },
    );
    stdout.writeln('sent activity');
  } finally {
    _closeHandle(pipe);
  }
}

const _genericRead = 0x80000000;
const _genericWrite = 0x40000000;
const _openExisting = 3;
const _invalidHandleValue = -1;

final _kernel32 = ffi.DynamicLibrary.open('kernel32.dll');

final _createFile = _kernel32.lookupFunction<
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

final _peekNamedPipe = _kernel32.lookupFunction<
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

final _readFile = _kernel32.lookupFunction<
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

final _writeFile = _kernel32.lookupFunction<
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

final _closeHandleFn = _kernel32.lookupFunction<
  ffi.Int32 Function(ffi.IntPtr),
  int Function(int)
>('CloseHandle');

final _getLastError = _kernel32.lookupFunction<
  ffi.Uint32 Function(),
  int Function()
>('GetLastError');

int? _openPipe() {
  final path = r'\\?\pipe\discord-ipc-0'.toNativeUtf16();
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
    if (handle == _invalidHandleValue) {
      stderr.writeln('CreateFileW failed: ${_getLastError()}');
      return null;
    }
    return handle;
  } finally {
    calloc.free(path);
  }
}

void _send(int pipe, int opcode, Map<String, Object?> payload) {
  final body = utf8.encode(jsonEncode(payload));
  final header = ByteData(8)
    ..setInt32(0, opcode, Endian.little)
    ..setInt32(4, body.length, Endian.little);
  final message = Uint8List(8 + body.length)
    ..setAll(0, header.buffer.asUint8List())
    ..setAll(8, body);
  final messagePtr = calloc<ffi.Uint8>(message.length);
  final bytesWritten = calloc<ffi.Uint32>();
  try {
    messagePtr.asTypedList(message.length).setAll(0, message);
    final result = _writeFile(
      pipe,
      messagePtr,
      message.length,
      bytesWritten,
      ffi.nullptr,
    );
    if (result == 0 || bytesWritten.value != message.length) {
      throw StateError(
        'WriteFile failed: ${_getLastError()} bytesWritten=${bytesWritten.value}',
      );
    }
  } finally {
    calloc.free(bytesWritten);
    calloc.free(messagePtr);
  }
}

Uint8List _readExact(int pipe, int byteCount) {
  final builder = BytesBuilder();
  while (builder.length < byteCount) {
    final remaining = byteCount - builder.length;
    final available = _peekAvailable(pipe);
    if (available <= 0) {
      sleep(const Duration(milliseconds: 20));
      continue;
    }

    final toRead = available < remaining ? available : remaining;
    final chunk = calloc<ffi.Uint8>(toRead);
    final bytesRead = calloc<ffi.Uint32>();
    try {
      final result = _readFile(pipe, chunk, toRead, bytesRead, ffi.nullptr);
      if (result == 0) {
        throw StateError('ReadFile failed: ${_getLastError()}');
      }
      final readCount = bytesRead.value;
      if (readCount == 0) {
        break;
      }
      builder.add(Uint8List.fromList(chunk.asTypedList(readCount)));
    } finally {
      calloc.free(bytesRead);
      calloc.free(chunk);
    }
  }
  return builder.toBytes();
}

int _peekAvailable(int pipe) {
  final totalBytesAvail = calloc<ffi.Uint32>();
  try {
    final result = _peekNamedPipe(
      pipe,
      ffi.nullptr,
      0,
      ffi.nullptr.cast<ffi.Uint32>(),
      totalBytesAvail,
      ffi.nullptr.cast<ffi.Uint32>(),
    );
    if (result == 0) {
      throw StateError('PeekNamedPipe failed: ${_getLastError()}');
    }
    return totalBytesAvail.value;
  } finally {
    calloc.free(totalBytesAvail);
  }
}

void _closeHandle(int handle) {
  _closeHandleFn(handle);
}