import 'package:flutter/foundation.dart';

/// What a card does when selected. New kinds (shortcuts, ...) are added here
/// and given a source in `cards_provider.dart`. Declaration order is the
/// default display order.
enum CardKind {
  input,
  app,

  /// Something the launcher itself does, such as opening its settings.
  action,
}

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

  /// The card that opens the launcher's settings. It can be placed like
  /// any other; while it is nowhere, the home screen shows a button instead.
  static const settings = LauncherCard(
    id: 'launcher:settings',
    kind: CardKind.action,
    target: 'settings',
    label: 'Settings',
    // A cog, in the same line drawing as the input cards.
    svg:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 90" '
        'fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round" '
        'stroke-linejoin="round"><circle cx="80" cy="45" r="7"/>'
        '<circle cx="80" cy="45" r="17"/><path d="M80 20v8m0 34v8M55 45h8'
        'm34 0h8M62.3 27.3l5.7 5.7m24 24 5.7 5.7m0-35.4L92 33M68 57l-5.7 '
        '5.7"/></svg>',
  );

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
