import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/core/utils/money_formatter.dart';

/// Push notifications format amounts on the server (services/crm/src/money.ts).
/// Both sides run these vectors so a notification shows the amount exactly as
/// the app does (R-9 AC10).
void main() {
  test('formatMoney matches the shared vectors', () {
    final vectors = jsonDecode(
      File('services/crm/test/money_vectors.json').readAsStringSync(),
    ) as List<dynamic>;
    for (final v in vectors.cast<Map<String, dynamic>>()) {
      expect(
        formatMoney(v['cents'] as int, v['currency'] as String),
        v['text'],
        reason: '${v['cents']} ${v['currency']}',
      );
    }
  });
}
