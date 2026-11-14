import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fpdart/fpdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // Firestore's offline cache is off, so the name is kept on the device
  // too, per account, for forms filled offline (#112).
  static String _cacheKey(String uid) => 'account_member_name:$uid';

  @override
  Future<Either<Failure, String?>> getMemberName() async {
    final uid = _currentUid();
    if (uid == null) return right(null);
    final prefs = await SharedPreferences.getInstance();
    try {
      final doc = await _doc(uid).get().timeout(const Duration(seconds: 5));
      final name = doc.data()?['memberName'] as String?;
      if (name == null) {
        await prefs.remove(_cacheKey(uid));
      } else {
        await prefs.setString(_cacheKey(uid), name);
      }
      return right(name);
    } on Object {
      // Offline or slow: the last value seen on this device.
      return right(prefs.getString(_cacheKey(uid)));
    }
  }

  @override
  Future<Either<Failure, Unit>> setMemberName(String name) async {
    final uid = _currentUid();
    if (uid == null) return left(const Failure.unexpected('Not signed in'));
    try {
      await _doc(uid).update({'memberName': name});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(uid), name);
      return right(unit);
    } on FirebaseException catch (e) {
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
