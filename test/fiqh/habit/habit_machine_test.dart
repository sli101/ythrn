import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// اختبارات آلة حالة العادة (`docs/SPEC.md` §٤). الأيام بأرقام سيناريو: اليوم ١ = 2026-03-01.
void main() {
  const machine = HabitMachine();
  final base = DateTime(2026, 3, 1, 4, 30);
  DateTime day(int n) => base.add(Duration(days: n - 1));
  JudgedCycle cycle(int start, double bloodDays, {int? end}) => JudgedCycle(
        start: day(start),
        end: end != null ? day(end).add(const Duration(hours: 14)) : day(start).add(Duration(minutes: (bloodDays * 1440).round())),
        bloodDays: bloodDays,
      );
  HabitState fold(HabitState s, List<JudgedCycle> cycles) {
    var state = s;
    for (final c in cycles) {
      state = machine.update(state, c).value;
    }
    return state;
  }

  int scenarioDay(DateTime t) => t.difference(base).inDays + 1;

  group('H4-01 الثبوت بمرتين', () {
    test('وقتًا وعددًا', () {
      final s = fold(HabitState.initial, [cycle(-59, 7), cycle(-29, 7)]);
      expect(s.type, WomanType.vw);
      expect(s.count, 7);
      expect(scenarioDay(s.expectedNextStart!), 1);
    });
    test('وقتًا فقط', () {
      expect(fold(HabitState.initial, [cycle(-59, 7), cycle(-29, 5)]).type, WomanType.v);
    });
    test('عددًا فقط', () {
      final s = fold(HabitState.initial, [cycle(-59, 5), cycle(-15, 5)]);
      expect(s.type, WomanType.w);
      expect(s.count, 5);
      expect(s.expectedNextStart, isNull);
    });
    test('لا هذا ولا ذاك → مضطربة', () {
      expect(fold(HabitState.initial, [cycle(-59, 7), cycle(-15, 4)]).type, WomanType.mud);
    });
    test('حيضة واحدة لا تثبت شيئًا', () {
      expect(fold(HabitState.initial, [cycle(-29, 7)]).type, WomanType.mub);
    });
  });

  group('H4-04 البقاء والتبدل والزوال', () {
    final established = fold(HabitState.initial, [cycle(-89, 7), cycle(-59, 7)]);

    test('حيضة واحدة مخالفة لا تزيل العادة (ج م٥٥٠) — تصحيح المالك', () {
      final s = machine.update(established, cycle(-29, 4));
      expect(s.value.type, WomanType.vw);
      expect(s.value.count, 7);
      expect(s.trace.any((r) => r.note?.contains('٥٥٠') ?? false), isTrue);
    });
    test('تغيّر العدد مرة ثم عودته → باقية (ج م٥٥١)', () {
      final s = fold(established, [cycle(-29, 9), cycle(1, 7)]);
      expect(s.type, WomanType.vw);
      expect(s.count, 7);
    });
    test('حيضتان متماثلتان مخالفتان → تبدلت (ج م٥٤٩)', () {
      final old = fold(HabitState.initial, [cycle(-119, 5), cycle(-89, 5)]);
      final s = fold(old, [cycle(-50, 7), cycle(-20, 7)]);
      expect(s.type, WomanType.vw);
      expect(s.count, 7);
      expect(scenarioDay(s.expectedNextStart!), 10);
    });
    test('حيضتان مخالفتان مختلفتان → زالت إلى مضطربة (ج م٥٥١)', () {
      final old = fold(HabitState.initial, [cycle(-119, 5), cycle(-89, 5)]);
      final s = fold(old, [cycle(-50, 8), cycle(-25, 4)]);
      expect(s.type, WomanType.mud);
      expect(s.count, isNull);
      expect(s.anchorDate, isNull);
    });
    test('اختلفتا وقتًا فقط واتفقتا عددًا → عددية (ج م٥٥١)', () {
      final old = fold(HabitState.initial, [cycle(-119, 5), cycle(-89, 5)]);
      final s = fold(old, [cycle(-50, 5), cycle(-12, 5)]);
      expect(s.type, WomanType.w);
      expect(s.count, 5);
    });
    test('الموافقة تعيد الإرساء فلا يتراكم الانحراف', () {
      final s = fold(established, [cycle(-28, 7), cycle(3, 7), cycle(34, 7)]);
      expect(s.type, WomanType.vw);
      expect(scenarioDay(s.expectedNextStart!), 64);
    });
  });

  group('التصريح الابتدائي', () {
    test('عادة مصرَّح بها ثم حيضة مخالفة واحدة → باقية', () {
      final declared = HabitState(
        type: WomanType.vw,
        anchorDate: day(1),
        count: 6,
        origin: HabitOrigin.declared,
      );
      final s = machine.update(declared, cycle(-29, 9)).value;
      expect(s.type, WomanType.vw);
      expect(s.count, 6);
      expect(s.origin, HabitOrigin.declared);
    });
    test('عادة مصرَّح بها ثم حيضتان متماثلتان مخالفتان → تبدلت', () {
      final declared = HabitState(type: WomanType.vw, anchorDate: day(1), count: 6, origin: HabitOrigin.declared);
      final s = fold(declared, [cycle(1, 9), cycle(31, 9)]);
      expect(s.type, WomanType.vw);
      expect(s.count, 9);
      expect(s.origin, HabitOrigin.derived);
    });
  });

  group('التسامح العرفي', () {
    test('ربع يوم في العدد لا يضر (ج م٥٣٩)', () {
      final s = fold(HabitState.initial, [cycle(-59, 7), cycle(-29, 7.2)]);
      expect(s.type, WomanType.vw);
      expect(s.count, 7);
    });
    test('نصف يوم في العدد يضر', () {
      expect(fold(HabitState.initial, [cycle(-59, 7), cycle(-29, 7.5)]).type, WomanType.v);
    });
    test('الفاصل ٢٨ و٣١ شهر؛ ٢٤ ليس شهرًا (H0-04)', () {
      expect(fold(HabitState.initial, [cycle(-59, 6), cycle(-31, 6)]).type, WomanType.vw);
      expect(fold(HabitState.initial, [cycle(-54, 6), cycle(-30, 6)]).type, WomanType.w);
    });
    test('الوقتية بآخرها (H4-09)', () {
      final s = fold(HabitState.initial, [cycle(-62, 9, end: -54), cycle(-29, 6, end: -24)]);
      expect(s.type, WomanType.v);
      expect(s.anchor, HabitAnchor.end);
    });
  });

  test('الأثر يحمل معرّفات القواعد', () {
    final r = machine.update(fold(HabitState.initial, [cycle(-59, 7)]), cycle(-29, 7));
    expect(r.trace.map((t) => t.id), containsAll(['H4-01', 'H0-04']));
  });
}
