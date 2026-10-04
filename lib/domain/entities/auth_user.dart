import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_user.freezed.dart';

/// The signed-in account (R-3). Identity comes from the sign-in provider;
/// the app never asks for a profile.
@freezed
sealed class AuthUser with _$AuthUser {
  const factory AuthUser({
    required String uid,
    String? email,
    String? displayName,
  }) = _AuthUser;
}
