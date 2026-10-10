import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/features/home/entry_tile.dart';
import 'package:openlauncher/features/home/popup_panel.dart';
import 'package:openlauncher/features/home/rail.dart';
import 'package:openlauncher/features/home/section_grid.dart';
import 'package:openlauncher/features/home/styled_box.dart';
import 'package:openlauncher/features/home_button/home_button.dart';
import 'package:openlauncher/features/settings/settings_screen.dart';
import 'package:openlauncher/features/wallpaper/wallpaper_background.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // TV overscan-safe margins (5% of a 960x540dp screen).
  static const _padding = EdgeInsets.symmetric(horizontal: 48, vertical: 27);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = ref.watch(layoutViewProvider);
    return PopScope(
      // This is the home screen: Back has nowhere to go.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const WallpaperBackground(),
            ...layout.when(
              skipLoadingOnReload: true,
              loading: () => const [Center(child: CircularProgressIndicator())],
              error: (error, _) => [
                Center(
                  child: Padding(
                    padding: _padding,
                    child: Text('Could not load apps: $error'),
                  ),
                ),
              ],
              data: (layout) {
                final left = layout.sidebar(Layout.leftId);
                final right = layout.sidebar(Layout.rightId);
                return [
                  Padding(
                    // The rails open over the sections, which only make
                    // room for them closed.
                    padding: EdgeInsets.only(
                      left: left == null ? 0 : Rail.closedWidth - 32,
                      right: right == null ? 0 : Rail.closedWidth - 32,
                    ),
                    child: _Sections(view: layout.home, padding: _padding),
                  ),
                  if (left != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Rail(view: left, onLeft: true),
                    ),
                  if (right != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Rail(view: right, onLeft: false),
                    ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The scrolling body of the home screen: the header, then each section.
class _Sections extends ConsumerWidget {
  const _Sections({required this.view, required this.padding});

  final PanelView view;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = [
      for (final section in view.sections)
        if (section.entries.isNotEmpty) section,
    ];
    var first = true;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: padding.copyWith(bottom: 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                // Offered until Home opens this launcher.
                if (ref.watch(homeButtonEnabledProvider).value == false)
                  _HeaderButton(
                    icon: Icons.home_outlined,
                    label: 'Set as Home',
                    onPressed: () => SettingsScreen.show(context),
                  ),
                _HeaderButton(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onPressed: () => SettingsScreen.show(context),
                ),
              ],
            ),
          ),
        ),
        if (sections.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: Text('No apps found')),
          ),
        for (final section in sections)
          SliverPadding(
            padding: padding.copyWith(top: 12, bottom: 12),
            sliver: SliverToBoxAdapter(
              child: StyledBox(
                style: section.section.style,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (section.section.title.isNotEmpty)
                      SectionTitle(section.section.title),
                    SectionGrid(
                      view: section,
                      tile: (entry, _) {
                        // The first thing on screen that can be selected
                        // starts with the focus.
                        final autofocus = first && entry is! WidgetEntry;
                        if (autofocus) first = false;
                        return EntryTile(entry: entry, autofocus: autofocus);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        SliverPadding(padding: EdgeInsets.only(bottom: padding.bottom)),
      ],
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: TextButton.styleFrom(foregroundColor: Colors.white70),
    );
  }
}
