import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:openlauncher/core/config/config.dart';
import 'package:openlauncher/core/layout/layout.dart';
import 'package:openlauncher/editor/controls/controls.dart';
import 'package:openlauncher/editor/modules/module_edit_context.dart';
import 'package:openlauncher/editor/tv/tv.dart';

/// The screen's own wallpapers, then how often they change.
List<Widget> wallpaperEditor(ModuleEdit edit) => [
  _Files(edit: edit),
  if ((edit.shown.wallpaperFiles?.length ?? 0) > 1) ...edit.fields(),
];

class _Files extends ConsumerStatefulWidget {
  const _Files({required this.edit});

  final ModuleEdit edit;

  @override
  ConsumerState<_Files> createState() => _FilesState();
}

class _FilesState extends ConsumerState<_Files> with Busy<_Files> {
  @override
  Widget build(BuildContext context) {
    final api = ref.watch(tvApiProvider);
    final edit = widget.edit;
    final files = edit.shown.wallpaperFiles ?? const <String>[];
    void set(List<String> files) => edit.set('files', files);
    return ImageCarousel(
      max: LauncherConfig.maxWallpapers,
      empty: 'A plain background',
      addLabel: 'Add a picture or video',
      firstLabel: edit.shown.wallpaperEvery == 0
          ? 'Make this the wallpaper'
          : 'Show this one first',
      busy: busy,
      images: [
        for (final id in files)
          CarouselImage(id: id, child: MediaPreview(api.mediaUrl(id))),
      ],
      onAdd: () => whileBusy(() async {
        final file = await pickFile(
          accept: 'image/*,video/mp4,video/webm,.mkv',
        );
        if (file == null) return;
        final url = await api.upload(file, wallpaper: true);
        set([...files, TvApi.mediaIdOf(url)]);
      }),
      // The file stays on the TV; Media deletes it.
      onRemove: (id) => set([
        for (final other in files)
          if (other != id) other,
      ]),
      onFirst: (id) => set([
        id,
        for (final other in files)
          if (other != id) other,
      ]),
    );
  }
}
