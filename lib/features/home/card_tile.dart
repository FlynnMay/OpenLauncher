import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:openlauncher/core/cards/cards.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/features/home/picture.dart';
import 'package:openlauncher/features/home/styled_box.dart';

/// A focusable picture with a label: the look shared by cards and folders.
class ArtTile extends StatelessWidget {
  const ArtTile({
    super.key,
    required this.label,
    required this.art,
    required this.onSelect,
    this.onMenu,
    this.onFocus,
    this.bare = false,
    this.autofocus = false,
    this.style = TileLook.card,
    this.showLabel = true,
    this.boxStyle = BoxStyle.none,
  });

  final String label;
  final Widget art;

  /// The fill and outline the user gave it, if any.
  final BoxStyle boxStyle;

  /// False for a card whose name the user chose to hide. A card keeps the room for it either
  /// way, so hiding a name never changes the size of the picture.
  final bool showLabel;

  /// True for line art, which sits straight on the wallpaper with only a
  /// faint wash to show focus.
  final bool bare;
  final VoidCallback onSelect;
  final void Function(bool held)? onMenu;
  final void Function(bool focused)? onFocus;
  final bool autofocus;
  final TileLook style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusTile(
      autofocus: autofocus,
      onSelect: onSelect,
      onMenu: onMenu,
      onFocus: onFocus,
      focusedScale: style == TileLook.card ? 1.08 : 1.04,
      builder: (context, focused) {
        final fill = styleFill(boxStyle);
        final outline = boxStyle.border;
        final picture = AnimatedContainer(
          duration: FocusTile.duration,
          clipBehavior: Clip.antiAlias,
          // The border is drawn over the artwork so the card does not
          // change size when focused.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: focused
                  ? Colors.white
                  : outline == null
                  ? Colors.transparent
                  : Color(outline),
              width: 2,
            ),
          ),
          decoration: BoxDecoration(
            gradient: fill.gradient,
            color: fill.gradient != null
                ? null
                : fill.color ??
                      (!bare
                          ? theme.colorScheme.surfaceContainerHigh
                          : focused
                          ? Colors.white.withValues(alpha: 0.12)
                          : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: art,
        );
        final text = Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: style == TileLook.card ? TextAlign.center : null,
          style: theme.textTheme.labelMedium?.copyWith(
            color: focused ? Colors.white : Colors.white60,
          ),
        );
        return switch (style) {
          TileLook.card => Column(
            crossAxisAlignment: .stretch,
            children: [
              Expanded(child: picture),
              const SizedBox(height: 6),
              Visibility.maintain(visible: showLabel, child: text),
            ],
          ),
          TileLook.row => Row(
            spacing: 12,
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: picture),
              if (showLabel) Expanded(child: text),
            ],
          ),
        };
      },
    );
  }
}

/// The picture of a card: its artwork, line art, or failing both its name.
class CardArt extends StatelessWidget {
  const CardArt({super.key, required this.card, this.padding = 14});

  final LauncherCard card;

  /// Space left around a square icon.
  final double padding;

  /// Whether [card] is drawn as line art with no card behind it.
  static bool isBare(LauncherCard card) =>
      card.iconPath == null && card.svg != null;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          card.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
    );
    final path = card.iconPath;
    if (path == null) {
      return switch (card.svg) {
        null => fallback,
        final svg => SvgPicture.string(svg, fit: BoxFit.contain),
      };
    }
    final image = Image(
      image: pictureAt(path),
      fit: card.wideIcon ? BoxFit.cover : BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
    return card.wideIcon
        ? image
        : Padding(padding: EdgeInsets.all(padding), child: image);
  }
}

/// The face of a card that opens a popup: the user's picture, else the first
/// few cards inside, else a folder drawn in outline.
class FolderArt extends StatelessWidget {
  const FolderArt({super.key, required this.entry});

  final PanelEntry entry;

  static bool isBare(PanelEntry entry) =>
      entry.icon == null && entry.preview.isEmpty;

  static const _outline =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90" '
      'fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" '
      'stroke-linejoin="round">'
      '<path d="M46 30a5 5 0 0 1 5-5h18l8 9h32a5 5 0 0 1 5 5v26a5 5 0 0 1-5 '
      '5H51a5 5 0 0 1-5-5z"/></svg>';

  @override
  Widget build(BuildContext context) {
    if (entry.icon case final icon?) {
      return Image(
        image: pictureAt(icon),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => SvgPicture.string(_outline),
      );
    }
    if (entry.preview.isEmpty) return SvgPicture.string(_outline);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        spacing: 4,
        children: [
          for (var row = 0; row < 2; row++)
            Expanded(
              child: Row(
                spacing: 4,
                children: [
                  for (var i = row * 2; i < row * 2 + 2; i++)
                    Expanded(
                      child: i < entry.preview.length
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: CardArt(
                                card: entry.preview[i],
                                padding: 2,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
