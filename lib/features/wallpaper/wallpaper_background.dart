import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/wallpaper/wallpaper.dart';

/// Fills its parent with the wallpaper, dimmed so cards stay readable.
class WallpaperBackground extends ConsumerWidget {
  const WallpaperBackground({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallpaper = ref.watch(wallpaperProvider);
    if (wallpaper == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        switch (wallpaper.kind) {
          WallpaperKind.image => Image.file(
            File(wallpaper.path),
            // A new upload has a new path, so this also restarts animations.
            key: ValueKey(wallpaper.path),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
          WallpaperKind.video => _VideoWallpaper(
            key: ValueKey(wallpaper.path),
            path: wallpaper.path,
          ),
        },
        const ColoredBox(color: Color(0x73000000)),
      ],
    );
  }
}

/// A silent, looping video that stops decoding while the launcher is not on
/// screen.
class _VideoWallpaper extends StatefulWidget {
  const _VideoWallpaper({super.key, required this.path});

  final String path;

  @override
  State<_VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends State<_VideoWallpaper> {
  late final VideoPlayerController _controller;
  late final AppLifecycleListener _lifecycle;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(
      File(widget.path),
      // Never take audio focus from whatever else is playing.
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) => state == AppLifecycleState.resumed
          ? _controller.play()
          : _controller.pause(),
    );
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.setVolume(0);
      await _controller.setLooping(true);
      await _controller.initialize();
      await _controller.play();
      if (mounted) setState(() => _ready = true);
    } on Object catch (error) {
      // An unplayable file leaves the plain background.
      debugPrint('Wallpaper video failed: $error');
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    final size = _controller.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(_controller),
      ),
    );
  }
}
