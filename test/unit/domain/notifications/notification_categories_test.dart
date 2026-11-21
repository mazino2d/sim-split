import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:yaml/yaml.dart';

/// R-9: `crm/categories.yaml` is the source of every notification category.
/// The app's enum, its defaults and its EN/VI names and descriptions (the
/// switches in Settings → Notifications and the Android channels) must say
/// exactly the same.
void main() {
  final yaml = loadYaml(File('crm/categories.yaml').readAsStringSync()) as List;
  final arb = {
    for (final lang in ['en', 'vi'])
      lang: jsonDecode(File('lib/core/l10n/app_$lang.arb').readAsStringSync())
          as Map<String, dynamic>,
  };

  String pascal(String id) =>
      id.split('_').map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join();

  test('the app has exactly the categories of crm/categories.yaml', () {
    expect(NotificationCategory.values.map((c) => c.id).toList(),
        yaml.map((c) => (c as YamlMap)['id']).toList());
  });

  test('defaults match crm/categories.yaml', () {
    for (final entry in yaml.cast<YamlMap>()) {
      final category = NotificationCategory.fromId(entry['id'] as String)!;
      expect(category.defaultOn, entry['default'] == 'on', reason: category.id);
    }
  });

  test('names and descriptions in both languages match crm/categories.yaml',
      () {
    for (final entry in yaml.cast<YamlMap>()) {
      final key = 'notificationCategory${pascal(entry['id'] as String)}';
      for (final lang in ['en', 'vi']) {
        expect(arb[lang]![key], (entry['name'] as YamlMap)[lang],
            reason: '$key ($lang)');
        expect(arb[lang]!['${key}Description'],
            (entry['description'] as YamlMap)[lang],
            reason: '${key}Description ($lang)');
      }
    }
  });

  test('preference keys are the camelCase ids', () {
    for (final category in NotificationCategory.values) {
      final p = pascal(category.id);
      expect(category.prefKey, '${p[0].toLowerCase()}${p.substring(1)}');
    }
  });
}
