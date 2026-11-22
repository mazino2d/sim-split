import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simsplit/domain/entities/notifications/notification_category.dart';
import 'package:simsplit/domain/entities/notifications/notification_prefs.dart';
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

  group('group activity events (R-9 AC26)', () {
    final category =
        yaml.cast<YamlMap>().firstWhere((c) => c['id'] == 'group_activity');
    final events = (category['events'] as YamlList).cast<YamlMap>();

    test('the app has exactly the events of crm/categories.yaml', () {
      expect(ActivityEvent.values.map((e) => e.id).toList(),
          events.map((e) => e['id']).toList());
    });

    test('defaults match', () {
      for (final entry in events) {
        final event =
            ActivityEvent.values.firstWhere((e) => e.id == entry['id']);
        expect(event.defaultOn, entry['default'] == 'on', reason: event.id);
      }
    });

    test('names in both languages match', () {
      for (final entry in events) {
        final key = 'notificationEvent${pascal(entry['id'] as String)}';
        for (final lang in ['en', 'vi']) {
          expect(arb[lang]![key], (entry['name'] as YamlMap)[lang],
              reason: '$key ($lang)');
        }
      }
    });

    test('preference keys in activityEvents are the camelCase ids', () {
      for (final event in ActivityEvent.values) {
        final p = pascal(event.id);
        expect(event.name, '${p[0].toLowerCase()}${p.substring(1)}');
      }
    });

    test('only group activity has events', () {
      for (final entry in yaml.cast<YamlMap>()) {
        if (entry['id'] != 'group_activity') {
          expect(entry['events'], isNull, reason: entry['id'] as String);
        }
      }
    });
  });

  test('preference keys are the camelCase ids', () {
    for (final category in NotificationCategory.values) {
      final p = pascal(category.id);
      expect(category.prefKey, '${p[0].toLowerCase()}${p.substring(1)}');
    }
  });
}
