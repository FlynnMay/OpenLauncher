import 'package:flutter/foundation.dart';

/// What a card does when selected. New kinds (shortcuts, ...) are added here
/// and given a source in `cards_provider.dart`. Declaration order is the
/// default display order.
enum CardKind { input, app }

/// One tile on the home screen, after user config has been applied.
@immutable
class LauncherCard {
  const LauncherCard({
    required this.id,
    required this.kind,
    required this.target,
    required this.label,
    this.iconPath,
    this.wideIcon = false,
    this.svg,
  });

  /// Stable key used by config and the command API, e.g. `app:com.example`.
  final String id;
  final CardKind kind;

  /// Kind-specific launch target: the package name for [CardKind.app], the
  /// TV input id for [CardKind.input].
  final String target;
  final String label;

  /// Absolute path of the image to show, or null to fall back to the label.
  final String? iconPath;

  /// True when [iconPath] is 16:9 artwork that should fill the card.
  final bool wideIcon;

  /// Built-in line art, as SVG markup, shown when there is no [iconPath].
  /// Cards drawn this way have no background of their own.
  final String? svg;

  static String appId(String packageName) => 'app:$packageName';
  static String inputId(String tvInputId) => 'input:$tvInputId';

  @override
  bool operator ==(Object other) =>
      other is LauncherCard &&
      other.id == id &&
      other.kind == kind &&
      other.target == target &&
      other.label == label &&
      other.iconPath == iconPath &&
      other.wideIcon == wideIcon &&
      other.svg == svg;

  @override
  int get hashCode =>
      Object.hash(id, kind, target, label, iconPath, wideIcon, svg);
}
