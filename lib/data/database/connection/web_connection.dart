import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// WASM-based web database. Data persists across reloads in the browser's
// storage (OPFS when available, otherwise IndexedDB); drift picks the best
// supported backend at runtime. Requires web/sqlite3.wasm and
// web/drift_worker.js (see scripts/setup.sh).
QueryExecutor openConnection() => driftDatabase(
      name: 'simsplit_db',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
