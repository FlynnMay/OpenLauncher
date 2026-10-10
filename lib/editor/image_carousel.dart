import 'package:flutter/material.dart';

/// One of the pictures an [ImageCarousel] shows.
@immutable
class CarouselImage {
  const CarouselImage({required this.id, required this.child});

  /// What it is told apart by.
  final String id;

  /// The picture itself; it is given the whole frame.
  final Widget child;
}

/// A frame showing one of several pictures at a time, with the means to go
/// through them, add to them, take one away and put one first. With [max]
/// of 1 it is simply a picture that can be chosen, replaced and removed.
///
/// It only shows and asks: what adding or removing does is the caller's.
/// Whichever of [onAdd], [onRemove] and [onFirst] is null is not offered.
class ImageCarousel extends StatefulWidget {
  const ImageCarousel({
    super.key,
    required this.images,
    this.max = 1,
    this.aspectRatio = 16 / 9,
    this.empty = 'No picture',
    this.addLabel = 'Add',
    this.replaceLabel = 'Replace',
    this.removeLabel = 'Remove',
    this.firstLabel = 'Show this one first',
    this.busy = false,
    this.onAdd,
    this.onRemove,
    this.onFirst,
    this.canRemove,
  });

  final List<CarouselImage> images;

  /// How many pictures there may be.
  final int max;
  final double aspectRatio;

  /// What the frame says while there is no picture.
  final String empty;
  final String addLabel, replaceLabel, removeLabel, firstLabel;

  /// True while something is on its way, such as an upload.
  final bool busy;

  /// Asked for another picture, or with [max] of 1 and one there already,
  /// for a different one.
  final VoidCallback? onAdd;
  final void Function(String id)? onRemove;

  /// Asked to put a picture in front of the others.
  final void Function(String id)? onFirst;

  /// Whether a given picture can be removed; all can if this is null.
  final bool Function(String id)? canRemove;

  @override
  State<ImageCarousel> createState() => _ImageCarouselState();
}

class _ImageCarouselState extends State<ImageCarousel> {
  final _pages = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(ImageCarousel old) {
    super.didUpdateWidget(old);
    final count = widget.images.length;
    if (count > old.images.length && old.images.isNotEmpty) {
      // One was added: go to it.
      _go(count - 1);
    } else if (_index >= count) {
      _index = count == 0 ? 0 : count - 1;
    }
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index) {
    _index = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pages.hasClients) {
        _pages.animateToPage(
          index,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final images = widget.images;
    final current = images.isEmpty ? null : images[_index];
    final single = widget.max <= 1;
    final full = images.length >= widget.max;
    Widget arrow(IconData icon, int to, Alignment side) => Align(
      alignment: side,
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        onPressed: to < 0 || to >= images.length
            ? null
            : () => setState(() => _go(to)),
        icon: Icon(icon),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (images.isEmpty)
                  Center(
                    child: Text(
                      widget.empty,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  )
                else
                  PageView(
                    controller: _pages,
                    onPageChanged: (index) => setState(() => _index = index),
                    children: [
                      for (final image in images)
                        KeyedSubtree(
                          key: ValueKey(image.id),
                          child: image.child,
                        ),
                    ],
                  ),
                if (images.length > 1) ...[
                  arrow(Icons.chevron_left, _index - 1, Alignment.centerLeft),
                  arrow(Icons.chevron_right, _index + 1, Alignment.centerRight),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      margin: const EdgeInsets.all(6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_index + 1} of ${images.length}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
                ],
                if (widget.busy)
                  const ColoredBox(
                    color: Colors.black54,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.onAdd case final add?)
              TextButton.icon(
                onPressed: widget.busy || full && !single ? null : add,
                icon: Icon(
                  single && full ? Icons.swap_horiz : Icons.add_photo_alternate,
                ),
                label: Text(
                  single && full ? widget.replaceLabel : widget.addLabel,
                ),
              ),
            if (widget.onFirst case final first? when current != null)
              if (_index > 0)
                IconButton(
                  tooltip: widget.firstLabel,
                  onPressed: widget.busy
                      ? null
                      : () {
                          first(current.id);
                          setState(() => _go(0));
                        },
                  icon: const Icon(Icons.vertical_align_top),
                ),
            if (widget.onRemove case final remove? when current != null)
              if (widget.canRemove?.call(current.id) ?? true)
                IconButton(
                  tooltip: widget.removeLabel,
                  onPressed: widget.busy ? null : () => remove(current.id),
                  icon: const Icon(Icons.delete_outline),
                ),
          ],
        ),
      ],
    );
  }
}
