import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openlauncher/core/values/date_format.dart';

/// The time as the clock widget writes it.
String formatTime(DateTime time, {required bool hour24, bool seconds = false}) {
  String two(int n) => n.toString().padLeft(2, '0');
  final tail = '${two(time.minute)}${seconds ? ':${two(time.second)}' : ''}';
  if (hour24) return '${two(time.hour)}:$tail';
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:$tail ${time.hour < 12 ? 'am' : 'pm'}';
}

String formatDate(DateTime time) => formatDateTime(time, 'EEEE d MMMM');

/// The time, and optionally the date, in plain white text sized to its box.
///
/// Options: `hour24` (default true), `date` (default true), `seconds`.
class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key, required this.options});

  final Map<String, Object?> options;

  @override
  State<ClockWidget> createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final options = widget.options;
    return FittedBox(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatTime(
              now,
              hour24: options['hour24'] != false,
              seconds: options['seconds'] == true,
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 44,
              fontWeight: FontWeight.w300,
              height: 1.1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          if (options['date'] != false)
            Text(
              formatDate(now),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
        ],
      ),
    );
  }
}
