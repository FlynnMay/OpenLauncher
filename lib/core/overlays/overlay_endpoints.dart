import 'package:openlauncher/core/endpoints/source_endpoint.dart';
import 'package:openlauncher/core/overlays/overlays.dart';

/// What is open over the screen.
final Map<String, SourceEndpoint> overlayEndpoints = {
  'launcher://overlays': (ref, watch) => {
    'count': ref.watch(overlaysProvider).length,
  },
};
