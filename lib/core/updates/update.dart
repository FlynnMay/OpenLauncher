import 'package:flutter/foundation.dart';
import 'package:openlauncher/core/config/app_version.dart';
import 'package:openlauncher/core/nodes/field.dart';

/// What the launcher does about a newer release of itself.
enum UpdateMode { off, notify, auto }

@immutable
class UpdateOptions {
  const UpdateOptions({this.mode = UpdateMode.notify});

  final UpdateMode mode;

  /// The editor's form is generated from this.
  static const options = [
    Field(
      'mode',
      'Automatic updates',
      FieldKind.choice,
      defaultValue: 'notify',
      choices: {'off': 'Off', 'notify': 'Notify', 'auto': 'Install'},
    ),
  ];

  factory UpdateOptions.fromJson(Map<Object?, Object?> json) => UpdateOptions(
    mode: UpdateMode.values.asNameMap()[json['mode']] ?? UpdateMode.notify,
  );

  Map<String, Object?> toJson() => {'mode': mode.name};
}

/// The numbers of a version such as `0.1.2` or `v0.1.2`; null if it is none.
List<int>? versionNumbers(String version) {
  final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)$').firstMatch(version.trim());
  if (match == null) return null;
  return [for (var part = 1; part <= 3; part++) int.parse(match[part]!)];
}

/// Whether [version] is a later release than [than].
bool isLaterVersion(String version, String than) {
  final a = versionNumbers(version), b = versionNumbers(than);
  if (a == null || b == null) return false;
  for (var part = 0; part < 3; part++) {
    if (a[part] != b[part]) return a[part] > b[part];
  }
  return false;
}

/// A published release that has an APK.
@immutable
class Release {
  const Release({
    required this.version,
    required this.apk,
    required this.bytes,
    this.sha256,
    this.notes = '',
  });

  /// As in `0.1.2`.
  final String version;
  final Uri apk;
  final int bytes;

  /// The APK's hash in hex, when the host gives one.
  final String? sha256;
  final String notes;

  /// Read from GitHub's JSON for a release; null if its tag is not a version
  /// or it has no APK.
  static Release? fromGitHub(Object? json) {
    if (json case {
      'tag_name': final String tag,
      'assets': final List<Object?> assets,
    }) {
      final numbers = versionNumbers(tag);
      if (numbers == null) return null;
      for (final asset in assets) {
        if (asset
            case {
              'name': final String name,
              'browser_download_url': final String url,
              'size': final int bytes,
            }
            when name.endsWith('.apk')) {
          return Release(
            version: numbers.join('.'),
            apk: Uri.parse(url),
            bytes: bytes,
            sha256: switch (asset['digest']) {
              final String digest when digest.startsWith('sha256:') =>
                digest.substring(7).toLowerCase(),
              _ => null,
            },
            notes: switch (json['body']) {
              final String body => body.trim(),
              _ => '',
            },
          );
        }
      }
    }
    return null;
  }
}

enum UpdateStatus { idle, checking, downloading, installing, failed }

/// Where the launcher stands against the latest release.
@immutable
class UpdateState {
  const UpdateState({
    this.current = appVersion,
    this.latest,
    this.notes = '',
    this.status = UpdateStatus.idle,
    this.progress = 0,
    this.error,
  });

  /// The release that is running.
  final String current;

  /// The latest release found, if a check has found one.
  final String? latest;

  /// What [latest] says of itself.
  final String notes;
  final UpdateStatus status;

  /// Of the download, 0 to 1.
  final double progress;

  /// Why it [UpdateStatus.failed].
  final String? error;

  bool get available => latest != null && isLaterVersion(latest!, current);

  bool get busy =>
      status == UpdateStatus.checking ||
      status == UpdateStatus.downloading ||
      status == UpdateStatus.installing;

  /// Where it stands, in a line.
  String get summary => switch (status) {
    UpdateStatus.checking => 'Checking for updates…',
    UpdateStatus.downloading =>
      'Downloading $latest: ${(progress * 100).round()}%',
    UpdateStatus.installing => 'Installing $latest…',
    UpdateStatus.failed => error ?? 'Something went wrong.',
    UpdateStatus.idle =>
      available
          ? 'Version $latest is available'
          : latest == null
          ? 'Version $current'
          : 'Version $current is the latest',
  };

  UpdateState doing(UpdateStatus status, {double progress = 0}) => UpdateState(
    current: current,
    latest: latest,
    notes: notes,
    status: status,
    progress: progress,
  );

  UpdateState failed(String error) => UpdateState(
    current: current,
    latest: latest,
    notes: notes,
    status: UpdateStatus.failed,
    error: error,
  );

  factory UpdateState.fromJson(Object? json) => switch (json) {
    final Map<Object?, Object?> json => UpdateState(
      current: json['current'] is String ? json['current']! as String : '',
      latest: json['latest'] is String ? json['latest']! as String : null,
      notes: json['notes'] is String ? json['notes']! as String : '',
      status:
          UpdateStatus.values.asNameMap()[json['status']] ?? UpdateStatus.idle,
      progress: json['progress'] is num
          ? (json['progress']! as num).toDouble()
          : 0,
      error: json['error'] is String ? json['error']! as String : null,
    ),
    _ => const UpdateState(),
  };

  Map<String, Object?> toJson() => {
    'current': current,
    'latest': latest,
    'available': available,
    'notes': notes,
    'status': status.name,
    'progress': progress,
    'error': error,
  };

  @override
  bool operator ==(Object other) =>
      other is UpdateState &&
      other.current == current &&
      other.latest == latest &&
      other.notes == notes &&
      other.status == status &&
      other.progress == progress &&
      other.error == error;

  @override
  int get hashCode =>
      Object.hash(current, latest, notes, status, progress, error);
}
