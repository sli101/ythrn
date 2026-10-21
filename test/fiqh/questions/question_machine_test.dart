import 'package:flutter_test/flutter_test.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// آلة الأسئلة (`docs/SPEC.md` §٦، §١٠): سؤال واحد في كل مرة بالأثر،
/// ولكل «لا أعلم» بنوعيه مسار، والمسار الشائع لا يتجاوز سبعة أسئلة.
void main() {
  const clock = FixedDayClock();
  final time = FiqhTime(clock);
  final machine = QuestionMachine(time);
  final base = DateTime(2026, 3, 1);

  DateTime day(int d) => base.add(Duration(days: d - 1));
  DateTime fajr(int d) => clock.fajr(day(d));
  DateTime at(int d, int hour, [int minute = 0]) => day(d).add(Duration(hours: hour, minutes: minute));

  /// مجموعة التنصيب المسوّاة: مستخدمة أكملت التهيئة.
  const onboarded = {'birthDate', 'lastBloodEnd'};

  HabitState vw({int start = 1, int count = 7}) => HabitState(type: WomanType.vw, anchorDate: fajr(start), count: count, origin: HabitOrigin.declared);

  QuestionSession session({
    FiqhProfile profile = const FiqhProfile(),
    List<FiqhEvent> events = const [],
    required DateTime now,
    Set<String> settled = const {},
  }) =>
      QuestionSession(profile: profile, events: events, now: now, settled: settled);

  /// يجيب عن سلسلة أسئلة ويعيد الجلسة، مؤكدًا معرّف كل سؤال في طريقه.
  QuestionSession walk(QuestionSession s, List<(String, Reply)> path) {
    for (final (id, reply) in path) {
      final q = machine.next(s);
      expect(q?.id, id, reason: 'المتوقع $id والناتج ${q?.id}');
      s = machine.apply(s, q!, reply);
    }
    return s;
  }

  DayState? stateAt(QuestionSession s, DateTime t) => machine.evaluate(s).at(t)?.state;

  group('التنصيب: نوع العادة أولًا ثم معطياتها ثم الميلاد', () {
    test('ذات الوقتية والعددية: أربعة أسئلة ثم لا شيء', () {
      var s = session(now: fajr(1));
      s = walk(s, [
        ('womanType', const Reply.value('VW')),
        ('habitStart', Reply.value(day(-29))),
        ('habitCount', const Reply.value(7)),
        ('birthDate', Reply.value(DateTime(1996, 1, 1))),
      ]);
      expect(machine.next(s), isNull);
      expect(s.profile.habit.type, WomanType.vw);
      expect(s.profile.habit.count, 7);
      expect(s.profile.habit.anchorDate, clock.fajr(day(-29)));
      expect(s.profile.habit.origin, HabitOrigin.declared);
    });

    test('«لا أفهم» نوع العادة → سلّم المشاهدة: العدد نفسه والوقت نفسه → وقتية وعددية', () {
      var s = session(now: fajr(1));
      s = walk(s, [
        ('womanType', Reply.dontUnderstand),
        ('firstTime', const Reply.value(false)),
        ('sameCount', const Reply.value(true)),
        ('sameTime', const Reply.value(true)),
      ]);
      expect(s.ladder, isNull);
      expect(s.profile.habit.type, WomanType.vw);
      expect(machine.next(s)?.id, 'habitStart');
    });

    test('سلّم المشاهدة: أول مرة → مبتدئة بلا أسئلة عادة', () {
      var s = session(now: fajr(1));
      s = walk(s, [
        ('womanType', Reply.dontUnderstand),
        ('firstTime', const Reply.value(true)),
      ]);
      expect(s.profile.habit.type, WomanType.mub);
      expect(s.profile.habit.origin, HabitOrigin.declared);
      expect(machine.next(s)?.id, 'birthDate');
    });

    test('سلّم المشاهدة: العدد نفسه فقط → عددية؛ الوقت فقط → وقتية؛ لا شيء → مضطربة', () {
      for (final (c, t, type) in [(true, false, WomanType.w), (false, true, WomanType.v), (false, false, WomanType.mud)]) {
        final s = walk(session(now: fajr(1)), [
          ('womanType', Reply.dontUnderstand),
          ('firstTime', const Reply.value(false)),
          ('sameCount', Reply.value(c)),
          ('sameTime', Reply.value(t)),
        ]);
        expect(s.profile.habit.type, type);
      }
    });

    test('«لا أتذكر» نوع العادة → ناسية بصورها مع الذاكرة الجزئية', () {
      // نسيت العدد وأذكر الوقت: وقتها ثم حدّا العدد.
      var s = walk(session(now: fajr(1)), [
        ('womanType', Reply.dontRemember),
        ('nasiyaForgot', const Reply.value('count')),
        ('habitStart', Reply.value(day(-29))),
        ('nasiyaCountMin', const Reply.value(4)),
        ('nasiyaCountMax', Reply.dontRemember),
      ]);
      expect(s.profile.habit.type, WomanType.nasC);
      expect(s.profile.habit.memory?.countMin, 4);
      expect(s.profile.habit.memory?.countMax, isNull);
      expect(machine.next(s)?.id, 'birthDate');

      // نسيت الوقت وأذكر العدد: العدد ثم نصف الشهر.
      s = walk(session(now: fajr(1)), [
        ('womanType', Reply.dontRemember),
        ('nasiyaForgot', const Reply.value('time')),
        ('habitCount', const Reply.value(6)),
        ('nasiyaHalfMonth', const Reply.value('first')),
      ]);
      expect(s.profile.habit.type, WomanType.nasT);
      expect(s.profile.habit.count, 6);
      expect(s.profile.nasiyaHalfMonth, 1);
      expect(machine.next(s)?.id, 'birthDate');

      // نسيتهما: الحدان ثم نصف الشهر، وكلها «لا أتذكر».
      s = walk(session(now: fajr(1)), [
        ('womanType', Reply.dontRemember),
        ('nasiyaForgot', const Reply.value('both')),
        ('nasiyaCountMin', Reply.dontRemember),
        ('nasiyaCountMax', Reply.dontRemember),
        ('nasiyaHalfMonth', Reply.dontRemember),
      ]);
      expect(s.profile.habit.type, WomanType.nasB);
      expect(machine.next(s)?.id, 'birthDate');
    });

    test('ذات عادة نسيت وقتها أو عددها → ناسية الوقت أو العدد', () {
      var s = walk(session(now: fajr(1)), [
        ('womanType', const Reply.value('VW')),
        ('habitStart', Reply.dontRemember),
      ]);
      expect(s.profile.habit.type, WomanType.nasT);
      expect(machine.next(s)?.id, 'habitCount');
      s = walk(s, [('habitCount', Reply.dontRemember)]);
      expect(s.profile.habit.type, WomanType.nasB);

      s = walk(session(now: fajr(1)), [
        ('womanType', const Reply.value('VW')),
        ('habitStart', Reply.value(day(-29))),
        ('habitCount', Reply.dontRemember),
      ]);
      expect(s.profile.habit.type, WomanType.nasC);
      expect(s.profile.habit.anchorDate, isNotNull);
    });

    test('الميلاد: «لا أتذكر» → سن تقريبي؛ على حافة التسع يُعدّ شكًّا', () {
      var s = walk(session(now: fajr(1), settled: {'womanType'}), [
        ('birthDate', Reply.dontRemember),
        ('approxAge', const Reply.value(9)),
      ]);
      expect(s.profile.approxAgeYears, const Tri.known(9.0));
      expect(s.profile.eligibilityAt(fajr(1)).doubtsNine, isTrue);
      expect(machine.next(s), isNull);

      s = walk(session(now: fajr(1), settled: {'womanType'}), [
        ('birthDate', Reply.dontUnderstand),
        ('approxAge', const Reply.value(30)),
      ]);
      expect(s.profile.eligibilityAt(fajr(1)).ageLunarYears, const Tri.known(30.0));
      expect(s.profile.eligibilityAt(fajr(1)).doubtsNine, isFalse);
    });

    test('التخطي يسوّي السؤال وينتقل إلى التالي', () {
      var s = session(now: fajr(1));
      final q = machine.next(s)!;
      expect(q.id, 'womanType');
      s = machine.apply(s, q, Reply.skip);
      expect(machine.next(s)?.id, 'birthDate');
    });
  });

  group('المسار الشائع: ذات عادة في وقتها', () {
    test('الحيضة كلها ثلاثة أسئلة: احتمال البقاء، القطنة، العود', () {
      var s = session(profile: FiqhProfile(habit: vw()), events: [BloodStart(fajr(1))], now: at(1, 12), settled: onboarded);
      // في وقتها: حيض بالرؤية بلا سؤال عن الصفات (H5-05).
      expect(machine.next(s), isNull);
      expect(stateAt(s, at(1, 12)), DayState.hayd);

      // انقطع يوم ٥: الحكم معلَّق على الاستبراء.
      final stop = at(5, 12);
      s = s.addEvent(BloodStop(stop)).copyWith(now: at(5, 13));
      expect(stateAt(s, at(5, 13)), DayState.pending);
      var asked = 0;
      s = walk(s, [
        ('innerContinuity', const Reply.value(true)),
        ('kursufTest', const Reply.value('clean')),
        ('willReturnBeforeTen', const Reply.value(false)),
      ]);
      asked += 3;
      expect(machine.next(s), isNull);
      expect(stateAt(s, at(5, 13)), DayState.tahir);
      expect(asked, lessThanOrEqualTo(7));
    });

    test('لا تحتمل بقاءه داخلًا → طهر بلا قطنة', () {
      final stop = at(5, 12);
      var s = session(profile: FiqhProfile(habit: vw()), events: [BloodStart(fajr(1)), BloodStop(stop)], now: at(5, 13), settled: onboarded);
      s = walk(s, [('innerContinuity', const Reply.value(false))]);
      expect(machine.next(s), isNull);
      expect(stateAt(s, at(5, 13)), DayState.tahir);
    });

    test('«لا أدري» في احتمال البقاء → القطنة؛ و«لم أُجرِ الاختبار» يبقيه معلَّقًا ويُعاد', () {
      final stop = at(5, 12);
      var s = session(profile: FiqhProfile(habit: vw()), events: [BloodStart(fajr(1)), BloodStop(stop)], now: at(5, 13), settled: onboarded);
      s = walk(s, [('innerContinuity', Reply.dontRemember)]);
      final q = machine.next(s)!;
      expect(q.id, 'kursufTest');
      s = machine.apply(s, q, Reply.dontRemember);
      expect(machine.next(s)?.id, 'kursufTest');
      expect(stateAt(s, at(5, 13)), DayState.pending);
    });

    test('«لا أفهم» احتمال البقاء → فحص الأثر: لا أثر → طهر', () {
      final stop = at(5, 12);
      var s = session(profile: FiqhProfile(habit: vw()), events: [BloodStart(fajr(1)), BloodStop(stop)], now: at(5, 13), settled: onboarded);
      s = walk(s, [
        ('innerContinuity', Reply.dontUnderstand),
        ('innerTrace', const Reply.value(false)),
      ]);
      expect(machine.next(s), isNull);
      expect(stateAt(s, at(5, 13)), DayState.tahir);
    });

    test('«لا أفهم» القطنة → شرح ثم السؤال نفسه معلَّمًا', () {
      final stop = at(5, 12);
      var s = session(profile: FiqhProfile(habit: vw()), events: [BloodStart(fajr(1)), BloodStop(stop), InnerContinuity(stop, const Tri.known(true))], now: at(5, 13), settled: onboarded);
      var q = machine.next(s)!;
      expect(q.id, 'kursufTest');
      expect(q.explained, isFalse);
      s = machine.apply(s, q, Reply.dontUnderstand);
      q = machine.next(s)!;
      expect(q.id, 'kursufTest');
      expect(q.explained, isTrue);
      expect(q.explanation, isNotNull);
    });

    test('القطنة نظيفة مع الاطمئنان بالعود → جمع إلى العشرة؛ و«لا أفهم» → سؤال المرات السابقة', () {
      final stop = at(5, 12);
      final events = [BloodStart(fajr(1)), BloodStop(stop), InnerContinuity(stop, const Tri.known(true)), KursufTest(at(5, 13), KursufResult.clean)];
      var s = session(profile: FiqhProfile(habit: vw()), events: events, now: at(5, 14), settled: onboarded);
      s = walk(s, [('willReturnBeforeTen', const Reply.value(true))]);
      expect(stateAt(s, at(6, 12)), DayState.jam3);
      expect(machine.next(s), isNull);

      s = session(profile: FiqhProfile(habit: vw()), events: events, now: at(5, 14), settled: onboarded);
      s = walk(s, [
        ('willReturnBeforeTen', Reply.dontUnderstand),
        ('bloodUsuallyReturns', const Reply.value(false)),
      ]);
      expect(stateAt(s, at(6, 12)), DayState.tahir);
      expect(machine.next(s), isNull);

      // «أظن فقط» → طهر (ج م٦٠٨).
      s = session(profile: FiqhProfile(habit: vw()), events: events, now: at(5, 14), settled: onboarded);
      s = walk(s, [('willReturnBeforeTen', Reply.dontRemember)]);
      expect(stateAt(s, at(6, 12)), DayState.tahir);
      expect(machine.next(s), isNull);
    });

    test('بعد العادة والقطنة ملوثة والتردد → «هل يتجاوز العشرة؟»', () {
      final stop = at(7, 12);
      final events = [BloodStart(fajr(1)), BloodStop(stop), InnerContinuity(stop, const Tri.known(true)), KursufTest(at(7, 13), KursufResult.stained)];
      var s = session(profile: FiqhProfile(habit: vw(count: 5)), events: events, now: at(7, 14), settled: onboarded);
      expect(stateAt(s, at(7, 14)), DayState.istU);
      s = walk(s, [('willExceedTen', const Reply.value('stop'))]);
      expect(stateAt(s, at(7, 14)), DayState.hayd);
      expect(machine.next(s), isNull);

      s = session(profile: FiqhProfile(habit: vw(count: 5)), events: events, now: at(7, 14), settled: onboarded);
      s = walk(s, [('willExceedTen', Reply.dontRemember)]);
      expect(stateAt(s, at(7, 14)), DayState.istU);
      expect(machine.next(s)?.id, 'istihadhaTest');
    });

    test('السؤال نفسه يُعاد في واقعة انقطاع جديدة لا في الواقعة نفسها', () {
      final stop1 = at(5, 12);
      var s = session(profile: FiqhProfile(habit: vw()), events: [BloodStart(fajr(1)), BloodStop(stop1)], now: at(5, 13), settled: onboarded);
      s = walk(s, [('innerContinuity', const Reply.value(false))]);
      expect(machine.next(s), isNull);
      // حيضة جديدة بعد شهر وانقطاع جديد.
      final stop2 = at(35, 12);
      s = s.copyWith(events: [...s.events, BloodStart(fajr(31)), BloodStop(stop2)], now: at(35, 13));
      final q = machine.next(s);
      expect(q?.id, 'innerContinuity');
      expect(q?.at, stop2);
    });
  });

  group('بدء الدم لغير ذات الوقت: الصفات ثم العلم بالاستمرار', () {
    final mud = FiqhProfile(habit: const HabitState(type: WomanType.mud, origin: HabitOrigin.declared), lastBloodEnd: Tri.known(day(-20)));

    test('واجد للصفات → حيض بلا سؤال ثانٍ', () {
      var s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: onboarded);
      s = walk(s, [('bloodProps', const Reply.value('wajid'))]);
      expect(stateAt(s, at(1, 12)), DayState.hayd);
      expect(machine.next(s), isNull);
    });

    test('«لا أفهم» الصفات → لون، حرارة، دفع: وتكفي صفة واحدة', () {
      var s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: onboarded);
      s = walk(s, [
        ('bloodProps', Reply.dontUnderstand),
        ('propsDark', const Reply.value('dark')),
      ]);
      expect(s.ladder, isNull);
      expect(stateAt(s, at(1, 12)), DayState.hayd);

      s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: onboarded);
      s = walk(s, [
        ('bloodProps', Reply.dontUnderstand),
        ('propsDark', const Reply.value('light')),
        ('propsWarm', const Reply.value(false)),
        ('propsThrust', const Reply.value(false)),
      ]);
      expect(stateAt(s, at(1, 12)), DayState.jam3M);
      expect(machine.next(s)?.id, 'willLastThreeDays');
    });

    test('فاقد والعلم بالاستمرار → حيض؛ و«لا أعلم» → الجمع ولا سؤال بعده', () {
      var s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: onboarded);
      s = walk(s, [
        ('bloodProps', const Reply.value('faqid')),
        ('willLastThreeDays', const Reply.value(true)),
      ]);
      expect(stateAt(s, at(1, 12)), DayState.hayd);
      expect(machine.next(s), isNull);

      s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: onboarded);
      s = walk(s, [
        ('bloodProps', Reply.dontRemember),
        ('willLastThreeDays', Reply.dontRemember),
      ]);
      expect(stateAt(s, at(1, 12)), DayState.jam3M);
      expect(machine.next(s), isNull);

      s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: onboarded);
      s = walk(s, [
        ('bloodProps', const Reply.value('faqid')),
        ('willLastThreeDays', Reply.dontUnderstand),
        ('bloodUsuallyLasts', const Reply.value(true)),
      ]);
      expect(stateAt(s, at(1, 12)), DayState.hayd);
    });

    test('تمام الثلاثة يرفع السؤال عن الاستمرار تلقائيًّا', () {
      final s = session(profile: mud, events: [BloodStart(fajr(1)), PropsChange(fajr(1), BloodProps.faqid)], now: at(4, 12), settled: onboarded);
      expect(stateAt(s, at(4, 12)), DayState.hayd);
      expect(machine.next(s), isNull);
    });
  });

  group('ذات الوقت قبل وقتها', () {
    test('تقدم بأزيد من يومين: «هل يصدق التعجيل؟» → نعم حيض؛ لا أدري → الصفات', () {
      // العادة تبدأ يوم ٢٠؛ الدم يوم ١٥.
      final profile = FiqhProfile(habit: vw(start: 20), lastBloodEnd: Tri.known(day(-10)));
      var s = session(profile: profile, events: [BloodStart(fajr(15))], now: at(15, 12), settled: onboarded);
      s = walk(s, [('isEarlyHabit', const Reply.value(true))]);
      expect(stateAt(s, at(15, 12)), DayState.hayd);
      expect(machine.next(s), isNull);

      s = session(profile: profile, events: [BloodStart(fajr(15))], now: at(15, 12), settled: onboarded);
      s = walk(s, [('isEarlyHabit', Reply.dontRemember)]);
      expect(machine.next(s)?.id, 'bloodProps');
    });

    test('تعجيل بيومين: لا سؤال', () {
      final profile = FiqhProfile(habit: vw(start: 20), lastBloodEnd: Tri.known(day(-10)));
      final s = session(profile: profile, events: [BloodStart(fajr(18))], now: at(18, 12), settled: onboarded);
      expect(machine.next(s), isNull);
      expect(stateAt(s, at(18, 12)), DayState.hayd);
    });
  });

  group('آخر انتهاء قبل التنصيب (أقل الطهر)', () {
    const mud = FiqhProfile(habit: HabitState(type: WomanType.mud, origin: HabitOrigin.declared));

    test('لغير المبتدئة خارج وقت العادة يُسأل قبل الصفات', () {
      final s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: {'birthDate'});
      expect(machine.next(s)?.id, 'lastBloodEnd');
    });

    test('المبتدئة وذات الوقت في وقتها لا تُسألان', () {
      const mub = FiqhProfile(habit: HabitState(type: WomanType.mub, origin: HabitOrigin.declared));
      expect(machine.next(session(profile: mub, events: [BloodStart(fajr(1))], now: at(1, 12), settled: {'birthDate'}))?.id, 'bloodProps');
      expect(machine.next(session(profile: FiqhProfile(habit: vw()), events: [BloodStart(fajr(1))], now: at(1, 12), settled: {'birthDate'})), isNull);
    });

    test('«لا أتذكر» → أكثر من عشرة أيام؟ لا → كم يومًا؟ → استحاضة حتى يمضي أقل الطهر', () {
      var s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: {'birthDate'});
      s = walk(s, [
        ('lastBloodEnd', Reply.dontRemember),
        ('moreThanTenDays', const Reply.value(false)),
        ('daysSinceLastBlood', const Reply.value(4)),
      ]);
      expect(s.profile.lastBloodEnd, Tri.known(fajr(1).subtract(const Duration(days: 4))));
      expect(stateAt(s, at(1, 12))?.isIstihadha, isTrue);

      s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: {'birthDate'});
      s = walk(s, [
        ('lastBloodEnd', Reply.dontRemember),
        ('moreThanTenDays', const Reply.value(true)),
      ]);
      expect(s.profile.lastBloodEnd.isKnown, isFalse);
      expect(machine.next(s)?.id, 'bloodProps');
    });

    test('«لا أفهم» → متى آخر غسل؟', () {
      var s = session(profile: mud, events: [BloodStart(fajr(1))], now: at(1, 12), settled: {'birthDate'});
      s = walk(s, [
        ('lastBloodEnd', Reply.dontUnderstand),
        ('lastGhuslDate', Reply.value(day(-20))),
      ]);
      expect(s.profile.lastBloodEnd, Tri.known(clock.maghrib(day(-20))));
    });
  });

  group('التجاوز بلا تمييز: الأقارب ثم العدد المختار', () {
    const mub = FiqhProfile(habit: HabitState(type: WomanType.mub, origin: HabitOrigin.declared));
    final events = [BloodStart(fajr(1))];

    test('عدد قريبة بلا علم بالمخالفة → حيض بعددها', () {
      var s = session(profile: mub, events: events, now: at(11, 12), settled: {...onboarded, 'bloodProps@${fajr(1).toIso8601String()}'});
      expect(stateAt(s, at(11, 12)), DayState.pending);
      s = walk(s, [
        ('kinCount', const Reply.value(6)),
        ('kinConditions', const Reply.value(false)),
      ]);
      expect(stateAt(s, at(6, 12)), DayState.hayd);
      expect(stateAt(s, at(7, 12))?.isIstihadha, isTrue);
      expect(s.profile.kinConditionsMet, const Tri.known(true));
    });

    test('لا أقارب ولا اختيار → سبعة؛ ثم اختبار الاستحاضة لما بعدها', () {
      var s = session(profile: mub, events: events, now: at(11, 12), settled: {...onboarded, 'bloodProps@${fajr(1).toIso8601String()}'});
      s = walk(s, [
        ('kinCount', Reply.dontRemember),
        ('chosenCount', Reply.dontRemember),
      ]);
      expect(s.profile.chosenCount, const Tri.known(7));
      expect(stateAt(s, at(7, 12)), DayState.hayd);
      expect(stateAt(s, at(8, 12)), DayState.istU);
      final q = machine.next(s)!;
      expect(q.id, 'istihadhaTest');
      // «لم أختبر بعد» يبقيه كما هو.
      s = machine.apply(s, q, Reply.dontRemember);
      expect(machine.next(s)?.id, 'istihadhaTest');
      s = walk(s, [
        ('istihadhaTest', const Reply.value('kathira')),
        ('istihadhaFlow', const Reply.value('intermittent')),
      ]);
      expect(stateAt(s, at(11, 12)), DayState.istK);
      expect(machine.next(s), isNull);
    });

    test('علم بمخالفة القريبة → العدد المختار', () {
      var s = session(profile: mub, events: events, now: at(11, 12), settled: {...onboarded, 'bloodProps@${fajr(1).toIso8601String()}'});
      s = walk(s, [
        ('kinCount', const Reply.value(6)),
        ('kinConditions', const Reply.value(true)),
        ('chosenCount', const Reply.value(3)),
      ]);
      expect(stateAt(s, at(3, 12)), DayState.hayd);
      expect(stateAt(s, at(4, 12))?.isIstihadha, isTrue);
    });
  });

  group('السقط', () {
    test('مرحلة مجهولة → السؤال؛ «لا أفهم» → صورة إنسان؟ نعم → نفاس ثم ولوج الروح', () {
      final m = Miscarriage(at(1, 10));
      var s = session(profile: FiqhProfile(habit: vw()), events: [m, BloodStart(at(1, 11))], now: at(1, 12), settled: onboarded);
      expect(stateAt(s, at(1, 12)), DayState.pending);
      s = walk(s, [
        ('miscarriageStage', Reply.dontUnderstand),
        ('humanForm', const Reply.value(true)),
      ]);
      expect(stateAt(s, at(1, 12)), DayState.nifas);
      s = walk(s, [
        ('ensouled', Reply.dontUnderstand),
        ('fourMonths', const Reply.value(true)),
      ]);
      expect(machine.evaluate(s).notices.any((n) => n.id == 'M-06'), isTrue);
      expect(machine.next(s), isNull);
    });

    test('«لا أعرف» المرحلة → يبقى معلَّقًا بالتوجيه ولا يُكرَّر', () {
      final m = Miscarriage(at(1, 10));
      var s = session(profile: FiqhProfile(habit: vw()), events: [m, BloodStart(at(1, 11))], now: at(1, 12), settled: onboarded);
      final q = machine.next(s)!;
      expect(q.id, 'miscarriageStage');
      expect(q.guidance, isNotNull);
      s = machine.apply(s, q, Reply.dontRemember);
      expect(stateAt(s, at(1, 12)), DayState.pending);
      expect(machine.next(s), isNull);
    });
  });

  group('رمضان والحمل والبكارة', () {
    test('نقاء ليلًا بلا مدى رمضان → «هل الغد من رمضان؟»', () {
      final stop = at(4, 22);
      var s = session(profile: FiqhProfile(habit: vw()), events: [BloodStart(fajr(1)), BloodStop(stop), InnerContinuity(stop, const Tri.known(false))], now: at(4, 23), settled: onboarded);
      s = walk(s, [('ramadanTomorrow', const Reply.value(true))]);
      expect(machine.evaluate(s).alerts.any((a) => a.rule.id == 'H9-15'), isTrue);
      expect(machine.next(s), isNull);
    });

    test('الحامل ذات الوقت بعد عشرين يومًا بصفات الحيض → تُسأل عن الحمل', () {
      // العادة تبدأ يوم ١ وعددها ٧؛ الدم يوم ٢٢ بصفات الحيض: بعد عشرين يومًا من أول
      // العادة وقبل موعدها القادم بتسعة أيام، فيُسأل عن التعجيل أولًا ثم عن الحمل.
      final profile = FiqhProfile(habit: vw(start: 1), lastBloodEnd: Tri.known(clock.maghrib(day(8))));
      var s = session(profile: profile, events: [BloodStart(fajr(22), props: BloodProps.wajid)], now: at(24, 12), settled: onboarded);
      expect(stateAt(s, at(24, 12)), DayState.hayd);
      s = walk(s, [('isEarlyHabit', const Reply.value(false))]);
      expect(stateAt(s, at(24, 12)), DayState.hayd);
      expect(machine.next(s)?.id, 'pregnant');
      s = walk(s, [('pregnant', const Reply.value(true))]);
      expect(stateAt(s, at(24, 12)), DayState.jam3);
      expect(machine.next(s), isNull);
    });

    test('مردد بين البكارة والحيض → اختبار القطنة؛ «تعذّر» → الطهارة بلا تكرار', () {
      final profile = FiqhProfile(habit: vw(start: 20), lastBloodEnd: Tri.known(day(-10)));
      var s = session(profile: profile, events: [BloodStart(fajr(1)), SourceNote(fajr(1), BloodSource.doubtVirginityOrHayd)], now: at(1, 12), settled: onboarded);
      final q = machine.next(s)!;
      expect(q.id, 'virginityTest');
      s = machine.apply(s, q, Reply.dontRemember);
      expect(machine.next(s), isNull);
      expect(stateAt(s, at(1, 12)), DayState.tahir);

      s = session(profile: profile, events: [BloodStart(fajr(1)), SourceNote(fajr(1), BloodSource.doubtVirginityOrHayd)], now: at(1, 12), settled: onboarded);
      s = walk(s, [('virginityTest', const Reply.value('ringed'))]);
      expect(stateAt(s, at(1, 12)), DayState.ghayr);
    });
  });

  test('كل سؤال في الفهرس له قاعدة، وكل خطوة سلّم لها أصل في الفهرس', () {
    for (final q in QuestionCatalog.all) {
      expect(q.rule.id, isNotEmpty, reason: q.id);
      if (q.parentId != null) expect(QuestionCatalog.has(q.parentId!), isTrue, reason: q.id);
      if (q.kind == QuestionKind.choice) expect(q.options, isNotEmpty, reason: q.id);
      if (q.kind == QuestionKind.number) expect(q.min != null && q.max != null, isTrue, reason: q.id);
    }
  });
}
