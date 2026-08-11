import 'dart:convert';

import 'package:http/http.dart' as http;

import 'announcement_models.dart';
import 'api_config.dart';
import 'api_http.dart';
import 'api_user_agent.dart';
import 'auth_token_store.dart';
import 'http_error_utils.dart';

/// Result of toggling a single emoji reaction on an announcement: the
/// authoritative aggregate counts plus the caller's own reactions.
typedef AnnouncementReactionResult = ({
  List<AnnouncementReaction> reactions,
  Set<String> myReactions,
});

class AnnouncementReactionService {
  AnnouncementReactionService({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  Future<AnnouncementReactionResult> toggleReaction(
    String announcementId,
    String emoji,
  ) async {
    final response = await _client.post(
      Uri.parse(
        '${ApiConfig.baseUrl}/api/v1/announcements/'
        '${Uri.encodeComponent(announcementId)}/reactions/toggle',
      ),
      headers: ApiUserAgent.applyTo(apiJsonContentHeaders),
      body: jsonEncode({'emoji': emoji}),
    );
    _throwIfUnauthorized(response);
    if (response.statusCode != 200) {
      throw Exception(httpErrorMessage(response, '無法更新反應。'));
    }

    final decoded = apiDecodeJsonResponse(response);
    if (decoded is! Map) {
      throw const FormatException('Invalid reaction payload.');
    }
    final map = decoded.map((key, value) => MapEntry(key.toString(), value));
    return (
      reactions: _parseReactions(map['reactions']),
      myReactions: _parseMyReactions(map['my_reactions']),
    );
  }
}

List<AnnouncementReaction> _parseReactions(Object? value) {
  if (value is! List) {
    return const <AnnouncementReaction>[];
  }
  return value
      .whereType<Map>()
      .map(
        (entry) => AnnouncementReaction.fromJson(
          entry.map((key, value) => MapEntry(key.toString(), value)),
        ),
      )
      .where((reaction) => reaction.emoji.isNotEmpty)
      .toList(growable: false);
}

Set<String> _parseMyReactions(Object? value) {
  if (value is! List) {
    return const <String>{};
  }
  return value
      .map((entry) => '$entry'.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet();
}

void _throwIfUnauthorized(http.Response response) {
  if (response.statusCode == 401 || response.statusCode == 403) {
    throw const AuthTokenExpiredException('登入已失效，請重新登入。');
  }
}
