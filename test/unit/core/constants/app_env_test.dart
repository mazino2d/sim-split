import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/constants/app_env.dart';
import 'package:simsplit/core/constants/auth_constants.dart';
import 'package:simsplit/core/constants/invite_constants.dart';

void main() {
  group('AppEnv.parse', () {
    test('defaults to prd when APP_ENV is empty', () {
      expect(AppEnv.parse(''), AppEnv.prd);
    });

    test('reads dev and prd', () {
      expect(AppEnv.parse('dev'), AppEnv.dev);
      expect(AppEnv.parse('prd'), AppEnv.prd);
    });

    test('rejects any other value instead of guessing a backend', () {
      expect(() => AppEnv.parse('prod'), throwsArgumentError);
      expect(() => AppEnv.parse('Dev'), throwsArgumentError);
    });
  });

  test('a build without APP_ENV is prd', () {
    expect(appEnv, AppEnv.prd);
  });

  test('invite links open the web app of the same environment', () {
    expect(inviteLinkBaseFor(AppEnv.prd).toString(),
        'https://simsplit.web.app/join');
    expect(inviteLinkBaseFor(AppEnv.dev).toString(),
        'https://simsplit-as-se1-dev.web.app/join');
  });

  test('prd keeps the production Google sign-in client', () {
    expect(googleServerClientIdFor(AppEnv.prd), startsWith('113980760756-'));
    expect(googleServerClientIdFor(AppEnv.dev),
        isNot(googleServerClientIdFor(AppEnv.prd)));
  });
}
