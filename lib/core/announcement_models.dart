import 'dart:collection';

enum AnnouncementRepeatBehavior { none, once, forever }

class AnnouncementBehavior {
  const AnnouncementBehavior({
    this.redDot = AnnouncementRepeatBehavior.once,
    this.popup = AnnouncementRepeatBehavior.once,
  });

  factory AnnouncementBehavior.fromJson(Map<String, dynamic> json) {
    return AnnouncementBehavior(
      redDot: _behaviorFromString(json['red_dot']),
      popup: _behaviorFromString(json['popup']),
    );
  }

  final AnnouncementRepeatBehavior redDot;
  final AnnouncementRepeatBehavior popup;
}

class AnnouncementTargets {
  const AnnouncementTargets({this.platforms, this.versionConstraint});

  factory AnnouncementTargets.fromJson(Map<String, dynamic> json) {
    final rawPlatforms = json['platforms'];
    final platforms = rawPlatforms is List
        ? rawPlatforms
              .map((entry) => '$entry'.trim().toLowerCase())
              .where((entry) => entry.isNotEmpty)
              .toSet()
              .toList(growable: false)
        : null;
    final versionConstraint = '${json['version_constraint'] ?? ''}'.trim();
    return AnnouncementTargets(
      platforms: platforms == null || platforms.isEmpty ? null : platforms,
      versionConstraint: versionConstraint.isEmpty ? null : versionConstraint,
    );
  }

  final List<String>? platforms;
  final String? versionConstraint;
}

class AnnouncementEmbed {
  const AnnouncementEmbed({required this.type, required this.url});

  factory AnnouncementEmbed.fromJson(Map<String, dynamic> json) {
    return AnnouncementEmbed(
      type: '${json['type'] ?? ''}'.trim(),
      url: '${json['url'] ?? ''}'.trim(),
    );
  }

  final String type;
  final String url;
}

class AnnouncementAction {
  const AnnouncementAction({
    required this.type,
    required this.label,
    required this.url,
  });

  factory AnnouncementAction.fromJson(Map<String, dynamic> json) {
    return AnnouncementAction(
      type: '${json['type'] ?? ''}'.trim(),
      label: '${json['label'] ?? ''}'.trim(),
      url: '${json['url'] ?? ''}'.trim(),
    );
  }

  final String type;
  final String label;
  final String url;
}

class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.contentType,
    required this.createdAt,
    required this.behavior,
    this.author,
    this.expireAt,
    this.targets,
    this.soundUrl,
    this.embed,
    this.actions = const <AnnouncementAction>[],
  });

  factory AppAnnouncement.fromJson(Map<String, dynamic> json) {
    final rawBehavior = _stringKeyedMap(json['behavior']);
    final rawTargets = _stringKeyedMap(json['targets']);
    final rawEmbed = _stringKeyedMap(json['embed']);
    final rawActions = json['actions'];
    return AppAnnouncement(
      id: '${json['id'] ?? ''}'.trim(),
      title: '${json['title'] ?? ''}'.trim(),
      content: '${json['content'] ?? ''}',
      contentType: '${json['content_type'] ?? 'markdown'}'.trim(),
      author: _normalizedNullableText(json['author']),
      createdAt: _parseUnixSeconds(json['created_at']),
      expireAt: _parseNullableUnixSeconds(json['expire_at']),
      behavior: rawBehavior == null
          ? const AnnouncementBehavior()
          : AnnouncementBehavior.fromJson(rawBehavior),
      targets: rawTargets == null
          ? null
          : AnnouncementTargets.fromJson(rawTargets),
      soundUrl: _normalizedNullableText(json['sound_url']),
      embed: rawEmbed == null ? null : AnnouncementEmbed.fromJson(rawEmbed),
      actions: rawActions is List
          ? rawActions
                .whereType<Map>()
                .map(
                  (entry) => AnnouncementAction.fromJson(
                    entry.map(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                  ),
                )
                .where(
                  (entry) =>
                      entry.type.isNotEmpty &&
                      entry.label.isNotEmpty &&
                      entry.url.isNotEmpty,
                )
                .toList(growable: false)
          : const <AnnouncementAction>[],
    );
  }

  final String id;
  final String title;
  final String content;
  final String contentType;
  final String? author;
  final int createdAt;
  final int? expireAt;
  final AnnouncementBehavior behavior;
  final AnnouncementTargets? targets;
  final String? soundUrl;
  final AnnouncementEmbed? embed;
  final List<AnnouncementAction> actions;

  DateTime get createdAtDateTime => DateTime.fromMillisecondsSinceEpoch(
    createdAt * 1000,
  );

  DateTime? get expireAtDateTime => expireAt == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(expireAt! * 1000);
}

class AnnouncementLocalState {
  const AnnouncementLocalState({
    this.viewedRedDotIds = const <String>{},
    this.shownPopupIds = const <String>{},
    this.dismissedPopupIds = const <String>{},
  });

  factory AnnouncementLocalState.empty() {
    return const AnnouncementLocalState();
  }

  factory AnnouncementLocalState.fromJson(Map<String, dynamic> json) {
    return AnnouncementLocalState(
      viewedRedDotIds: _readIdSet(json['viewed_red_dot_ids']),
      shownPopupIds: _readIdSet(json['shown_popup_ids']),
      dismissedPopupIds: _readIdSet(json['dismissed_popup_ids']),
    );
  }

  final Set<String> viewedRedDotIds;
  final Set<String> shownPopupIds;
  final Set<String> dismissedPopupIds;

  Map<String, dynamic> toJson() {
    return {
      'viewed_red_dot_ids': _sortedList(viewedRedDotIds),
      'shown_popup_ids': _sortedList(shownPopupIds),
      'dismissed_popup_ids': _sortedList(dismissedPopupIds),
    };
  }

  AnnouncementLocalState copyWith({
    Set<String>? viewedRedDotIds,
    Set<String>? shownPopupIds,
    Set<String>? dismissedPopupIds,
  }) {
    return AnnouncementLocalState(
      viewedRedDotIds: viewedRedDotIds ?? this.viewedRedDotIds,
      shownPopupIds: shownPopupIds ?? this.shownPopupIds,
      dismissedPopupIds: dismissedPopupIds ?? this.dismissedPopupIds,
    );
  }
}

AnnouncementRepeatBehavior _behaviorFromString(Object? value) {
  return switch ('${value ?? 'once'}'.trim().toLowerCase()) {
    'none' => AnnouncementRepeatBehavior.none,
    'forever' => AnnouncementRepeatBehavior.forever,
    _ => AnnouncementRepeatBehavior.once,
  };
}

Map<String, dynamic>? _stringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, entry) => MapEntry(key.toString(), entry));
}

String? _normalizedNullableText(Object? value) {
  final normalized = '${value ?? ''}'.trim();
  return normalized.isEmpty ? null : normalized;
}

int _parseUnixSeconds(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse('${value ?? ''}'.trim()) ?? 0;
}

int? _parseNullableUnixSeconds(Object? value) {
  if (value == null) {
    return null;
  }
  return _parseUnixSeconds(value);
}

Set<String> _readIdSet(Object? value) {
  if (value is! List) {
    return const <String>{};
  }
  return HashSet<String>.from(
    value.map((entry) => '$entry'.trim()).where((entry) => entry.isNotEmpty),
  );
}

List<String> _sortedList(Set<String> ids) {
  final values = ids.toList(growable: false);
  values.sort();
  return values;
}