import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The folders of `lib/core`, lowest first. A folder builds only on folders
/// below it, so core has no import cycles and each area can be read alone.
const coreLayers = [
  'access',
  'media',
  'components',
  'values',
  'packs',
  'config',
  'prefabs',
  'sources',
  'entities',
  'variables',
  'layout',
  'overlays',
  'screens',
  'wallpaper',
  'updates',
  'commands',
  'services',
  'operations',
  'actions',
];

/// Imports that still point up, as `from -> to` below `lib/core`. Fix one,
/// then take it off; nothing new goes on.
const knownUpwardImports = {
  'sources/source_endpoints.dart -> entities/entities_provider.dart',
  'sources/source_endpoints.dart -> overlays/overlays.dart',
  'sources/source_endpoints.dart -> updates/updates.dart',
};

const _corePath = 'lib/core/';
final _coreImport = RegExp(
  r"^(?:import|export) 'package:openlauncher/core/([^']+)'",
  multiLine: true,
);
final _outsideCoreImport = RegExp(
  r"^(?:import|export) 'package:openlauncher/(features|editor|server)/",
  multiLine: true,
);

void main() {
  final coreFiles = _dartFilesIn(_corePath);

  test('every core folder has a place in the layers', () {
    final unplaced = coreFiles.map(_folderOf).toSet().difference(
      coreLayers.toSet(),
    );
    expect(unplaced, isEmpty, reason: 'Add new folders to coreLayers.');
  });

  test('core imports only folders below it, apart from the known ones', () {
    final upward = coreFiles.expand(_upwardImportsOf).toSet();
    expect(upward.difference(knownUpwardImports), isEmpty);
  });

  test('a fixed upward import is taken off the known list', () {
    final upward = coreFiles.expand(_upwardImportsOf).toSet();
    expect(knownUpwardImports.difference(upward), isEmpty);
  });

  test('core never imports the screens, the editor or the server', () {
    final reachingOut = coreFiles.where(
      (file) => _outsideCoreImport.hasMatch(file.readAsStringSync()),
    );
    expect(reachingOut.map((file) => file.path), isEmpty);
  });
}

List<File> _dartFilesIn(String path) => [
  for (final entry in Directory(path).listSync(recursive: true))
    if (entry is File && entry.path.endsWith('.dart')) entry,
];

String _pathInCore(File file) => file.path.substring(_corePath.length);

String _folderOf(File file) => _pathInCore(file).split('/').first;

int _layerOf(String importedPath) =>
    coreLayers.indexOf(importedPath.split('/').first);

Iterable<String> _upwardImportsOf(File file) {
  final ownLayer = coreLayers.indexOf(_folderOf(file));
  return _coreImport
      .allMatches(file.readAsStringSync())
      .map((match) => match.group(1)!)
      .where((imported) => _layerOf(imported) > ownLayer)
      .map((imported) => '${_pathInCore(file)} -> $imported');
}
