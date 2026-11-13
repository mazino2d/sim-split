import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/utils/in_app_browser.dart';

void main() {
  test('recognises chat and social in-app browsers (#109)', () {
    const cases = {
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
          'ZaloTheme/light ZaloLanguage/vn': 'Zalo',
      'Mozilla/5.0 (Linux; Android 14; SM-A546E Build/UP1A; wv) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
          'Chrome/141.0.0.0 Mobile Safari/537.36 Zalo android': 'Zalo',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22B83 '
          '[FBAN/FBIOS;FBAV/490.0.0.0;FBBV/1]': 'Facebook',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22B83 '
          '[FBAN/MessengerForiOS;FBAV/480.0]': 'Messenger',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22B83 '
          'Instagram 350.0.0': 'Instagram',
    };
    cases.forEach((ua, app) => expect(inAppBrowserName(ua), app, reason: ua));
  });

  test('regular browsers are not in-app', () {
    for (final ua in [
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 '
          'Mobile/15E148 Safari/604.1',
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/141.0.0.0 Mobile Safari/537.36',
      '',
    ]) {
      expect(inAppBrowserName(ua), isNull, reason: ua);
    }
  });
}
