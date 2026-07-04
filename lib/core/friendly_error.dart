import 'dart:async';

import 'http_error_utils.dart';

const genericFriendlyErrorMessage = '發生錯誤，請稍後再試。';
const networkFriendlyErrorMessage = '網路連線異常，請確認網路後再試。';
const timeoutFriendlyErrorMessage = '連線逾時，請稍後再試。';

final _cjkPattern = RegExp(r'[぀-ヿ㐀-䶿一-鿿]');

const _networkErrorMarkers = [
  'SocketException',
  'ClientException',
  'HandshakeException',
  'Failed host lookup',
  'Connection refused',
  'Connection reset',
  'Connection closed',
  'Connection terminated',
  'Network is unreachable',
  'XMLHttpRequest error',
  'ERR_INTERNET_DISCONNECTED',
  'ERR_NAME_NOT_RESOLVED',
];

const _exceptionPrefixes = [
  'Exception: ',
  'HttpException: ',
  'FormatException: ',
  'Bad state: ',
];

/// Converts a caught [error] into a message that is safe to show to users.
///
/// Messages that were already written for users (they contain CJK text, e.g.
/// the ones thrown by the repository layer) pass through with their exception
/// prefix stripped. Raw network / timeout exceptions are translated, and
/// anything else falls back to [fallback] so English stack-dump text never
/// reaches the UI.
String friendlyErrorMessage(
  Object? error, {
  String fallback = genericFriendlyErrorMessage,
}) {
  if (error == null) {
    return fallback;
  }
  final raw = error.toString().trim();
  if (raw.isEmpty || raw.startsWith('Instance of ')) {
    return fallback;
  }
  if (isRateLimitedError(error)) {
    return rateLimitedErrorMessage;
  }
  if (error is TimeoutException ||
      raw.contains('TimeoutException') ||
      raw.contains('Connection timed out')) {
    return timeoutFriendlyErrorMessage;
  }
  for (final marker in _networkErrorMarkers) {
    if (raw.contains(marker)) {
      return networkFriendlyErrorMessage;
    }
  }
  final message = _stripExceptionPrefixes(raw);
  if (_cjkPattern.hasMatch(message)) {
    return message;
  }
  return fallback;
}

String _stripExceptionPrefixes(String message) {
  var result = message.trim();
  var stripped = true;
  while (stripped) {
    stripped = false;
    for (final prefix in _exceptionPrefixes) {
      if (result.startsWith(prefix)) {
        result = result.substring(prefix.length).trim();
        stripped = true;
      }
    }
  }
  return result;
}
