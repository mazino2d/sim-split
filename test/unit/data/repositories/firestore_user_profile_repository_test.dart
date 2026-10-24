import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/data/repositories/firestore_user_profile_repository.dart';
import 'package:simsplit/domain/entities/auth_user.dart';

void main() {
  late FakeFirebaseFirestore cloud;
  late FirestoreUserProfileRepository repository;
  const user = AuthUser(uid: 'u1', email: 'an@example.com', displayName: 'An');

  setUp(() {
    cloud = FakeFirebaseFirestore();
    repository = FirestoreUserProfileRepository(
        firestore: cloud, currentUid: () => 'u1');
  });

  test('the first sign-in stores the profile and the agreement (R-4 AC7)',
      () async {
    final result = await repository.recordAgreement(user, '2026-10-24');

    expect(result.isRight(), isTrue);
    final data = (await cloud.doc('users/u1').get()).data()!;
    expect((data['displayName'], data['email']), ('An', 'an@example.com'));
    expect((data['consent'] as Map)['policyVersion'], '2026-10-24');
  });

  test('later sign-ins keep the first agreement', () async {
    await repository.recordAgreement(user, '2026-10-24');
    await repository.recordAgreement(user, '2027-01-01');

    final data = (await cloud.doc('users/u1').get()).data()!;
    expect((data['consent'] as Map)['policyVersion'], '2026-10-24');
  });

  test('deleting the profile removes the document', () async {
    await repository.recordAgreement(user, '2026-10-24');
    await repository.deleteProfile();

    expect((await cloud.doc('users/u1').get()).exists, isFalse);
  });
}
