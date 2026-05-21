import 'dart:convert';

enum AccountSyncNamespace {
  favorites,
  preferences;

  String get apiValue => name;

  String get label => switch (this) {
    AccountSyncNamespace.favorites => '最愛站牌與分類',
    AccountSyncNamespace.preferences => '偏好設定',
  };

  String get shortLabel => switch (this) {
    AccountSyncNamespace.favorites => '站牌',
    AccountSyncNamespace.preferences => '設定',
  };

  int get schemaVersion => 1;
}

enum AccountSyncConflictPolicy {
  abort('abort'),
  clientWins('client_wins'),
  serverWins('server_wins'),
  merge('merge');

  const AccountSyncConflictPolicy(this.apiValue);

  final String apiValue;
}

enum AccountSyncHealth {
  unknown,
  noBackup,
  inSync,
  localChanges,
  cloudChanges,
  conflict,
}

class AccountSyncDocument {
  const AccountSyncDocument({
    required this.namespace,
    required this.hasData,
    required this.schemaVersion,
    required this.revision,
    required this.etag,
    required this.updatedAt,
    required this.lastSyncedAt,
    required this.lastClientModifiedAt,
    required this.payloadSizeBytes,
    required this.payload,
  });

  final AccountSyncNamespace namespace;
  final bool hasData;
  final int? schemaVersion;
  final int revision;
  final String? etag;
  final DateTime? updatedAt;
  final DateTime? lastSyncedAt;
  final DateTime? lastClientModifiedAt;
  final int payloadSizeBytes;
  final Map<String, dynamic>? payload;

  factory AccountSyncDocument.fromJson(
    AccountSyncNamespace namespace,
    Map<String, dynamic> json,
  ) {
    final hasData = json['has_data'] == true;
    final payloadValue = json['payload'];
    return AccountSyncDocument(
      namespace: namespace,
      hasData: hasData,
      schemaVersion: _jsonIntOrNull(json['schema_version']),
      revision: _jsonIntOrNull(json['revision']) ?? 0,
      etag: _jsonStringOrNull(json['etag']),
      updatedAt: _parseDateTime(json['updated_at']),
      lastSyncedAt: _parseDateTime(json['last_synced_at']),
      lastClientModifiedAt: _parseDateTime(json['last_client_modified_at']),
      payloadSizeBytes: _jsonIntOrNull(json['payload_size_bytes']) ?? 0,
      payload: payloadValue is Map
          ? payloadValue.map(
              (key, value) => MapEntry(key.toString(), _deepCloneJson(value)),
            )
          : null,
    );
  }
}

class AccountSyncSummary {
  const AccountSyncSummary({required this.serverTime, required this.documents});

  final DateTime? serverTime;
  final Map<AccountSyncNamespace, AccountSyncDocument> documents;

