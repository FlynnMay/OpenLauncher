import 'package:openlauncher/core/components/device_endpoints.dart';
import 'package:openlauncher/core/config/place_endpoints.dart';
import 'package:openlauncher/core/endpoints/source_endpoint.dart';
import 'package:openlauncher/core/overlays/overlay_endpoints.dart';
import 'package:openlauncher/core/updates/update_endpoints.dart';
import 'package:openlauncher/core/values/clock_endpoint.dart';

/// Every `os://` and `launcher://` address the launcher answers as a source.
/// A feature declares its own in its folder, below this one, and adds its
/// map here.
final Map<String, SourceEndpoint> sourceEndpointRegistry = {
  ...deviceEndpoints,
  ...clockEndpoints,
  ...placeEndpoints,
  ...updateEndpoints,
  ...overlayEndpoints,
};
