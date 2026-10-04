import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:simsplit/domain/entities/auth_user.dart';

class AuthUserMapper {
  const AuthUserMapper();

  AuthUser toEntity(fb.User user) => AuthUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
      );
}
