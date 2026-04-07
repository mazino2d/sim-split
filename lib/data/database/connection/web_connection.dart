import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// WASM-based web database — volatile (in-memory) so data resets on reload.
QueryExecutor openConnection() => driftDatabase(
      name: 'simsplit_db',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
