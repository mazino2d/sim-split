/// What the Diagnostics screen shows about error reports (R-4 AC25–AC27).
class ErrorReportSettings {
  const ErrorReportSettings({
    required this.enabled,
    required this.reportId,
    required this.waitingCount,
    required this.appVersion,
    required this.platform,
  });

  /// Whether error reports are recorded and sent (on by default).
  final bool enabled;

  /// The install's random report ID, e.g. `7KQ-4MZ`; null while reports are
  /// off.
  final String? reportId;

  /// Error reports still waiting on the device to be sent.
  final int waitingCount;

  /// e.g. `2026.10.22+42`, shown so testers can quote it.
  final String appVersion;

  /// 'android' | 'ios' | 'web'
  final String platform;
}
