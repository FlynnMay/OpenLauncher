import 'package:openlauncher/core/endpoints/source_endpoint.dart';
import 'package:openlauncher/core/updates/update_controller.dart';

/// Whether a newer launcher is out, and how getting it is going.
final Map<String, SourceEndpoint> updateEndpoints = {
  'launcher://updates': (ref, watch) {
    final update = ref.watch(updateStateProvider);
    return {
      'text': update.current,
      'current': update.current,
      'latest': update.latest,
      'available': update.available,
      'status': update.status.name,
      'progress': update.progress,
      'notes': update.notes,
      'error': update.error,
    };
  },
};
