import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/services/http_service.dart';
import 'package:openlauncher/core/sources/source_request.dart';

/// The sources of packs, as something to be told to do.
class SourceService {
  SourceService(this._ref);

  final Ref _ref;

  /// Fetches source [name] of the pack the entity [entityId] belongs to again,
  /// now. Nothing happens for an entity of no pack or a source it lacks.
  Future<String?> fetchAgain(String? entityId, String name) async {
    final pack = HttpService.packOf(entityId);
    if (pack != null) await fetchSourceAgain(_ref, pack, name);
    return null;
  }
}

final sourceServiceProvider = Provider<SourceService>(SourceService.new);
