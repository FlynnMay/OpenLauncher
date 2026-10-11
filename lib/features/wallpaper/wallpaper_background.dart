import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/wallpaper/wallpaper.dart';
import 'package:openlauncher/features/home/picture.dart';
import 'package:video_player/video_player.dart';

/// Fills its parent with the wallpaper, dimmed so entities stay readable.
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
          WallpaperKind.image => Image(
            // Decoded at screen size; full-size photos are slow and heavy.
            image: ResizeImage(
              pictureAt(wallpaper.path),
              width:
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
            ),
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

/// A muted looping video, paused while the launcher is not on screen.
class _VideoWallpaper extends StatefulWidget {
  const _VideoWallpaper({super.key, required this.path});

  final String path;

  @override
  State<_VideoWallpaper> createState() => _VideoWallpaperState();
}

class _VideoWallpaperState extends State<_VideoWallpaper> {
  /// Retries before giving up until the launcher is next resumed.
  static const _tries = 5;

  /// Null until a player works.
  VideoPlayerController? _controller;
  late final AppLifecycleListener _lifecycle;
  Timer? _retry;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) {
          _retry?.cancel();
          _controller?.pause();
        } else if (_controller case final controller?) {
          controller.play();
        } else {
          _failures = 0;
          _start();
        }
      },
    );
    _start();
  }

  Future<void> _start() async {
    _retry?.cancel();
    // Never take audio focus from whatever else is playing.
    final options = VideoPlayerOptions(mixWithOthers: true);
    // A URL in the browser.
    final controller = kIsWeb
        ? VideoPlayerController.networkUrl(
            Uri.parse(widget.path),
            videoPlayerOptions: options,
          )
        : VideoPlayerController.file(
            File(widget.path),
            videoPlayerOptions: options,
          );
    try {
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.initialize();
      await controller.play();
    } on Object catch (error) {
      await controller.dispose();
      _failed(error);
      return;
    }
    if (!mounted || _controller != null) {
      await controller.dispose();
      return;
    }
    _failures = 0;
    // A player can also fail later, when another app takes the decoder.
    controller.addListener(() {
      if (controller.value.hasError && _controller == controller) {
        setState(() => _controller = null);
        controller.dispose();
        _failed(controller.value.errorDescription);
      }
    });
    setState(() => _controller = controller);
  }

  /// TVs have few video decoders and another app may still hold one, so a
  /// failed video is retried.
  void _failed(Object? error) {
    debugPrint('Wallpaper video failed: $error');
    if (!mounted || ++_failures >= _tries) return;
    _retry = Timer(Duration(seconds: 1 << (_failures - 1)), _start);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _lifecycle.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    final size = controller.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
