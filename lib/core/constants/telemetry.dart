/// URL of the R-4 telemetry endpoint (Cloud Run `telemetry` in
/// `simsplit-as-se1-<APP_ENV>`), set with `--dart-define=TELEMETRY_URL=<url>`.
/// The URL is public; the endpoint checks App Check on every request and only
/// accepts tokens from its own project, so CI passes each environment its own
/// endpoint. Empty means error reports are recorded and queued but never sent.
const telemetryUrl = String.fromEnvironment('TELEMETRY_URL');
