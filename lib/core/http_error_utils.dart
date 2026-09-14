import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_http.dart';

const rateLimitedErrorMessage = '你已受到速率限制。';

bool isRateLimitedStatusCode(int statusCode) => statusCode == 429;

bool isRateLimitedError(Object error) {
  final message = error.toString();
  return message.contains(rateLimitedErrorMessage) ||
      message.contains('Too Many Requests') ||
      message.contains('429');
}

String httpErrorMessage(http.Response response, String fallback) {
  if (isRateLimitedStatusCode(response.statusCode)) {
    return rateLimitedErrorMessage;
  }
  try {
    final decoded = jsonDecode(apiResponseText(response));
    if (decoded is Map) {
      final detail = '${decoded['detail'] ?? ''}'.trim();
      if (detail.isNotEmpty) {
        return detail;
      }
      final message = '${decoded['message'] ?? ''}'.trim();
      if (message.isNotEmpty) {
        return message;
      }
    }
  } catch (_) {
    // Ignore malformed payloads and keep the fallback.
  }
  return fallback;
}

String httpStatusMessage(int statusCode, String fallback) {
  if (isRateLimitedStatusCode(statusCode)) {
    return rateLimitedErrorMessage;
  }
  return fallback;
}

/// The server has no whole-city bus feed for this provider.
///
/// Raised for a 404, which covers both a server older than the endpoint and a
/// city the deployment does not sync. The map shows the same notice either way.
class CityBusFeedUnavailableException implements Exception {
  const CityBusFeedUnavailableException(this.provider);

  final Object provider;

  @override
  String toString() => '此城市暫不支援全公車地圖。';
}
