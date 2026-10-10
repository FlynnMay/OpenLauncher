import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls.dart';
import 'package:openlauncher/editor/file_pick.dart';
import 'package:openlauncher/editor/image_carousel.dart';

/// The one picture something has: a carousel of a single image, with the
/// choosing of a file and the waiting for it done. Used for a card's
/// picture and a folder's.
class PictureSettings extends StatefulWidget {
  const PictureSettings({
    super.key,
    required this.picture,
    required this.onPicked,
    this.onCleared,
    this.empty = 'No picture',
    this.clearLabel = 'Remove',
    this.aspectRatio = 16 / 9,
  });

  /// What it looks like now; null for nothing.
  final Widget? picture;

  /// Called with the file the user chose in its place.
  final Future<void> Function(PickedFile file) onPicked;

  /// Returns it to what it was by itself; null when it already is.
  final Future<void> Function()? onCleared;
  final String empty, clearLabel;
  final double aspectRatio;

  @override
  State<PictureSettings> createState() => _PictureSettingsState();
}

class _PictureSettingsState extends State<PictureSettings>
    with Busy<PictureSettings> {
  @override
  Widget build(BuildContext context) => ImageCarousel(
    images: [
      if (widget.picture case final picture?)
        CarouselImage(id: 'picture', child: picture),
    ],
    aspectRatio: widget.aspectRatio,
    empty: widget.empty,
    addLabel: 'Choose a picture',
    replaceLabel: 'Choose a picture',
    removeLabel: widget.clearLabel,
    busy: busy,
    onAdd: () => whileBusy(() async {
      final file = await pickFile(accept: 'image/*');
      if (file != null) await widget.onPicked(file);
    }),
    onRemove: switch (widget.onCleared) {
      null => null,
      final clear => (_) => whileBusy(clear),
    },
  );
}