  factory AccountSyncSummary.fromJson(Map<String, dynamic> json) {
    final rawDocuments = json['documents'];
    final documents = <AccountSyncNamespace, AccountSyncDocument>{};
    if (rawDocuments is Map) {
      for (final namespace in AccountSyncNamespace.values) {
        final entry = rawDocuments[namespace.apiValue];
        if (entry is Map) {
          documents[namespace] = AccountSyncDocument.fromJson(
            namespace,
            entry.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }
    return AccountSyncSummary(
      serverTime: _parseDateTime(json['server_time']),
      documents: documents,
    );
  }

  AccountSyncSummary copyWithDocument(AccountSyncDocument document) {
    return AccountSyncSummary(
      serverTime: serverTime,
      documents: {...documents, document.namespace: document},
    );
  }
}

class AccountSyncMergePreview {
  const AccountSyncMergePreview({
    required this.status,
    required this.message,
    required this.payload,
  });

  final String status;
  final String? message;
  final Map<String, dynamic>? payload;

  bool get canMerge => status == 'possible';

  factory AccountSyncMergePreview.fromJson(Map<String, dynamic> json) {
    final payloadValue = json['payload'];
    return AccountSyncMergePreview(
      status: '${json['status'] ?? ''}',
      message: _jsonStringOrNull(json['message']),
      payload: payloadValue is Map
          ? payloadValue.map(
              (key, value) => MapEntry(key.toString(), _deepCloneJson(value)),
            )
          : null,
    );
  }
}

class AccountSyncConflictException implements Exception {
  const AccountSyncConflictException({
    required this.namespace,
    required this.message,
    required this.serverDocument,
    required this.mergePreview,
  });

  final AccountSyncNamespace namespace;
  final String message;
  final AccountSyncDocument? serverDocument;
  final AccountSyncMergePreview? mergePreview;

  bool get canMerge => mergePreview?.canMerge == true;

  factory AccountSyncConflictException.fromJson(
    AccountSyncNamespace namespace,
    Map<String, dynamic> json,
  ) {
    final rawServerDocument = json['server_document'];
    final rawMergePreview = json['merge_preview'];
    return AccountSyncConflictException(
      namespace: namespace,
      message: _jsonStringOrNull(json['message']) ?? '同步發生衝突。',
      serverDocument: rawServerDocument is Map
          ? AccountSyncDocument.fromJson(
              namespace,
              rawServerDocument.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
      mergePreview: rawMergePreview is Map
          ? AccountSyncMergePreview.fromJson(
              rawMergePreview.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
    );
  }

  @override
  String toString() => message;
}

class AccountSyncWriteResult {
  const AccountSyncWriteResult({
    required this.status,
    required this.conflictPolicy,
    required this.document,
  });

  final String status;
  final AccountSyncConflictPolicy conflictPolicy;
  final AccountSyncDocument? document;

  bool get isCreated => status == 'created';
}

class AccountSyncNamespaceLocalState {
  const AccountSyncNamespaceLocalState({
    this.lastSuccessfulSyncAtMs,
    this.lastSyncedLocalModifiedAtMs,
    this.lastSyncedServerRevision,
    this.lastSyncedServerEtag,
    this.lastSyncedServerUpdatedAt,
    this.preservedPayload,
  });

  final int? lastSuccessfulSyncAtMs;
  final int? lastSyncedLocalModifiedAtMs;
  final int? lastSyncedServerRevision;
  final String? lastSyncedServerEtag;
  final String? lastSyncedServerUpdatedAt;
  final Map<String, dynamic>? preservedPayload;

  DateTime? get lastSuccessfulSyncAt => _dateTimeFromMs(lastSuccessfulSyncAtMs);

  DateTime? get lastSyncedLocalModifiedAt =>
      _dateTimeFromMs(lastSyncedLocalModifiedAtMs);

  DateTime? get lastSyncedServerUpdatedAtDateTime =>
      _parseDateTime(lastSyncedServerUpdatedAt);

  AccountSyncNamespaceLocalState copyWith({
    int? lastSuccessfulSyncAtMs,
    bool clearLastSuccessfulSyncAtMs = false,
    int? lastSyncedLocalModifiedAtMs,
    bool clearLastSyncedLocalModifiedAtMs = false,
    int? lastSyncedServerRevision,
    bool clearLastSyncedServerRevision = false,
    String? lastSyncedServerEtag,
    bool clearLastSyncedServerEtag = false,
    String? lastSyncedServerUpdatedAt,
    bool clearLastSyncedServerUpdatedAt = false,
    Map<String, dynamic>? preservedPayload,
    bool clearPreservedPayload = false,
  }) {
    return AccountSyncNamespaceLocalState(
      lastSuccessfulSyncAtMs: clearLastSuccessfulSyncAtMs
          ? null
          : (lastSuccessfulSyncAtMs ?? this.lastSuccessfulSyncAtMs),
      lastSyncedLocalModifiedAtMs: clearLastSyncedLocalModifiedAtMs
          ? null
          : (lastSyncedLocalModifiedAtMs ?? this.lastSyncedLocalModifiedAtMs),
      lastSyncedServerRevision: clearLastSyncedServerRevision
          ? null
          : (lastSyncedServerRevision ?? this.lastSyncedServerRevision),
      lastSyncedServerEtag: clearLastSyncedServerEtag
          ? null
          : (lastSyncedServerEtag ?? this.lastSyncedServerEtag),
      lastSyncedServerUpdatedAt: clearLastSyncedServerUpdatedAt
          ? null
          : (lastSyncedServerUpdatedAt ?? this.lastSyncedServerUpdatedAt),
      preservedPayload: clearPreservedPayload
          ? null
          : (preservedPayload ?? this.preservedPayload),
    );
  }

  factory AccountSyncNamespaceLocalState.fromJson(Map<String, dynamic> json) {
    final preservedPayload = json['preserved_payload'];
    return AccountSyncNamespaceLocalState(
      lastSuccessfulSyncAtMs: _jsonIntOrNull(
        json['last_successful_sync_at_ms'],
      ),
      lastSyncedLocalModifiedAtMs: _jsonIntOrNull(
        json['last_synced_local_modified_at_ms'],
      ),
      lastSyncedServerRevision: _jsonIntOrNull(
        json['last_synced_server_revision'],
      ),
      lastSyncedServerEtag: _jsonStringOrNull(json['last_synced_server_etag']),
      lastSyncedServerUpdatedAt: _jsonStringOrNull(
        json['last_synced_server_updated_at'],
      ),
      preservedPayload: preservedPayload is Map
          ? preservedPayload.map(
              (key, value) => MapEntry(key.toString(), _deepCloneJson(value)),
            )
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (lastSuccessfulSyncAtMs != null)
        'last_successful_sync_at_ms': lastSuccessfulSyncAtMs,
      if (lastSyncedLocalModifiedAtMs != null)
        'last_synced_local_modified_at_ms': lastSyncedLocalModifiedAtMs,
      if (lastSyncedServerRevision != null)
        'last_synced_server_revision': lastSyncedServerRevision,
      if (lastSyncedServerEtag != null)
        'last_synced_server_etag': lastSyncedServerEtag,
      if (lastSyncedServerUpdatedAt != null)
        'last_synced_server_updated_at': lastSyncedServerUpdatedAt,
      if (preservedPayload != null)
        'preserved_payload': jsonDecode(jsonEncode(preservedPayload)),
    };
  }
}

class AccountSyncLocalState {
  const AccountSyncLocalState({
    required this.favorites,
    required this.preferences,
  });

  final AccountSyncNamespaceLocalState favorites;
  final AccountSyncNamespaceLocalState preferences;

  factory AccountSyncLocalState.empty() {
    return const AccountSyncLocalState(
      favorites: AccountSyncNamespaceLocalState(),
      preferences: AccountSyncNamespaceLocalState(),
    );
  }

  factory AccountSyncLocalState.fromJson(Map<String, dynamic> json) {
    final rawFavorites = json['favorites'];
    final rawPreferences = json['preferences'];
    return AccountSyncLocalState(
      favorites: rawFavorites is Map
          ? AccountSyncNamespaceLocalState.fromJson(
              rawFavorites.map((key, value) => MapEntry(key.toString(), value)),
            )
          : const AccountSyncNamespaceLocalState(),
      preferences: rawPreferences is Map
          ? AccountSyncNamespaceLocalState.fromJson(
              rawPreferences.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            )
          : const AccountSyncNamespaceLocalState(),
    );
  }

  AccountSyncNamespaceLocalState stateFor(AccountSyncNamespace namespace) {
    return switch (namespace) {
      AccountSyncNamespace.favorites => favorites,
      AccountSyncNamespace.preferences => preferences,
    };
  }

  AccountSyncLocalState copyWithNamespace(
    AccountSyncNamespace namespace,
    AccountSyncNamespaceLocalState state,
  ) {
    return switch (namespace) {
      AccountSyncNamespace.favorites => AccountSyncLocalState(
        favorites: state,
        preferences: preferences,
      ),
      AccountSyncNamespace.preferences => AccountSyncLocalState(
        favorites: favorites,
        preferences: state,
      ),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'favorites': favorites.toJson(),
      'preferences': preferences.toJson(),
    };
  }
}

class AccountSyncNamespaceStatus {
  const AccountSyncNamespaceStatus({
    required this.namespace,
    required this.localState,
    required this.serverDocument,
    required this.localModifiedAt,
  });

  final AccountSyncNamespace namespace;
  final AccountSyncNamespaceLocalState localState;
  final AccountSyncDocument? serverDocument;
  final DateTime? localModifiedAt;

  bool get hasCloudData => serverDocument?.hasData == true;

  bool get hasEverSynced => localState.lastSuccessfulSyncAtMs != null;

  bool get localChanges =>
      localModifiedAt != null &&
      (localState.lastSyncedLocalModifiedAtMs == null ||
          localModifiedAt!.millisecondsSinceEpoch >
              localState.lastSyncedLocalModifiedAtMs!);

  bool get cloudChanges =>
      serverDocument != null &&
      serverDocument!.hasData &&
      (localState.lastSyncedServerRevision == null ||
          serverDocument!.revision > localState.lastSyncedServerRevision!);

  AccountSyncHealth get health {
    if (localChanges && cloudChanges) {
      return AccountSyncHealth.conflict;
    }
    if (!hasCloudData) {
      return localChanges
          ? AccountSyncHealth.localChanges
          : AccountSyncHealth.noBackup;
    }
    if (cloudChanges) {
      return AccountSyncHealth.cloudChanges;
    }
    if (localChanges) {
      return AccountSyncHealth.localChanges;
    }
    if (hasEverSynced) {
      return AccountSyncHealth.inSync;
    }
    return AccountSyncHealth.unknown;
  }

  String get healthLabel => switch (health) {
    AccountSyncHealth.unknown => '狀態未知',
    AccountSyncHealth.noBackup => '尚未備份',
    AccountSyncHealth.inSync => '已同步',
    AccountSyncHealth.localChanges => '本機有新變更',
    AccountSyncHealth.cloudChanges => '雲端較新',
    AccountSyncHealth.conflict => '同步衝突',
  };
}

DateTime? _parseDateTime(Object? value) {
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return DateTime.tryParse(text)?.toLocal();
}

DateTime? _dateTimeFromMs(int? value) {
  if (value == null) {
    return null;
  }
  return DateTime.fromMillisecondsSinceEpoch(value);
}

int? _jsonIntOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse('$value');
}

String? _jsonStringOrNull(Object? value) {
  final text = '$value'.trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  return text;
}

Object? _deepCloneJson(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return value;
  }
  if (value is List) {
    return value.map(_deepCloneJson).toList(growable: false);
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), _deepCloneJson(item)),
    );
  }
  return '$value';
}
