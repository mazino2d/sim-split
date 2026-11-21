import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fpdart/fpdart.dart';

import 'package:simsplit/domain/entities/notifications/announcement.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/announcement_repository.dart';

/// `announcements/{id}` (R-9 AC12), written only by `services/crm`:
/// `banner {en, vi: {title, body}}`, `all`, `audienceUids`, `endsAt`. The
/// rules let an account read one addressed to everyone or to it, so the
/// app runs exactly those two queries. Dismissed ids live in
/// `users/{uid}.dismissedAnnouncements`, shared by the account's devices.
class FirestoreAnnouncementRepository implements AnnouncementRepository {
  const FirestoreAnnouncementRepository({
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
    DateTime Function()? now,
  })  : _firestore = firestore,
        _currentUid = currentUid,
        _now = now ?? DateTime.now;

  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;
  final DateTime Function() _now;

  static const dismissedField = 'dismissedAnnouncements';
  static const _limit = 10;
  static const _ackTimeout = Duration(seconds: 5);

  static Announcement? parse(String id, Map<String, dynamic> data) {
    final banner = data['banner'];
    final endsAt = data['endsAt'];
    if (banner is! Map || endsAt is! Timestamp) return null;
    final copy = <String, AnnouncementCopy>{};
    for (final lang in const ['en', 'vi']) {
      final c = banner[lang];
      if (c is Map && c['title'] is String && c['body'] is String) {
        copy[lang] = AnnouncementCopy(
            title: c['title'] as String, body: c['body'] as String);
      }
    }
    if (copy.isEmpty) return null;
    return Announcement(id: id, copy: copy, endsAt: endsAt.toDate());
  }

  Stream<Either<Failure, T>> _guard<T>(Stream<Either<Failure, T>> stream) =>
      stream.transform(StreamTransformer.fromHandlers(
        handleError: (error, stackTrace, sink) =>
            sink.add(left(Failure.unexpected(error.toString()))),
      ));

  @override
  Stream<Either<Failure, List<Announcement>>> watchAnnouncements() {
    final uid = _currentUid();
    if (uid == null) return Stream.value(right(const []));
    final collection = _firestore.collection('announcements');
    final notEnded =
        Filter('endsAt', isGreaterThan: Timestamp.fromDate(_now()));
    final queries = [
      collection.where(
          Filter.and(Filter('audienceUids', arrayContains: uid), notEnded)),
      collection.where(Filter.and(Filter('all', isEqualTo: true), notEnded)),
    ];

    late final StreamController<Either<Failure, List<Announcement>>> controller;
    final latest = List<List<Announcement>?>.filled(queries.length, null);
    final subs = <StreamSubscription<Object?>>[];
    controller = StreamController(
      onListen: () {
        for (var i = 0; i < queries.length; i++) {
          subs.add(_guard(queries[i]
              .limit(_limit)
              .snapshots()
              .map<Either<Failure, List<Announcement>>>((snap) => right(snap
                  .docs
                  .map((doc) => parse(doc.id, doc.data()))
                  .whereType<Announcement>()
                  .toList()))).listen(
              (either) => either.fold((f) => controller.add(left(f)), (list) {
                    latest[i] = list;
                    if (latest.every((l) => l != null)) {
                      final byId = {
                        for (final l in latest)
                          for (final a in l!) a.id: a,
                      };
                      controller.add(right(byId.values.toList()));
                    }
                  })));
        }
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }

  static Set<String> _dismissed(Map<String, dynamic>? data) {
    final raw = data?[dismissedField];
    return raw is List ? raw.whereType<String>().toSet() : const {};
  }

  @override
  Stream<Either<Failure, Set<String>>> watchDismissed() {
    final uid = _currentUid();
    if (uid == null) return Stream.value(right(const {}));
    return _guard(_firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map<Either<Failure, Set<String>>>(
            (doc) => right(_dismissed(doc.data()))));
  }

  @override
  Future<Either<Failure, Unit>> dismiss(String id) async {
    final uid = _currentUid();
    if (uid == null) return left(const Failure.unexpected('Not signed in'));
    final doc = _firestore.collection('users').doc(uid);
    try {
      List<String>? current;
      try {
        final raw =
            (await doc.get().timeout(_ackTimeout)).data()?[dismissedField];
        current = raw is List ? raw.whereType<String>().toList() : <String>[];
      } on TimeoutException {
        // Offline: add it without trimming; the next dismissal trims.
      }
      if (current != null && current.contains(id)) return right(unit);
      final Object value =
          current == null || current.length < maxDismissedAnnouncements
              ? FieldValue.arrayUnion([id])
              : [
                  ...current.sublist(
                      current.length - (maxDismissedAnnouncements - 1)),
                  id,
                ];
      try {
        await doc.update({dismissedField: value}).timeout(_ackTimeout);
      } on TimeoutException {
        // Queued; it goes out once online.
      }
      return right(unit);
    } on FirebaseException catch (e) {
      return left(Failure.unexpected('${e.code} ${e.message}'));
    }
  }
}
