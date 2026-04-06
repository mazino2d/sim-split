import 'package:drift/drift.dart';
import 'package:drift/web.dart';

// In-memory web database for UI testing — data does not persist between reloads.
QueryExecutor openConnection() =>
    WebDatabase.withStorage(DriftWebStorage.volatile());
