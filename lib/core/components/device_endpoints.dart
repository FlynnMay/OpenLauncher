import 'package:openlauncher/core/components/device_sources.dart';
import 'package:openlauncher/core/endpoints/source_endpoint.dart';

/// What the TV itself answers: its apps, its inputs and what is playing.
final Map<String, SourceEndpoint> deviceEndpoints = {
  'os://apps': (ref, watch) async => [
    for (final app in await readOrWatch(
      ref,
      installedAppsProvider.future,
      watch,
    ))
      {
        'package': app.packageName,
        'label': app.label,
        'icon': app.iconPath,
        'banner': app.isBanner,
      },
  ],
  'os://inputs': (ref, watch) async => [
    for (final input in await readOrWatch(ref, tvInputsProvider.future, watch))
      {'id': input.id, 'label': input.label, 'kind': input.kind.name},
  ],
  'os://media': (ref, watch) {
    final playing = ref.watch(nowPlayingProvider).value;
    if (playing == null) {
      return const {'text': null, 'playing': false};
    }
    return {
      'text': playing.title ?? playing.appLabel,
      'title': playing.title,
      'artist': playing.artist,
      'app': playing.appLabel,
      'playing': playing.playing,
      'art': playing.artPath,
    };
  },
};
