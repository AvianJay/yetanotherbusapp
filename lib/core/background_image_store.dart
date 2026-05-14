import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BackgroundImageStore {
  BackgroundImageStore({
    Future<Directory> Function()? supportDirectoryProvider,
    Future<Directory> Function()? tempDirectoryProvider,
  }) : _supportDirectoryProvider =
           supportDirectoryProvider ?? getApplicationSupportDirectory,
       _tempDirectoryProvider =
           tempDirectoryProvider ?? getTemporaryDirectory;

  static const _directoryName = 'background_images';

  final Future<Directory> Function() _supportDirectoryProvider;
  final Future<Directory> Function() _tempDirectoryProvider;

  Future<String> importImage(String sourcePath) async {
    final trimmedPath = sourcePath.trim();
    if (kIsWeb || trimmedPath.isEmpty || _isNonFilePath(trimmedPath)) {
      return trimmedPath;
    }

    final managedDirectory = await _managedDirectory();
    final managedDirectoryPath = _normalizeDirectoryPath(managedDirectory.path);
    final normalizedSourcePath = _normalizeFilePath(trimmedPath);
    if (p.isWithin(managedDirectoryPath, normalizedSourcePath)) {
      return normalizedSourcePath;
    }

    final sourceFile = File(normalizedSourcePath);
    if (!await sourceFile.exists()) {
      throw FileSystemException(
        'Background image file does not exist.',
        normalizedSourcePath,
      );
    }

    final storedPath = p.join(
      managedDirectory.path,
      'background_${DateTime.now().microsecondsSinceEpoch}_'
      '${p.basename(normalizedSourcePath)}',
    );
    await sourceFile.copy(storedPath);
    await _deleteSourceIfTemporary(normalizedSourcePath);
    return storedPath;
  }

  Future<Map<String, String>> normalizeSettingsPaths(
    Map<String, String> paths,
  ) async {
    if (kIsWeb) {
      return Map<String, String>.fromEntries(
        paths.entries.where((entry) => entry.value.trim().isNotEmpty),
      );
    }

    final normalized = <String, String>{};
    final importedBySource = <String, String>{};
    final managedDirectory = await _managedDirectory(create: false);
    final managedDirectoryPath = _normalizeDirectoryPath(managedDirectory.path);

    for (final entry in paths.entries) {
      final trimmedPath = entry.value.trim();
      if (trimmedPath.isEmpty) {
        continue;
      }
      if (_isNonFilePath(trimmedPath)) {
        normalized[entry.key] = trimmedPath;
        continue;
      }

      final normalizedSourcePath = _normalizeFilePath(trimmedPath);
      final reusedImportedPath = importedBySource[normalizedSourcePath];
      if (reusedImportedPath != null) {
        normalized[entry.key] = reusedImportedPath;
        continue;
      }
      if (p.isWithin(managedDirectoryPath, normalizedSourcePath)) {
        if (await File(normalizedSourcePath).exists()) {
          normalized[entry.key] = normalizedSourcePath;
        }
        continue;
      }

      final sourceFile = File(normalizedSourcePath);
      if (!await sourceFile.exists()) {
        continue;
      }

      final importedPath = await importImage(normalizedSourcePath);
      importedBySource[normalizedSourcePath] = importedPath;
      normalized[entry.key] = importedPath;
    }

    await cleanupUnusedImages(normalized.values);
    return normalized;
  }

  Future<void> cleanupUnusedImages(Iterable<String> referencedPaths) async {
    if (kIsWeb) {
      return;
    }

    final managedDirectory = await _managedDirectory(create: false);
    if (!await managedDirectory.exists()) {
      return;
    }

    final referenced = referencedPaths
        .where((path) => !_isNonFilePath(path))
        .map(_normalizeFilePath)
        .toSet();

    await for (final entity in managedDirectory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final entityPath = _normalizeFilePath(entity.path);
      if (referenced.contains(entityPath)) {
        continue;
      }
      try {
        await entity.delete();
      } catch (_) {
        // Ignore cleanup failures so background updates still succeed.
      }
    }
  }

  Future<Directory> _managedDirectory({bool create = true}) async {
    final supportDirectory = await _supportDirectoryProvider();
    final directory = Directory(
      p.join(supportDirectory.path, _directoryName),
    );
    if (create) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _deleteSourceIfTemporary(String sourcePath) async {
    final tempDirectory = await _tempDirectoryProvider();
    final normalizedTempPath = _normalizeDirectoryPath(tempDirectory.path);
    if (!p.isWithin(normalizedTempPath, sourcePath)) {
      return;
    }

    final sourceFile = File(sourcePath);
    try {
      if (await sourceFile.exists()) {
        await sourceFile.delete();
      }
    } catch (_) {
      return;
    }

    await _pruneEmptyParentDirectories(
      start: sourceFile.parent,
      rootPath: normalizedTempPath,
    );
  }

  Future<void> _pruneEmptyParentDirectories({
    required Directory start,
    required String rootPath,
  }) async {
    var current = Directory(_normalizeDirectoryPath(start.path));
    while (true) {
      final currentPath = _normalizeDirectoryPath(current.path);
      if (currentPath == rootPath || !p.isWithin(rootPath, currentPath)) {
        return;
      }

      try {
        if (!await current.exists()) {
          current = current.parent;
          continue;
        }
        if (!await current.list(followLinks: false).isEmpty) {
          return;
        }
        await current.delete();
      } catch (_) {
        return;
      }

      current = current.parent;
    }
  }

  bool _isNonFilePath(String path) {
    return path.startsWith('data:') ||
        path.startsWith('http://') ||
        path.startsWith('https://');
  }

  String _normalizeDirectoryPath(String path) {
    return p.normalize(Directory(path).absolute.path);
  }

  String _normalizeFilePath(String path) {
    return p.normalize(File(path).absolute.path);
  }
}
