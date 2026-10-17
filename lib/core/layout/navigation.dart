import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';

enum NavDirection { left, right, up, down }

/// A focusable thing: its rect and the containers it is in, outermost first.
@immutable
class NavSpot<T> {
  const NavSpot(this.id, this.rect, [this.containers = const []]);

  final T id;
  final Rect rect;
  final List<String> containers;
}

/// How a spot's pane relates to the focused one, in order of preference.
enum NavKinship { same, child, parent, other }

NavKinship navKinship(List<String> from, List<String> to) {
  final shared = min(from.length, to.length);
  for (var i = 0; i < shared; i++) {
    if (from[i] != to[i]) return NavKinship.other;
  }
  if (from.isEmpty || to.isEmpty) return NavKinship.other;
  return to.length == from.length
      ? NavKinship.same
      : to.length > from.length
      ? NavKinship.child
      : NavKinship.parent;
}

/// Where the focus goes from [from] when the D-pad is pressed towards
/// [direction], or null if there is nowhere to go.
///
/// Only spots lying in that direction count. Among them:
///
/// 1. What is in the same pane always comes first.
/// 2. Then what is in line with where the focus is (overlapping it across
///    the direction of travel) beats what is off to the side.
/// 3. Then the pane decides (see [NavKinship]): a pane inside, the pane
///    around, any other.
/// 4. Then the nearest wins.
///
/// Being in line is put before the kind of pane so that, leaving a pane, the
/// focus goes to what is straight ahead rather than to something of the pane
/// around it that happens to lie far off to one side.
NavSpot<T>? navigate<T>(
  NavSpot<T> from,
  Iterable<NavSpot<T>> spots,
  NavDirection direction,
) {
  final a = from.rect;
  final slack = 0.01 * min(a.width, a.height);
  NavSpot<T>? best;
  var bestKinship = NavKinship.other, bestScore = double.infinity;
  var bestInLine = false;
  for (final spot in spots) {
    final c = spot.rect;
    if (identical(spot, from) || spot.id == from.id) continue;
    // In that direction: its middle is past ours, and it reaches further.
    final (ahead, gap, apart, askew) = switch (direction) {
      NavDirection.right => (
        c.center.dx > a.center.dx && c.right > a.right + slack,
        c.left - a.right,
        max(c.top - a.bottom, a.top - c.bottom),
        (c.center.dy - a.center.dy).abs(),
      ),
      NavDirection.left => (
        c.center.dx < a.center.dx && c.left < a.left - slack,
        a.left - c.right,
        max(c.top - a.bottom, a.top - c.bottom),
        (c.center.dy - a.center.dy).abs(),
      ),
      NavDirection.down => (
        c.center.dy > a.center.dy && c.bottom > a.bottom + slack,
        c.top - a.bottom,
        max(c.left - a.right, a.left - c.right),
        (c.center.dx - a.center.dx).abs(),
      ),
      NavDirection.up => (
        c.center.dy < a.center.dy && c.top < a.top - slack,
        a.top - c.bottom,
        max(c.left - a.right, a.left - c.right),
        (c.center.dx - a.center.dx).abs(),
      ),
    };
    if (!ahead) continue;
    final kinship = navKinship(from.containers, spot.containers);
    final inLine = apart < 0;
    // Distance, with a heavy penalty for being off to the side and a light
    // one for not being level.
    final score = max(0.0, gap) + 3 * max(0.0, apart) + 0.25 * askew;
    final same = kinship == NavKinship.same;
    final better = best == null
        ? true
        : same != (bestKinship == NavKinship.same)
        ? same
        : inLine != bestInLine
        ? inLine
        : kinship != bestKinship
        ? kinship.index < bestKinship.index
        : score < bestScore;
    if (better) {
      best = spot;
      bestKinship = kinship;
      bestInLine = inLine;
      bestScore = score;
    }
  }
  return best;
}
