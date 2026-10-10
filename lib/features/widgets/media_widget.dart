import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/widgets/widgets.dart';
import 'package:openlauncher/features/home/focus_tile.dart';
import 'package:openlauncher/platform/launcher_platform.dart';

/// Shows what is playing; OK plays or pauses it.
class MediaWidget extends ConsumerWidget {
  const MediaWidget({super.key, this.compact = false});

  /// True in a closed rail, where there is only room for the cover.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const quiet = TextStyle(color: Colors.white70, fontSize: 13);
    final playing = ref.watch(nowPlayingProvider).value;
    if (playing == null) {
      final allowed = ref.watch(notificationAccessProvider).value ?? true;
      return compact
          ? const Icon(Icons.music_note_outlined, color: Colors.white38)
          : Center(
              child: Text(
                allowed
                    ? 'Nothing is playing'
                    : 'Run automatic setup in Settings\nto see what is playing',
                style: quiet,
                textAlign: TextAlign.center,
              ),
            );
    }
    final art = playing.artPath;
    return FocusTile(
      focusedScale: 1.04,
      onSelect: () => ref
          .read(launcherPlatformProvider)
          .sendMediaCommand(MediaCommand.playPause),
      builder: (context, focused) => AnimatedContainer(
        duration: FocusTile.duration,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: focused ? 0.12 : 0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: focused ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          spacing: 12,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: art == null
                    ? const ColoredBox(
                        color: Colors.white10,
                        child: Icon(Icons.music_note_outlined),
                      )
                    : Image.file(
                        File(art),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
              ),
            ),
            if (!compact)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playing.title ?? playing.appLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    Text(
                      [?playing.artist, playing.appLabel].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: quiet,
                    ),
                  ],
                ),
              ),
            if (!compact)
              Icon(
                playing.playing
                    ? Icons.pause_circle_outline
                    : Icons.play_circle_outline,
                color: Colors.white,
              ),
          ],
        ),
      ),
    );
  }
}
