import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> configureDatabaseFactory() async {
  if (kIsWeb) {
    return;
  }

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final supportDirectory = await getApplicationSupportDirectory();
    await supportDirectory.create(recursive: true);
    await databaseFactory.setDatabasesPath(supportDirectory.path);
  }
}
