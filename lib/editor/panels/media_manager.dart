import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/tv/tv.dart';

/// Every file uploaded to the TV, read again when what the config points at
/// changes.
final mediaProvider = FutureProvider.autoDispose<List<MediaFile>>((ref) {
  ref.watch(
    configProvider.select(
      (config) => Object.hashAll([
        ...?config.value?.wallpapers,
        ...?config.value?.iconOverrides.values,
        for (final screen in config.value?.layout.screens ?? const <Screen>[])
          ...?screen.root.wallpaperFiles,
      ]),
    ),
  );
  return ref.watch(tvApiProvider).media();
});

/// Opens the media manager.
class MediaButton extends StatelessWidget {
  const MediaButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: MediaManager.title,
    onPressed: () => MediaManager.show(context),
    icon: const Icon(MediaManager.icon),
  );
}

/// Every uploaded file and whether anything uses it. Files are only deleted
/// here; removing a picture or wallpaper elsewhere just stops using its file.
class MediaManager extends ConsumerStatefulWidget {
  const MediaManager({super.key});

  static const title = 'Media';
  static const icon = Icons.perm_media_outlined;

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => const Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(width: 920, height: 680, child: MediaManager()),
    ),
  );

  /// [bytes] as a size to read.
  static String sizeOf(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).ceil()} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  ConsumerState<MediaManager> createState() => _MediaManagerState();
}

class _MediaManagerState extends ConsumerState<MediaManager>
    with Busy<MediaManager> {
  Future<void> _delete(Future<void> Function(TvApi api) how) =>
      whileBusy(() async {
        try {
          await how(ref.read(tvApiProvider));
        } finally {
          ref.invalidate(mediaProvider);
        }
      });

  Future<void> _deleteUnused(List<MediaFile> unused) async {
    final sure = await confirm(
      context,
      unused.length == 1
          ? 'Delete 1 unused file?'
          : 'Delete ${unused.length} unused files?',
      'Nothing on the TV uses them. Deleted files cannot be brought back, '
          'by Undo either.',
      'Delete',
    );
    if (sure) await _delete((api) => api.deleteUnusedMedia());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final files = ref.watch(mediaProvider);
    final all = files.value ?? const <MediaFile>[];
    final unused = [
      for (final file in all)
        if (!file.used) file,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
          child: Row(
            spacing: 12,
            children: [
              Text(MediaManager.title, style: theme.textTheme.titleLarge),
              Expanded(
                child: Text(
                  all.isEmpty
                      ? ''
                      : '${all.length} files, ${unused.length} unused '
                            '(${MediaManager.sizeOf(unused.fold(0, (sum, file) => sum + file.bytes))})',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: busy || unused.isEmpty
                    ? null
                    : () => _deleteUnused(unused),
                icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                label: const Text('Delete unused'),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: switch (files) {
            AsyncValue(:final error?) when !files.hasValue => Center(
              child: Text('$error'.replaceFirst(RegExp(r'^Exception: '), '')),
            ),
            _ when !files.hasValue => const Center(
              child: CircularProgressIndicator(),
            ),
            _ when all.isEmpty => const Center(
              child: Text('Nothing has been uploaded.'),
            ),
            _ => GridView(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 168,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.3,
              ),
              children: [
                for (final file in all)
                  PictureTile(
                    key: ValueKey(file.id),
                    label: MediaManager.sizeOf(file.bytes),
                    tooltip: file.id,
                    picture: MediaPreview(file.url),
                    badge: file.used ? null : 'Unused',
                    corner: file.used
                        ? null
                        : IconButton(
                            tooltip: 'Delete',
                            visualDensity: VisualDensity.compact,
                            onPressed: busy
                                ? null
                                : () => _delete(
                                    (api) => api.deleteMedia(file.id),
                                  ),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                  ),
              ],
            ),
          },
        ),
      ],
    );
  }
}
