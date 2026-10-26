/// URL of the R-4 telemetry endpoint (Cloud Run `telemetry` in
/// simsplit-as-se1-prd), set with `--dart-define=TELEMETRY_URL=<url>`. The
/// URL is public; the endpoint checks App Check on every request. Empty means
/// error reports are recorded and queued but never sent. Dev builds
/// (APP_ENV=dev) leave it empty: the endpoint only accepts App Check tokens
/// from simsplit-as-se1-prd.
const telemetryUrl = String.fromEnvironment('TELEMETRY_URL');
