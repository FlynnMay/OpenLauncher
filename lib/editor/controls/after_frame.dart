import 'package:flutter/material.dart';

/// Builds from a value only known after layout, such as another widget's
/// position. [read] runs after every frame; the builder re-runs when the
/// value changes.
class AfterFrame<T> extends StatefulWidget {
  const AfterFrame({
    super.key,
    required this.read,
    required this.builder,
    this.same,
  });

  final T Function() read;

  /// Equality for the value; `==` by default.
  final bool Function(T a, T b)? same;

  /// Null until the first frame.
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
