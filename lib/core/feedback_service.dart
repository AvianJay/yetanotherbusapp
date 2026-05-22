import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_user_agent.dart';
import 'auth_token_store.dart';
import 'http_error_utils.dart';

class FeedbackRateLimitException implements Exception {
  const FeedbackRateLimitException({
    required this.message,
    this.retryAfterSeconds,
  });

  final String message;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

class FeedbackSubmissionResult {
  const FeedbackSubmissionResult({
    required this.feedbackId,
    required this.createdAt,
  });

  final String feedbackId;
  final int createdAt;

  factory FeedbackSubmissionResult.fromJson(Map<String, dynamic> json) {
    return FeedbackSubmissionResult(
      feedbackId: '${json['feedback_id'] ?? ''}',
      createdAt: _jsonInt(json['created_at']),
    );
  }
}

class FeedbackService {
  FeedbackService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<FeedbackSubmissionResult> submitFeedback({
    required String title,
    required String content,
  }) async {
    final cleanedTitle = title.trim();
    final cleanedContent = content.trim();
    if (cleanedTitle.isEmpty) {
      throw ArgumentError('標題不能為空。');
    }
    if (cleanedTitle.length > 100) {
      throw ArgumentError('標題不能超過 100 字。');
    }
    if (cleanedContent.isEmpty) {
      throw ArgumentError('內容不能為空。');
    }
    if (cleanedContent.length > 4000) {
      throw ArgumentError('內容不能超過 4000 字。');
    }

    final response = await _client.post(
      Uri.parse('${ApiConfig.baseUrl}/api/v1/feedback'),
      headers: ApiUserAgent.applyTo(const {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
        'Content-Type': 'application/json',
      }),
      body: jsonEncode({'title': cleanedTitle, 'content': cleanedContent}),
    );

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AuthTokenExpiredException('登入已失效，請重新登入。');
    }
    if (response.statusCode == 429) {
      throw FeedbackRateLimitException(
        message: rateLimitedErrorMessage,
        retryAfterSeconds: int.tryParse(response.headers['retry-after'] ?? ''),
      );
    }
    if (response.statusCode != 201) {
      throw Exception(httpErrorMessage(response, '送出意見回饋失敗。'));
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Invalid feedback response payload.');
    }
    return FeedbackSubmissionResult.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

int _jsonInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value') ?? 0;
}
