import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';

/// What the user gave each pack's settings, by pack id; made again only when
/// they change.
final packSettingsOfProvider =
    Provider.autoDispose<Map<String, Map<String, Object?>>>((ref) {
      final saved = ref.watch(
        configProvider.select(
          (config) => jsonEncode(config.value?.packSettings),
        ),
      );
      final decoded = jsonDecode(saved);
      return {
        if (decoded is Map)
          for (final MapEntry(:key, :value) in decoded.entries)
            if (value is Map) '$key': {...value.cast<String, Object?>()},
      };
    });
