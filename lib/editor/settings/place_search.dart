import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/components/weather.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/tv/tv.dart';

/// Finds a place by name and offers what was found.
class PlaceSearch extends ConsumerStatefulWidget {
  const PlaceSearch({super.key, required this.said, required this.onChosen});

  /// The current place, or that there is none.
  final String said;
  final void Function(Place place) onChosen;

  @override
  ConsumerState<PlaceSearch> createState() => _State();
}

class _State extends ConsumerState<PlaceSearch> with Busy<PlaceSearch> {
  List<Place>? _found;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(widget.said),
      ),
      TextField(
        decoration: InputDecoration(
          labelText: 'Location',
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search),
        ),
        onSubmitted: (name) {
          if (name.trim().isEmpty) return;
          whileBusy(() async {
            final found = await ref.read(tvApiProvider).findPlaces(name.trim());
            if (mounted) setState(() => _found = found);
          });
        },
      ),
      if (_found case final found?)
        if (found.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('No results'),
          )
        else
          for (final place in found)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.place_outlined),
              title: Text(place.name),
              onTap: () {
                setState(() => _found = null);
                widget.onChosen(place);
              },
            ),
    ],
  );
}
