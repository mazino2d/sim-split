import 'package:uuid/uuid.dart';

/// Type-safe wrapper around a UUID string identifier.
class UniqueId {
  const UniqueId._(this.value);

  factory UniqueId.generate() => UniqueId._(const Uuid().v4());

  factory UniqueId.fromString(String id) {
    assert(id.isNotEmpty, 'UniqueId cannot be empty');
    return UniqueId._(id);
  }

  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UniqueId && other.value == value);

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
