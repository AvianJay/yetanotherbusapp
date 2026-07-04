import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:taiwanbus_flutter/core/bus_repository.dart';
import 'package:taiwanbus_flutter/core/friendly_error.dart';
import 'package:taiwanbus_flutter/core/http_error_utils.dart';

void main() {
  group('friendlyErrorMessage', () {
    test('keeps user-facing messages written in Chinese', () {
      expect(
        friendlyErrorMessage(DatabaseNotReadyException('尚未下載路線資料庫。')),
        '尚未下載路線資料庫。',
      );
      expect(
        friendlyErrorMessage(const HttpException('無法查詢全部路線 (500)。')),
        '無法查詢全部路線 (500)。',
      );
    });

    test('strips Exception prefixes from user-facing messages', () {
      expect(
        friendlyErrorMessage(Exception('資料庫版本格式錯誤。')),
        '資料庫版本格式錯誤。',
      );
    });

    test('translates rate-limit errors', () {
      expect(
        friendlyErrorMessage(const HttpException(rateLimitedErrorMessage)),
        rateLimitedErrorMessage,
      );
      expect(
        friendlyErrorMessage(Exception('429 Too Many Requests')),
        rateLimitedErrorMessage,
      );
    });

    test('translates network errors', () {
      expect(
        friendlyErrorMessage(
          const SocketException('Failed host lookup: api.example.com'),
        ),
        networkFriendlyErrorMessage,
      );
      expect(
        friendlyErrorMessage(Exception('XMLHttpRequest error.')),
        networkFriendlyErrorMessage,
      );
    });

    test('translates timeouts', () {
      expect(
        friendlyErrorMessage(TimeoutException('future not completed')),
        timeoutFriendlyErrorMessage,
      );
    });

    test('falls back for raw English exception text', () {
      expect(
        friendlyErrorMessage(
          StateError('Null check operator used on a null value'),
        ),
        genericFriendlyErrorMessage,
      );
      expect(
        friendlyErrorMessage(const FormatException('Unexpected character')),
        genericFriendlyErrorMessage,
      );
    });

    test('uses the provided fallback', () {
      expect(
        friendlyErrorMessage(StateError('boom'), fallback: '載入失敗，請稍後再試。'),
        '載入失敗，請稍後再試。',
      );
    });

    test('handles null and empty errors', () {
      expect(friendlyErrorMessage(null), genericFriendlyErrorMessage);
      expect(friendlyErrorMessage(''), genericFriendlyErrorMessage);
    });
  });
}
