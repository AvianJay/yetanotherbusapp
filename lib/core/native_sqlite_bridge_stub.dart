class NativeSqliteDatabase {
  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) {
    throw UnsupportedError('Native sqlite is unavailable on this platform.');
  }

  void close() {}
}

NativeSqliteDatabase openReadOnlySqliteDatabase(String path) {
  throw UnsupportedError('Native sqlite is unavailable on this platform.');
}

