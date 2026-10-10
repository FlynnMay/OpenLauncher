import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/cards/launcher_card.dart';

/// A D-pad focusable card: artwork with the label underneath.
class CardTile extends StatefulWidget {
  const CardTile({
    super.key,
    required this.card,
    required this.onSelect,
    this.autofocus = false,
  });

  final LauncherCard card;
  final VoidCallback onSelect;
  final bool autofocus;

  @override
  State<CardTile> createState() => _CardTileState();
}

class _CardTileState extends State<CardTile> {
  static const _duration = Duration(milliseconds: 150);

  bool _focused = false;

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (focused) {
      Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: _duration,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bare = widget.card.iconPath == null && widget.card.svg != null;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      mouseCursor: SystemMouseCursors.click,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => widget.onSelect(),
        ),
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: _focused ? 1.08 : 1,
          duration: _duration,
          curve: Curves.easeOut,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: _duration,
                  clipBehavior: Clip.antiAlias,
                  // The border is drawn over the artwork so the card does
                  // not change size when focused.
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _focused ? Colors.white : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  decoration: BoxDecoration(
                    // Line-art cards sit straight on the wallpaper, with
                    // only a faint wash to show focus.
                    color: !bare
                        ? theme.colorScheme.surfaceContainerHigh
                        : _focused
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: _Artwork(card: widget.card),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.card.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: _focused ? Colors.white : Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.card});

  final LauncherCard card;

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
    final image = Image.file(
      File(path),
      fit: card.wideIcon ? BoxFit.cover : BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
    );
    return card.wideIcon
        ? image
        : Padding(padding: const EdgeInsets.all(14), child: image);
  }
}
