import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:taiwanbus_flutter/core/auth_token_store.dart';
import 'package:taiwanbus_flutter/core/feedback_service.dart';

void main() {
  tearDown(() {
    AuthTokenStore.token = null;
  });

  test('submitFeedback posts payload and parses success response', () async {
    AuthTokenStore.token = 'test-token';
    final service = FeedbackService(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/feedback');
        expect(
          request.headers['Authorization'] ?? request.headers['authorization'],
          'Bearer test-token',
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['title'], 'Bug report');
        expect(body['content'], 'Something broke');
        return http.Response(
          jsonEncode({
            'ok': true,
            'feedback_id': '12345',
            'created_at': 1716000000,
          }),
          201,
        );
      }),
    );

    final result = await service.submitFeedback(
      title: 'Bug report',
      content: 'Something broke',
    );

    expect(result.feedbackId, '12345');
    expect(result.createdAt, 1716000000);
  });

  test('submitFeedback surfaces rate-limit details', () async {
    final service = FeedbackService(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': 'Feedback submissions are limited to 1 per minute.',
          }),
          429,
          headers: {'retry-after': '42'},
        );
      }),
    );

    expect(
      () => service.submitFeedback(title: 'A', content: 'B'),
      throwsA(
        isA<FeedbackRateLimitException>()
            .having(
              (error) => error.message,
              'message',
              'Feedback submissions are limited to 1 per minute.',
            )
            .having(
              (error) => error.retryAfterSeconds,
              'retryAfterSeconds',
              42,
            ),
      ),
    );
  });
}
