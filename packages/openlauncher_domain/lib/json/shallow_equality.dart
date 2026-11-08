import 'package:collection/collection.dart';

/// Same keys, each value `==` the other's; values are not looked inside.
bool mapsEqual(Map<Object?, Object?>? a, Map<Object?, Object?>? b) =>
    const MapEquality<Object?, Object?>().equals(a, b);

/// Same length, each item `==` the other's in order.
bool listsEqual(List<Object?>? a, List<Object?>? b) =>
    const ListEquality<Object?>().equals(a, b);
