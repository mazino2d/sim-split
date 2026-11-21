import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/domain/entities/notifications/notification_open.dart';

void main() {
  const g = '0b6f1c2e-4a5d-4e8f-9a1b-2c3d4e5f6a7b';
  const e = '7c9e6679-7425-40de-944b-e07fc1f90ae7';

  test('accepts the three routes the sender uses (R-9 AC8)', () {
    expect(parseNotificationRoute('/groups/$g'), '/groups/$g');
    expect(parseNotificationRoute('/groups/$g/expenses/$e'),
        '/groups/$g/expenses/$e');
    expect(parseNotificationRoute('/groups/$g/settle'), '/groups/$g/settle');
  });

  test('ignores anything else', () {
    for (final route in [
      null,
      '',
      '/',
      'groups/$g',
      '/groups/',
      '/groups/g1',
      '/groups/${g.toUpperCase()}',
      '/groups/$g/',
      '/groups/$g/edit',
      '/groups/$g/settlements/$e',
      '/groups/$g/expenses/$e/edit',
      '/groups/$g/expenses/e1',
      '/groups/$g/settle?x=1',
      '/settings',
      '/join/abc',
      'https://evil.example/groups/$g',
      '//evil.example/groups/$g',
      '/groups/$g/../settings',
    ]) {
      expect(parseNotificationRoute(route), isNull, reason: route);
    }
  });
}
