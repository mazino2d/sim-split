import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Takes an account out of a group that has other members (AC6, AC14): the
/// account's member stays with its expenses and becomes unclaimed, the
/// change is logged, and ownership passes to another member. One batch.
class GroupLeaver {
  const GroupLeaver({
    required FirebaseFirestore firestore,
    required this.timeout,
    required DateTime Function() clock,
    required String Function() newId,
  })  : _firestore = firestore,
        _clock = clock,
        _newId = newId;

  final FirebaseFirestore _firestore;
  final Duration timeout;
  final DateTime Function() _clock;
  final String Function() _newId;

  Future<void> leave(
    DocumentSnapshot<Map<String, dynamic>> group,
    String uid,
  ) async {
    final ref = group.reference;
    final data = group.data() ?? const <String, dynamic>{};
    final memberUids =
        List<String>.from(data['memberUids'] as List? ?? const <String>[]);
    final claimed = await ref
        .collection('members')
        .where('linkedUid', isEqualTo: uid)
        .get()
        .timeout(timeout);

    final batch = _firestore.batch();
    for (final member in claimed.docs) {
      final before = {...member.data()}..remove('updatedAt');
      final after = {...before, 'linkedUid': null, 'updatedBy': uid};
      batch.update(member.reference, {
        'linkedUid': null,
        'updatedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.set(ref.collection('activity').doc(_newId()), {
        'actorUid': uid,
        'action': 'update',
        'entityType': 'member',
        'entityId': member.id,
        'before': {'id': member.id, ...before},
        'after': {'id': member.id, ...after},
        'clientTime': _clock().millisecondsSinceEpoch,
        'syncedAt': FieldValue.serverTimestamp(),
      });
    }
    final owner = data['ownerUid'];
    batch.update(ref, {
      'memberUids': FieldValue.arrayRemove([uid]),
      if (owner == uid) 'ownerUid': memberUids.firstWhere((u) => u != uid),
      'updatedBy': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit().timeout(timeout);
  }
}
