import 'package:fpdart/fpdart.dart';
import 'package:simsplit/domain/failures/core_failure.dart';
import 'package:simsplit/domain/failures/member_failure.dart';
import 'package:simsplit/domain/repositories/user_profile_repository.dart';
import 'package:simsplit/domain/use_cases/use_case.dart';

/// The name the account goes by in groups, set once in Settings (#112).
class GetMyName implements AsyncUseCase<String?, NoParams> {
  const GetMyName({required UserProfileRepository userProfileRepository})
      : _profiles = userProfileRepository;

  final UserProfileRepository _profiles;

  @override
  Future<Either<Failure, String?>> call(NoParams params) =>
      _profiles.getMemberName();
}

/// Saves the name the account goes by in groups (#112). It only fills new
/// forms: "me" keeps its name in groups that already exist.
class SetMyName implements AsyncUseCase<Unit, String> {
  const SetMyName({required UserProfileRepository userProfileRepository})
      : _profiles = userProfileRepository;

  final UserProfileRepository _profiles;

  @override
  Future<Either<Failure, Unit>> call(String params) async {
    final name = params.trim();
    if (name.isEmpty) return left(const MemberFailure.nameEmpty());
    if (name.length > maxMemberNameLength) {
      return left(const MemberFailure.nameTooLong());
    }
    return _profiles.setMemberName(name);
  }
}

/// The name to prefill for "me" on a new group or when joining one (#112):
/// the account's "My name", then the name last used on this device, then
/// the Google account name. Null when there is none.
String? prefillMyName({
  String? accountName,
  String? lastUsedOnDevice,
  String? displayName,
}) =>
    [accountName, lastUsedOnDevice, displayName]
        .map((n) => n?.trim())
        .firstWhere((n) => n != null && n.isNotEmpty, orElse: () => null);
