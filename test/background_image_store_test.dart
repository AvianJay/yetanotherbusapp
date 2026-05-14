import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:taiwanbus_flutter/core/background_image_store.dart';

void main() {
  Future<Directory> createTempDir(String prefix) {
    return Directory.systemTemp.createTemp(prefix);
  }

  test('importImage stores the file outside cache and deletes temp copies', () async {
    final supportRoot = await createTempDir('background-store-support-');
    final tempRoot = await createTempDir('background-store-temp-');
    addTearDown(() async {
      if (await supportRoot.exists()) {
        await supportRoot.delete(recursive: true);
      }
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final pickerDirectory = Directory(p.join(tempRoot.path, 'image_picker_1'));
    await pickerDirectory.create(recursive: true);
    final sourceFile = File(p.join(pickerDirectory.path, 'picked.gif'));
    await sourceFile.writeAsBytes([0x47, 0x49, 0x46]);

    final store = BackgroundImageStore(
      supportDirectoryProvider: () async => supportRoot,
      tempDirectoryProvider: () async => tempRoot,
    );

    final storedPath = await store.importImage(sourceFile.path);
    final storedFile = File(storedPath);

    expect(p.isWithin(supportRoot.path, storedPath), isTrue);
    expect(await storedFile.exists(), isTrue);
    expect(await storedFile.readAsBytes(), [0x47, 0x49, 0x46]);
    expect(await sourceFile.exists(), isFalse);
    expect(await pickerDirectory.exists(), isFalse);
  });

  test('normalizeSettingsPaths reuses one stored copy and drops missing files', () async {
    final supportRoot = await createTempDir('background-store-support-');
    final tempRoot = await createTempDir('background-store-temp-');
    addTearDown(() async {
      if (await supportRoot.exists()) {
        await supportRoot.delete(recursive: true);
      }
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final sourceDirectory = Directory(p.join(tempRoot.path, 'image_picker_2'));
    await sourceDirectory.create(recursive: true);
    final sourceFile = File(p.join(sourceDirectory.path, 'picked.png'));
    await sourceFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47]);

    final store = BackgroundImageStore(
      supportDirectoryProvider: () async => supportRoot,
      tempDirectoryProvider: () async => tempRoot,
    );

    final normalized = await store.normalizeSettingsPaths({
      'bus': sourceFile.path,
      'route_detail': sourceFile.path,
      'search': p.join(tempRoot.path, 'missing.png'),
    });

    expect(normalized.keys, {'bus', 'route_detail'});
    expect(normalized['bus'], normalized['route_detail']);

    final managedDirectory = Directory(
      p.join(supportRoot.path, 'background_images'),
    );
    final files = await managedDirectory
        .list(followLinks: false)
        .where((entity) => entity is File)
        .toList();
    expect(files.length, 1);
  });
}
