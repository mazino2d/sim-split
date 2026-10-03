import 'package:integration_test/integration_test_driver.dart';

// Failure messages recorded by the tests land in
// build/integration_response_data.json.
Future<void> main() => integrationDriver(writeResponseOnFailure: true);
