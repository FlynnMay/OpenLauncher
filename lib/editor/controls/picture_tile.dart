import 'package:flutter/material.dart';

/// A picture with a name and an optional corner note, as the catalogue and
/// pickers show things.
class PictureTile extends StatelessWidget {
  const PictureTile({
    super.key,
    required this.label,
    required this.picture,
    this.backed = false,
    this.badge,
    this.tooltip,
    this.onTap,
    this.corner,
  });

  final String label;
  final Widget picture;

  /// Whether the picture gets a card background.
  final bool backed;
  final String? badge;
  final String? tooltip;
  final VoidCallback? onTap;

  /// A small control over the picture's top left corner.
  final Widget? corner;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip ?? label,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: backed
                          ? theme.colorScheme.surfaceContainerHigh
                          : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: picture,
                  ),
                  if (corner case final corner?)
                    Align(alignment: Alignment.topLeft, child: corner),
                  if (badge case final badge?)
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // A second line only where there is the room for it.
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The grid layout for [PictureTile]s.
const pictureTileGrid = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 104,
  mainAxisSpacing: 8,
  crossAxisSpacing: 8,
  childAspectRatio: 1.1,
);
