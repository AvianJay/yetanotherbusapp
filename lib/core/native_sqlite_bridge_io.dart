import 'package:sqlite3/sqlite3.dart' as sqlite3_pkg;

class NativeSqliteDatabase {
  NativeSqliteDatabase(this._database);

  final sqlite3_pkg.Database _database;

  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> parameters = const <Object?>[],
  ]) {
    final result = _database.select(sql, parameters);
    return result
        .map(
          (row) => <String, Object?>{
            for (final key in row.keys) key: row[key] as Object?,
          },
        )
        .toList();
  }

  void close() {
    _database.close();
  }
}

NativeSqliteDatabase openReadOnlySqliteDatabase(String path) {
  return NativeSqliteDatabase(
    sqlite3_pkg.sqlite3.open(path, mode: sqlite3_pkg.OpenMode.readOnly),
  );
}

