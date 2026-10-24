import 'dart:io';

/// The OS name and version for error reports, e.g. `android 14`.
String deviceOs() {
  final version = Platform.operatingSystemVersion;
  final short = version.length > 40 ? version.substring(0, 40) : version;
  return '${Platform.operatingSystem} $short';
}
