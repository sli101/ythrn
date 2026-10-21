import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'golden_case.dart';
import 'package:ythrn/fiqh/golden/golden_runner.dart';

/// الاختبارات الذهبية: المرحلة الحالية تتحقق من بنية الحالات وثبات معرّفاتها
/// وإحالاتها إلى قواعد موجودة في `assets/fiqh/rules.json`.
/// تشغيل الحالات على المحرك يُضاف في المرحلة ٢ (انظر المجموعة المعلَّقة أدناه).
void main() {
  final cases = loadGoldenCases();
  final ruleIds = _loadRuleIds();

  group('بنية الحالات الذهبية', () {
    test('توجد حالات في كل مجموعة', () {
      final groups = cases.map((c) => c.group).toSet();
      expect(groups, containsAll(['text', 'habit', 'time', 'unknown']));
      expect(cases.length, greaterThanOrEqualTo(50));
    });

    test('المعرّفات فريدة ومطابقة للنسق', () {
      final ids = cases.map((c) => c.id).toList();
      expect(ids.toSet().length, ids.length);
      final re = RegExp(r'^G-(TXT|HAB|TIME|UNK|AUDIT|NIF|IST|ELG|DUT)-\d{2,3}$');
      for (final id in ids) {
        expect(re.hasMatch(id), isTrue, reason: id);
      }
    });

    for (final c in cases) {
      test('${c.id} ${c.title}', () {
        expect(goldenWomanTypes, contains(c.womanType), reason: 'womanType');
        expect(c.timeline, isNotEmpty);
        expect(c.expected, isNotEmpty);
        for (final item in c.timeline) {
          final days = item['days'] as String?;
          final at = item['at'] as String?;
          expect(days != null || at != null, isTrue, reason: 'timeline item');
          if (days != null) {
            expect(GoldenCase.isValidRange(days), isTrue, reason: days);
          }
          if (at != null) {
            expect(GoldenCase.isValidInstant(at), isTrue, reason: at);
          }
        }
        for (final e in c.expected) {
          final days = e['days'] as String?;
          if (days != null) {
            expect(GoldenCase.isValidRange(days), isTrue, reason: days);
            expect(goldenStates, contains(e['state']), reason: 'state');
            expect(GoldenCase.dayRangeEnd(days), lessThanOrEqualTo(c.lastDay));
          } else {
            expect(e['assert'], isA<String>());
          }
        }
        for (final rid in c.rules) {
          final base = rid.replaceFirst(RegExp(r'[a-z]$'), '');
          expect(
            ruleIds.contains(rid) || ruleIds.any((r) => r.startsWith(base)),
            isTrue,
            reason: 'قاعدة غير موجودة: $rid',
          );
        }
      });
    }
  });

  group('تشغيل الحالات على الشرائح المكتوبة (الزمن، آلة العادة)', () {
    final pendingByCase = <String, List<String>>{};
    for (final c in cases) {
      test('${c.id} ${c.title}', () {
        final r = runGoldenCase(c);
        expect(r.failures.toList(), isEmpty, reason: '${c.id}\n${r.failures.join('\n')}');
        if (r.pending.isNotEmpty) pendingByCase[c.id] = r.pending;
      });
    }
    tearDownAll(() {
      final total = cases.fold<int>(0, (n, c) => n + c.expected.length);
      final pending = pendingByCase.values.fold<int>(0, (n, l) => n + l.length);
      final byReason = <String, int>{};
      for (final l in pendingByCase.values) {
        for (final p in l) {
          final m = RegExp(r'\(([^)]*)\)$').firstMatch(p);
          final reason = m?.group(1) ?? p.split(' ').first;
          byReason[reason] = (byReason[reason] ?? 0) + 1;
        }
      }
      // ignore: avoid_print
      print('الاختبارات الذهبية: $total توقعًا، منها $pending معلَّق على شرائح لاحقة في ${pendingByCase.length} حالة. '
          'بحسب السبب: ${byReason.entries.map((e) => "${e.key}=${e.value}").join("، ")}');
    });
  });
}

Set<String> _loadRuleIds() {
  final ids = <String>{};
  for (final path in ['assets/fiqh/rules.json', 'assets/fiqh/deferred-istihbabi.json']) {
    final doc = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    for (final r in doc['rules'] as List<dynamic>) {
      ids.add((r as Map<String, dynamic>)['id'] as String);
    }
  }
  return ids;
}
