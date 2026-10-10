import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cards/cards_provider.dart';
import '../../core/cards/launcher_card.dart';
import '../home_button/home_button.dart';
import '../settings/settings_screen.dart';
import '../wallpaper/wallpaper_background.dart';
import 'card_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  // TV overscan-safe margins (5% of a 960x540dp screen).
  static const _padding = EdgeInsets.symmetric(horizontal: 48, vertical: 27);

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    LauncherCard card,
  ) async {
    try {
      await ref.read(cardActionsProvider).launch(card);
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${card.label}: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(cardsProvider);
    return PopScope(
      // This is the home screen: Back has nowhere to go.
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const WallpaperBackground(),
            cards.when(
              skipLoadingOnReload: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: _padding,
                  child: Text('Could not load apps: $error'),
                ),
              ),
              data: (cards) => cards.isEmpty
                  ? const Center(child: Text('No apps found'))
                  : CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: _padding.copyWith(bottom: 0),
                          sliver: SliverToBoxAdapter(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              spacing: 8,
                              children: [
                                // Offered until Home opens this launcher.
                                if (ref
                                        .watch(homeButtonEnabledProvider)
                                        .value ==
                                    false)
                                  _HeaderButton(
                                    icon: Icons.home_outlined,
                                    label: 'Set as Home',
                                    onPressed: () =>
                                        SettingsScreen.show(context),
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
                        SliverPadding(
                          padding: _padding.copyWith(top: 12),
                          sliver: SliverGrid.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 180,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 20,
                                  childAspectRatio: 1.45,
                                ),
                            itemCount: cards.length,
                            itemBuilder: (context, index) {
                              final card = cards[index];
                              return CardTile(
                                key: ValueKey(card.id),
                                card: card,
                                autofocus: index == 0,
                                onSelect: () => _open(context, ref, card),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
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
