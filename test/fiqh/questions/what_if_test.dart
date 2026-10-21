import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// «ماذا لو؟»: تبديل مجهول واحد على نسخة من المدخلات بلا حفظ، وعرض الفرق.
void main() {
  const clock = FixedDayClock();
  final time = FiqhTime(clock);
  final machine = QuestionMachine(time);
  final whatIf = WhatIf(machine);
  final day0 = DateTime(2026, 3, 1);

  test('مبتدئة ترى دمًا بلا صفات: بدائل سؤال الصفات تغيّر الحكم ولا تمسّ الأصل', () {
    final start = clock.fajr(day0).add(const Duration(hours: 2));
    final s = QuestionSession(
      profile: FiqhProfile(habit: const HabitState(type: WomanType.mub, origin: HabitOrigin.declared), birth: Tri.known(DateTime(1996))),
      events: [BloodStart(start)],
      now: start.add(const Duration(hours: 3)),
      settled: const {'womanType', 'birthDate'},
    );
    final items = whatIf.items(s);
    expect(items, isNotEmpty);
    final props = items.firstWhere((i) => i.id == 'bloodProps');
    expect(props.variants.length, 2);
    final wajid = props.variants.first;
    expect(wajid.stateAt(s.now), DayState.hayd);
    expect(wajid.changesAnything, isTrue);
    expect(wajid.diffs.first.base, DayState.jam3M);
    expect(wajid.diffs.first.variant, DayState.hayd);
    // الأصل لم يتغير.
    expect(s.events.length, 1);
    expect(machine.evaluate(s).at(s.now)?.state, DayState.jam3M);
  });

  test('مجاهيل الملف (الحمل، القرشية، الاستئصال) تُعرض فقط إذا لم تُجَب', () {
    final s = QuestionSession(
      profile: FiqhProfile(
        habit: const HabitState(type: WomanType.vw, count: 7, origin: HabitOrigin.declared),
        birth: Tri.known(DateTime(1996)),
        pregnant: const Tri.known(false),
      ),
      events: const [],
      now: clock.fajr(day0),
      settled: const {'womanType', 'habitStart', 'habitCount', 'birthDate', 'lastBloodEnd'},
    );
    final items = whatIf.items(s);
    final ids = items.map((i) => i.id).toList();
    expect(ids, isNot(contains('pregnant')));
    expect(ids, containsAll(['isQurashi', 'hysterectomy']));
    for (final item in items) {
      expect(item.variants.length, 2);
      // لا دم: لا أثر لأي بديل.
      expect(item.variants.every((v) => !v.changesAnything), isTrue);
    }
  });

  test('الفرق بين ناتجين يُدمج في مدد متصلة', () {
    final a = EngineResult(
      intervals: [StateInterval(day0, day0.add(const Duration(days: 3)), DayState.hayd, const [])],
      segments: const [],
      unsupported: const [],
      judgedEnd: null,
    );
    final b = EngineResult(
      intervals: [
        StateInterval(day0, day0.add(const Duration(days: 1)), DayState.jam3M, const []),
        StateInterval(day0.add(const Duration(days: 1)), day0.add(const Duration(days: 3)), DayState.jam3M, const []),
      ],
      segments: const [],
      unsupported: const [],
      judgedEnd: null,
    );
    final d = WhatIf.diff(a, b, day0);
    expect(d.length, 1);
    expect(d.single.from, day0);
    expect(d.single.to, day0.add(const Duration(days: 3)));
    expect(d.single.base, DayState.hayd);
    expect(d.single.variant, DayState.jam3M);
  });
}
