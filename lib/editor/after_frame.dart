import 'package:flutter/material.dart';

/// Builds with something that can only be known once the page has been laid
/// out, such as where another widget is on screen. [read] is asked after
/// every frame, and the builder is run again when the answer has changed.
/// Asking does not itself cause a frame.
class AfterFrame<T> extends StatefulWidget {
  const AfterFrame({
    super.key,
    required this.read,
    required this.builder,
    this.same,
  });

  final T Function() read;

  /// Whether two answers are the same; `==` if not given.
  final bool Function(T a, T b)? same;

  /// Given null until the first frame has been drawn.
  final Widget Function(BuildContext context, T? value) builder;

  @override
  State<AfterFrame<T>> createState() => _AfterFrameState<T>();
}

class _AfterFrameState<T> extends State<AfterFrame<T>> {
  T? _value;

  @override
  void initState() {
    super.initState();
    _watch();
  }

  void _watch() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final value = widget.read();
    final before = _value;
    final same =
        before != null && (widget.same?.call(before, value) ?? before == value);
    if (!same && !(before == null && value == null)) {
      setState(() => _value = value);
    }
    _watch();
  });

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
