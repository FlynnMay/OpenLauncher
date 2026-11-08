import 'package:openlauncher/core/endpoints/source_endpoint.dart';
import 'package:openlauncher/core/values/value_providers.dart';
import 'package:openlauncher_domain/values/date_format.dart';

/// The TV's time, read again each second.
final Map<String, SourceEndpoint> clockEndpoints = {
  'launcher://clock': (ref, watch) {
    final now = ref.watch(tickProvider(true));
    final time = formatDateTime(now, 'HH:mm');
    return {
      'text': time,
      'time': time,
      'date': formatDateTime(now, 'EEEE d MMMM'),
      'hour': now.hour,
      'minute': now.minute,
      'second': now.second,
      'hour12': now.hour % 12 == 0 ? 12 : now.hour % 12,
      'ampm': now.hour < 12 ? 'am' : 'pm',
      'weekday': dayNames[now.weekday - 1],
      'day': now.day,
      'month': now.month,
      'monthName': monthNames[now.month - 1],
      'year': now.year,
      'epoch': now.millisecondsSinceEpoch,
    };
  },
};
