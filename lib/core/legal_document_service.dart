import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'api_user_agent.dart';

class LegalDocumentService {
  LegalDocumentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<String> fetchTermsOfService() {
    return _fetchMarkdownDocument('/api/v1/terms-of-service');
  }

  Future<String> fetchPrivacyPolicy() {
    return _fetchMarkdownDocument('/api/v1/privacy-policy');
  }

  Future<String> _fetchMarkdownDocument(String path) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    final response = await _client.get(
      uri,
      headers: ApiUserAgent.applyTo(const {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip',
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, '文件載入失敗。'));
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid legal document payload.');
    }

    final content = '${decoded['content'] ?? ''}'.trim();
    if (content.isEmpty) {
      throw const FormatException('Missing legal document content.');
    }
    return content;
  }
}

String _errorMessage(http.Response response, String fallback) {
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map && decoded['detail'] != null) {
      final detail = '${decoded['detail']}'.trim();
      if (detail.isNotEmpty) {
        return detail;
      }
    }
  } catch (_) {
    // Ignore malformed error payloads and fall back to the generic message.
  }
  return fallback;
}