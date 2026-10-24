import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/entities/auth_user.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/repositories/user_profile_repository.dart';

/// `users/{uid}` in Firestore (R-4). The rules let an account create and
/// delete only its own document, never change the agreement afterwards, and
/// require it for every group read and write.
class FirestoreUserProfileRepository implements UserProfileRepository {
  const FirestoreUserProfileRepository({
    required FirebaseFirestore firestore,
    required String? Function() currentUid,
  })  : _firestore = firestore,
        _currentUid = currentUid;

  final FirebaseFirestore _firestore;
  final String? Function() _currentUid;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _firestore.collection('users').doc(uid);

  @override
  Future<Either<Failure, Unit>> recordAgreement(
      AuthUser user, String policyVersion) async {
    try {
      final doc = _doc(user.uid);
      if ((await doc.get()).exists) return right(unit);
      await doc.set({
        'displayName': user.displayName,
        'email': user.email,
        'createdAt': FieldValue.serverTimestamp(),
        'consent': {
          'agreedAt': FieldValue.serverTimestamp(),
          'policyVersion': policyVersion,
        },
      });
      return right(unit);
    } on FirebaseException catch (e) {
      // Sign-in and sync start both record the agreement; when they race, the
      // second create is refused because the document now exists.
      try {
        if ((await _doc(user.uid).get()).exists) return right(unit);
      } on FirebaseException {
        // Fall through to the original failure.
      }
      return left(Failure.unexpected('${e.code} ${e.message}'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteProfile() async {
    final uid = _currentUid();
    if (uid == null) return right(unit);
    try {
      await _doc(uid).delete();
      return right(unit);
    } on FirebaseException catch (e) {
      return left(Failure.unexpected('${e.code} ${e.message}'));
    }
  }
}
