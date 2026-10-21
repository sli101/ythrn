import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// ترميز JSON: كل حدث وكل حقل في الملف يعود كما كان.
void main() {
  final t = DateTime(2026, 3, 5, 11, 30);

  test('كل أنواع الأحداث تعود بعد الترميز وفكّه', () {
    final events = <FiqhEvent>[
      BloodStart(t, props: BloodProps.wajid),
      BloodStart(t, isBlood: const Tri.unknown(UnknownKind.dontRemember), spots: true),
      BloodStop(t),
      FullStop(t, const Duration(minutes: 45)),
      PropsChange(t, BloodProps.faqid),
      KursufTest(t, KursufResult.stained),
      InnerContinuity(t, const Tri.known(true)),
      Expectation(t, ExpectationKind.willReturnBeforeTen, const Tri.unknown(UnknownKind.dontUnderstand)),
      IsEarlyHabit(t, const Tri.known(false)),
      Ghusl(t),
      RamadanNote(t, isRamadan: true),
      Birth(t, twins: true, cesarean: true),
      Miscarriage(t, stage: MiscarriageStage.formed, ensouled: const Tri.known(true)),
      Miscarriage(t),
      IstihadhaTest(t, IstihadhaLevel.kathira, flow: IstihadhaFlow.intermittent),
      VirginityTest(t, VirginityTestResult.ringed),
      SourceNote(t, BloodSource.doubtVirginityOrHayd),
    ];
    for (final e in events) {
      final json = jsonDecode(jsonEncode(FiqhCodec.encodeEvent(e))) as Map<String, Object?>;
      final back = FiqhCodec.decodeEvent(json);
      expect(back.runtimeType, e.runtimeType, reason: json.toString());
      expect(back.at, e.at);
      expect(FiqhCodec.encodeEvent(back), FiqhCodec.encodeEvent(e), reason: json.toString());
    }
  });

  test('الملف الشخصي يعود بكل حقوله', () {
    final p = FiqhProfile(
      habit: HabitState(
        type: WomanType.nasC,
        anchorDate: t,
        count: 6,
        deficient: const DeficientBounds(min: 4, max: 8),
        memory: const NasiyaMemory(countMin: 3, countMax: 9, knownDays: [2, 3]),
        origin: HabitOrigin.declared,
        history: [JudgedCycle(start: t, end: t.add(const Duration(days: 6)), bloodDays: 5.5)],
      ),
      birth: Tri.known(DateTime(1995, 2, 1)),
      approxAgeYears: const Tri.unknown(UnknownKind.dontUnderstand),
      pregnant: const Tri.known(false),
      lastBloodEnd: Tri.known(t),
      kinCount: const Tri.known(7),
      kinConditionsMet: const Tri.known(true),
      chosenCount: const Tri.unknown(UnknownKind.dontRemember),
      nasiyaHalfMonth: 2,
      knownTimeDays: [t],
      timeWindow: (t, t.add(const Duration(days: 3))),
      ramadan: [(t, t.add(const Duration(days: 30)))],
    );
    final json = jsonDecode(jsonEncode(FiqhCodec.encodeProfile(p))) as Map<String, Object?>;
    final back = FiqhCodec.decodeProfile(json);
    expect(FiqhCodec.encodeProfile(back), FiqhCodec.encodeProfile(p));
    expect(back.habit.type, WomanType.nasC);
    expect(back.habit.memory?.knownDays, [2, 3]);
    expect(back.habit.history.single.bloodDays, 5.5);
    expect(back.birth, Tri.known(DateTime(1995, 2, 1)));
    expect(back.approxAgeYears, const Tri.unknown(UnknownKind.dontUnderstand));
    expect(back.timeWindow, (t, t.add(const Duration(days: 3))));
  });

  test('ملف فارغ يُفكّ إلى الافتراضيات', () {
    final back = FiqhCodec.decodeProfile(const {});
    expect(back.habit.type, WomanType.mub);
    expect(back.birth.isKnown, isFalse);
    expect(back.ramadan, isEmpty);
  });
}
