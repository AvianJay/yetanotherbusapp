import 'dart:convert';

import 'package:http/http.dart' as http;

import 'account_sync_models.dart';
import 'api_http.dart';
import 'api_config.dart';
import 'api_user_agent.dart';
import 'auth_token_store.dart';
import 'http_error_utils.dart';

class AccountSyncService {
  AccountSyncService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<AccountSyncSummary> fetchSummary() async {
    final response = await _client.get(
      Uri.parse('${ApiConfig.baseUrl}/api/v1/account/sync'),
      headers: ApiUserAgent.applyTo(apiJsonHeaders),
    );
    _throwIfUnauthorized(response);
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, '無法取得同步狀態。'));
    }

    final decoded = apiDecodeJsonResponse(response);
    if (decoded is! Map) {
      throw const FormatException('Invalid sync summary payload.');
    }
    return AccountSyncSummary.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<AccountSyncDocument> fetchDocument(
    AccountSyncNamespace namespace,
  ) async {
    final response = await _client.get(
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/account/sync/${namespace.apiValue}',
      ),
      headers: ApiUserAgent.applyTo(apiJsonHeaders),
    );
    _throwIfUnauthorized(response);
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, '無法讀取雲端同步資料。'));
    }

    final decoded = apiDecodeJsonResponse(response);
    if (decoded is! Map) {
      throw const FormatException('Invalid sync document payload.');
    }
    return AccountSyncDocument.fromJson(
      namespace,
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  Future<AccountSyncWriteResult> upsertDocument({
    required AccountSyncNamespace namespace,
    required Map<String, dynamic> payload,
    required DateTime clientModifiedAt,
    required int schemaVersion,
    AccountSyncConflictPolicy conflictPolicy = AccountSyncConflictPolicy.abort,
    int? baseRevision,
    String? baseEtag,
  }) async {
    final response = await _client.put(
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/account/sync/${namespace.apiValue}',
      ),
      headers: ApiUserAgent.applyTo(apiJsonContentHeaders),
      body: jsonEncode({
        'schema_version': schemaVersion,
        'client_modified_at': clientModifiedAt.toUtc().toIso8601String(),
        'base_revision': baseRevision,
        'base_etag': baseEtag,
        'conflict_policy': conflictPolicy.apiValue,
        'payload': payload,
      }),
    );
    _throwIfUnauthorized(response);
    if (response.statusCode == 409) {
      final decoded = _decodedMap(response);
      throw AccountSyncConflictException.fromJson(namespace, decoded);
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_errorMessage(response, '無法寫入雲端同步資料。'));
    }

    final decoded = _decodedMap(response);
    final rawDocument = decoded['document'];
    return AccountSyncWriteResult(
      status: '${decoded['status'] ?? ''}',
      conflictPolicy: conflictPolicy,
      document: rawDocument is Map
          ? AccountSyncDocument.fromJson(
              namespace,
              rawDocument.map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
    );
  }
}

void _throwIfUnauthorized(http.Response response) {
  if (response.statusCode == 401 || response.statusCode == 403) {
    throw const AuthTokenExpiredException('登入已失效，請重新登入。');
  }
}

Map<String, dynamic> _decodedMap(http.Response response) {
  final decoded = apiDecodeJsonResponse(response);
  if (decoded is! Map) {
    throw const FormatException('Invalid sync response payload.');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

String _errorMessage(http.Response response, String fallback) =>
    httpErrorMessage(response, fallback);
