import 'package:flutter_riverpod/misc.dart';
import 'package:openlauncher/core/components/device_endpoints.dart';
import 'package:openlauncher/core/config/place_endpoints.dart';
import 'package:openlauncher/core/endpoints/source_endpoint.dart';
import 'package:openlauncher/core/overlays/overlay_endpoints.dart';
import 'package:openlauncher/core/updates/update_endpoints.dart';
import 'package:openlauncher/core/values/clock_endpoint.dart';

/// Every address the launcher answers as a source. A feature with a new one
/// declares it in its own folder and adds its map here.
final Map<String, SourceEndpoint> launcherSourceEndpoints = {
  ...deviceEndpoints,
  ...clockEndpoints,
  ...placeEndpoints,
  ...updateEndpoints,
  ...overlayEndpoints,
};

/// Fills in [sourceEndpointsProvider]; every ProviderScope and test container
/// that reads sources needs it.
final List<Override> sourceEndpointOverrides = [
  sourceEndpointsProvider.overrideWithValue(launcherSourceEndpoints),
];
