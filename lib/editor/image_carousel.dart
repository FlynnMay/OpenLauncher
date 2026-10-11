import 'package:flutter/material.dart';

@immutable
class CarouselImage {
  const CarouselImage({required this.id, required this.child});

  final String id;

  final Widget child;
}

/// Shows one of several pictures with controls to browse, add, remove and
/// make one first. With [max] 1 it is a single replaceable picture. It only
/// reports; the caller does the work.
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

  final int max;
  final double aspectRatio;

  /// Text shown when there is no picture.
  final String empty;
  final String addLabel, replaceLabel, removeLabel, firstLabel;

  /// While something is pending, such as an upload.
  final bool busy;

  /// Add a picture, or replace it when [max] is 1.
  final VoidCallback? onAdd;
  final void Function(String id)? onRemove;

  final void Function(String id)? onFirst;

  /// All are removable if null.
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
      // Go to the one just added.
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
