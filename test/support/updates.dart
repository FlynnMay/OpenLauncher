import 'package:openlauncher/core/updates/updates.dart';

/// A release later than any this code will be.
const later = '99.0.0';

Release release(String version, {String notes = 'Fixes.'}) => Release(
  version: version,
  apk: Uri.parse('https://releases.test/openlauncher-$version.apk'),
  bytes: 4,
  notes: notes,
);

/// Releases without GitHub: [found] is the latest there is.
class FakeUpdateSource implements UpdateSource {
  FakeUpdateSource([this.found]);

  Release? found;

  /// Thrown by [latest] and [download] when set.
  Object? failure;
  int checks = 0;
  final downloaded = <String>[];
  bool discarded = false;

  @override
  Future<Release?> latest() async {
    checks++;
    if (failure case final failure?) throw failure;
    return found;
  }

  @override
  Future<String> download(
    Release release,
    void Function(double) onProgress,
  ) async {
    if (failure case final failure?) throw failure;
    onProgress(0.5);
    onProgress(1);
    downloaded.add(release.version);
    return '/cache/update.apk';
  }

  @override
  Future<void> discard() async => discarded = true;
}
