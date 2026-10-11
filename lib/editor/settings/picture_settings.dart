import 'package:flutter/material.dart';
import 'package:openlauncher/editor/controls/controls.dart';

/// A single picture with upload and reset; used for entity and folder
/// pictures.
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

  final Widget? picture;

  final Future<void> Function(PickedFile file) onPicked;

  /// Resets it; null when already default.
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
