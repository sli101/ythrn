// ignore_for_file: avoid_print
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ythrn/app/answer.dart';
import 'package:ythrn/app/clock.dart';
import 'package:ythrn/app/intent.dart';
import 'package:ythrn/app/labels.dart';
import 'package:ythrn/app/providers.dart';
import 'package:ythrn/data/app_settings.dart';
import 'package:ythrn/data/fiqh_store.dart';
import 'package:ythrn/fiqh/fiqh.dart';

/// «تخيّل أنك امرأة»: سيناريوهات كاملة على التطبيق (المخزن والمزوّدات والآلة
/// وبطاقة الجواب) تطبع ما تراه المرأة خطوة خطوة، مع تأكيدات على ما لا يجوز أن يخطئ.
void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  const settings = AppSettings(manualFajrMinutes: 270, manualMaghribMinutes: 1110);
  final time = FiqhTime(clockFromSettings(settings));
  final today = time.fiqhDayOf(DateTime.now());
  DateTime day(int ago) => DateTime(today.year, today.month, today.day - ago);

  /// جلسة امرأة: مخزن في الذاكرة وحاوية مزوّدات.
  Future<_Woman> woman(String name, StoredState initial) async {
    final store = MemoryFiqhStore(initial);
    final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    await container.read(appStateProvider.future);
    return _Woman(name, container, store, time);
  }

  FiqhProfile profile({HabitState? habit, DateTime? birth, Tri<bool> pregnant = const Tri.unknown(UnknownKind.dontRemember)}) => FiqhProfile(
        habit: habit ?? const HabitState(type: WomanType.mub, origin: HabitOrigin.declared),
        birth: birth == null ? const Tri.unknown(UnknownKind.dontRemember) : Tri.known(birth),
        pregnant: pregnant,
        ramadan: [(DateTime(2030, 1, 1), DateTime(2030, 1, 30))],
      );

  test('١. فتاة ١٥ سنة ترى الدم لأول مرة منذ ٤ أيام، لا تعرف صفاته', () async {
    final w = await woman('فتاة ١٥', StoredState(settings: settings));
    await w.mark(day(3), day(0));
    await w.ask(AskIntent.isHayd, answers: {
      'womanType': 'MUB',
      'birthDate': DateTime(today.year - 15, today.month, today.day),
      'bloodProps': 'dont_remember',
      'willLastThreeDays': 'dont_remember',
    });
    // أربعة أيام مضت فالثلاثة تمت: حيض وإن جُهلت الصفات (H3-06 بعد التمام).
    expect(w.state, DayState.hayd, reason: w.log);
  });

  test('٢. ذات عادة ٧ أيام، جاءها الدم قبل موعده بيومين واستمر ٩ أيام ثم انقطع', () async {
    final w = await woman('ذات عادة', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(38)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.mark(day(10), day(2));
    await w.ask(AskIntent.stopped, answers: {'innerContinuity': false, 'willReturnBeforeTen': false});
    expect(w.dayStates.values.where((s) => s == DayState.hayd).length, 9, reason: w.log);
    expect(w.state, DayState.tahir, reason: w.log);
    expect(w.answer.headline, contains('اغتسلي'), reason: w.log);
  });

  test('٣. ذات عادة ٧، استمر الدم ١٤ يومًا: أيام العادة حيض والباقي استحاضة', () async {
    final w = await woman('تجاوز', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(44)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.mark(day(14), day(1));
    await w.ask(AskIntent.overflow, answers: {'innerContinuity': false, 'willExceedTen': 'exceed', 'istihadhaTest': 'qalila'});
    final h = w.dayStates.values.where((s) => s == DayState.hayd).length;
    final i = w.dayStates.values.where((s) => s?.isIstihadha ?? false).length;
    expect(h, 7, reason: w.log);
    expect(i, 7, reason: w.log);
    expect(w.answer.headline, contains('حيض'), reason: w.log);
  });

  test('٤. دم يومين فقط ثم انقطع ولم يعد: ليس حيضًا، وعليها قضاء الصلاة', () async {
    final w = await woman('يومان', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(32)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.mark(day(12), day(11));
    await w.ask(AskIntent.qada, answers: {'innerContinuity': false, 'willReturnBeforeTen': false, 'istihadhaTest': 'qalila'});
    expect(w.dayStates.values.any((s) => s == DayState.hayd), isFalse, reason: w.log);
    // كانت في جمع احتياطي (تصلّي) فلا قضاء محسوب؛ لكن يُنبَّه على اليومين.
    expect(w.answer.notHaydBloodDays.length, 2, reason: w.log);
    expect(w.answer.headline, contains('فاقضيها'), reason: w.log);
  });

  test('٥. ولادة قبل ١٢ يومًا والدم مستمر: نفاس إلى العشرة ثم استحاضة', () async {
    final w = await woman('نفساء', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.notifier.addEvent(Birth(time.clock.fajr(day(12)).add(const Duration(hours: 3))));
    await w.mark(day(12), day(0));
    await w.ask(AskIntent.nifas, answers: {'istihadhaTest': 'kathira', 'istihadhaFlow': 'continuous'});
    expect(w.dayStates.values.where((s) => s == DayState.nifas).length, inInclusiveRange(7, 10), reason: w.log);
    expect(w.state.isIstihadha, isTrue, reason: w.log);
  });

  test('٦. امرأة ٦٢ سنة ترى دمًا ٥ أيام: ليس حيضًا', () async {
    final w = await woman('يائسة', StoredState(settings: settings, profile: profile(habit: const HabitState(type: WomanType.mud, origin: HabitOrigin.declared), birth: DateTime(today.year - 62))));
    await w.mark(day(5), day(1));
    await w.ask(AskIntent.isHayd, answers: {'isQurashi': false, 'istihadhaTest': 'qalila'});
    expect(w.dayStates.values.any((s) => s == DayState.hayd), isFalse, reason: w.log);
  });

  test('٧. حامل ترى دمًا بصفات الحيض ٥ أيام', () async {
    final w = await woman('حامل', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(35)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995), pregnant: const Tri.known(true))));
    await w.mark(day(5), day(1), props: BloodProps.wajid);
    await w.ask(AskIntent.isHayd, answers: {});
    print(w.log);
    expect(w.log, isNot(contains('خطأ')));
  });

  test('٨. لطخة صفراء يوم واحد فقط', () async {
    final w = await woman('لطخة', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(20)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.notifier.saveMarks([BloodDay(day(2), props: BloodProps.faqid, spots: true)]);
    await w.ask(AskIntent.isHayd, answers: {'innerContinuity': false, 'willReturnBeforeTen': false, 'istihadhaTest': 'qalila'});
    expect(w.dayStates.values.any((s) => s == DayState.hayd), isFalse, reason: w.log);
  });

  test('٩. شهران سابقان ٧ أيام ثم دم هذا الشهر: العادة تُشتق بلا سؤال النوع', () async {
    final w = await woman('مشتقة', StoredState(settings: settings, profile: profile(birth: DateTime(1995))));
    await w.mark(day(67), day(61), props: BloodProps.wajid);
    await w.mark(day(37), day(31), props: BloodProps.wajid);
    await w.mark(day(6), day(0));
    await w.ask(AskIntent.isHayd, answers: {'womanType': 'MUB'});
    final habit = w.container.read(sessionProvider)!.profile.habit;
    print('${w.name}: العادة المشتقة ${habit.type.code} عدد ${habit.count} تاريخ ${habit.history.length}');
    expect(habit.type, WomanType.vw, reason: w.log);
    expect(w.state, DayState.hayd, reason: w.log);
    expect(w.asked, isNot(contains('bloodProps')), reason: 'في وقتها فتتحيض بالرؤية: ${w.log}');
  });

  test('١٠. تلوين ثم حذف يوم من الوسط يقسم المدى إلى مديين', () async {
    final w = await woman('حذف', StoredState(settings: settings, profile: profile(habit: const HabitState(type: WomanType.mub, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.mark(day(8), day(2));
    await w.notifier.toggleDay(day(5));
    final ev = w.container.read(calendarEventsProvider);
    expect(ev.whereType<BloodStart>().length, 2);
    expect(ev.whereType<BloodStop>().length, 2);
  });

  test('١١. الدم مستمر اليوم ثم «انقطع اليوم» ثم عاد غدًا؟ (انقطاع ثم تلوين اليوم نفسه)', () async {
    final w = await woman('انقطاع', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(4)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.mark(day(4), day(0));
    final m = w.store.state.marks.last;
    await w.notifier.updateDay(m.copyWith(stopAt: DateTime.now()));
    expect(w.container.read(bloodOngoingProvider), isFalse);
    // عاد في اليوم نفسه بعد ساعة: النقرة على اليوم تفتح الورقة، فلا يمكن «إعادة الجريان» إلا بإزالة الانقطاع.
    await w.notifier.updateDay(m.copyWith(clearStopAt: true));
    expect(w.container.read(bloodOngoingProvider), isTrue);
  });

  // ------------------------------------------------------------ الجولة الثانية

  test('١٢. بدأ الدم ليلًا قبل ثلاثة أيام ومستمر: اليوم الأول لا يُحسب نهاره', () async {
    final w = await woman('ليلي', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(3)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.mark(day(3), day(0));
    final first = w.store.state.marks.first;
    await w.notifier.updateDay(first.copyWith(startPart: DayPart.night));
    await w.ask(AskIntent.isHayd, answers: {});
    expect(w.state, DayState.hayd, reason: w.log);
    // اليوم الأول يحمل حكم ليلته في التقويم، والمعلم القادم (الثلاثة أو العشرة) معروض.
    expect(w.dayStates.values.first, DayState.hayd, reason: w.log);
    expect(w.answer.watch, isNotEmpty, reason: w.log);
  });

  test('١٣. نسيت عادتها (لا أتذكر) ورأت دمًا ١٢ يومًا بصفات مختلفة', () async {
    final w = await woman('ناسية', StoredState(settings: settings, profile: FiqhProfile(birth: Tri.known(DateTime(1990)), ramadan: [(DateTime(2030, 1, 1), DateTime(2030, 1, 30))])));
    await w.mark(day(12), day(1), props: BloodProps.wajid);
    final m = w.store.state.marks;
    await w.notifier.updateDay(m[6].copyWith(props: BloodProps.faqid));
    await w.ask(AskIntent.overflow, answers: {
      'womanType': 'dont_remember',
      'nasiyaForgot': 'both',
      'nasiyaCountMin': 'dont_remember',
      'nasiyaCountMax': 'dont_remember',
      'nasiyaHalfMonth': 'dont_remember',
      'innerContinuity': false,
      'willExceedTen': 'exceed',
      'istihadhaTest': 'qalila',
    });
    expect(w.asked, containsAll(['womanType', 'nasiyaForgot']), reason: w.log);
    expect(w.dayStates.values.where((s) => s == DayState.hayd).length, inInclusiveRange(3, 10), reason: w.log);
    expect(w.result.unsupported, isEmpty, reason: w.log);
  });

  test('١٤. ٧ أيام دم، ٥ نقاء، ٤ أيام دم: المجموع يتجاوز العشرة (دمان)', () async {
    final w = await woman('دمان', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(46)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.mark(day(16), day(10), props: BloodProps.wajid);
    await w.mark(day(4), day(1));
    await w.ask(AskIntent.overflow, answers: {'innerContinuity': false, 'willReturnBeforeTen': false, 'willExceedTen': 'exceed', 'istihadhaTest': 'qalila'});
    print(w.log);
    expect(w.dayStates.values.where((s) => s == DayState.hayd).length, 7, reason: w.log);
    expect(w.result.unsupported, isEmpty, reason: w.log);
  });

  test('١٥. مبتدئة دمها ١٢ يومًا بلا تمييز: ترجع إلى أقاربها أو تختار عددًا', () async {
    final w = await woman('مبتدئة ١٢', StoredState(settings: settings, profile: profile(habit: const HabitState(type: WomanType.mub, origin: HabitOrigin.declared), birth: DateTime(2010))));
    await w.mark(day(12), day(1), props: BloodProps.faqid);
    await w.ask(AskIntent.overflow, answers: {'innerContinuity': false, 'willExceedTen': 'exceed', 'kinCount': 'dont_remember', 'chosenCount': 7, 'istihadhaTest': 'qalila'});
    print(w.log);
    expect(w.dayStates.values.where((s) => s == DayState.hayd).length, 7, reason: w.log);
  });

  test('١٦. استحاضة كثيرة مستمرة ٢٠ يومًا: ما تفعله اليوم', () async {
    final w = await woman('مستحاضة', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(20)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.mark(day(20), day(0));
    await w.ask(AskIntent.istihadha, answers: {'willExceedTen': 'exceed', 'istihadhaTest': 'kathira', 'istihadhaFlow': 'continuous'});
    expect(w.state, DayState.istK, reason: w.log);
    expect(w.answer.headline, contains('كثيرة'), reason: w.log);
    expect(w.answer.doNow.any((d) => d.text.contains('غسل') || d.text.contains('أغسال')), isTrue, reason: w.log);
  });

  test('١٧. حيض في رمضان: قضاء الصوم يُحسب من التقويم الهجري بلا إدخال', () async {
    // أيام الحيض تُوضع داخل رمضان الهجري الأقرب في الماضي.
    final h = HijriDate.fromDate(today);
    final ramadanYear = h.month > 9 ? h.year : h.year - 1;
    final r1 = HijriDate(ramadanYear, 9, 5).toDate();
    final w = await woman('رمضان', StoredState(settings: settings, profile: FiqhProfile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(r1), count: 7, origin: HabitOrigin.declared), birth: Tri.known(DateTime(1995)))));
    await w.mark(r1, DateTime(r1.year, r1.month, r1.day + 6));
    await w.ask(AskIntent.qada, answers: {'innerContinuity': false, 'willReturnBeforeTen': false});
    print(w.log);
    expect(w.result.qada.fastDays.length, 7, reason: w.log);
    expect(w.answer.headline, contains('صيام'), reason: w.log);
  });

  test('١٨. ولادة في يوم الدم نفسه: لا سؤال عن آخر انتهاء، والنفاس من لحظة الولادة', () async {
    final w = await woman('ولادة اليوم', StoredState(settings: settings, profile: profile(habit: HabitState(type: WomanType.vw, anchorDate: time.clock.fajr(day(40)), count: 7, origin: HabitOrigin.declared), birth: DateTime(1995))));
    await w.notifier.addEvent(Birth(time.clock.fajr(day(5)).add(const Duration(hours: 5))));
    await w.mark(day(5), day(0));
    await w.ask(AskIntent.nifas, answers: {});
    expect(w.asked, isNot(contains('lastBloodEnd')), reason: w.log);
    expect(w.state, DayState.nifas, reason: w.log);
    expect(w.container.read(calendarEventsProvider).whereType<BloodStart>().first.at, time.clock.fajr(day(5)).add(const Duration(hours: 5)));
  });

  test('١٩. تلوّن أيامًا ثم تحذف كل البيانات ثم تعود: لا بقايا', () async {
    final w = await woman('حذف كلي', StoredState(settings: settings, profile: profile(birth: DateTime(1995))));
    await w.mark(day(3), day(0));
    await w.notifier.clearAll();
    expect(w.store.state.marks, isEmpty);
    expect(w.container.read(resultProvider)!.intervals.where((iv) => iv.state != DayState.tahir), isEmpty);
    expect(w.container.read(nextQuestionProvider)?.id, 'womanType');
  });
}

class _Woman {
  _Woman(this.name, this.container, this.store, this.time);
  final String name;
  final ProviderContainer container;
  final MemoryFiqhStore store;
  final FiqhTime time;
  final asked = <String>[];
  final _log = StringBuffer();
  late AnswerSummary answer;

  AppStateNotifier get notifier => container.read(appStateProvider.notifier);
  EngineResult get result => container.read(resultProvider)!;
  DayState get state => container.read(todayIntervalProvider)?.state ?? DayState.tahir;
  String get log => _log.toString();

  Map<DateTime, DayState?> get dayStates {
    final marks = store.state.marks;
    final from = marks.map((m) => m.day).reduce((a, b) => a.isBefore(b) ? a : b);
    return BloodCalendar.dayStates(result, time.clock, from: from, to: container.read(todayProvider));
  }

  Future<void> mark(DateTime from, DateTime to, {BloodProps? props}) async {
    await notifier.markRange(from, to);
    if (props != null) {
      final first = store.state.marks.firstWhere((m) => m.day == from);
      await notifier.updateDay(first.copyWith(props: props));
    }
  }

  /// «احسبي»: الساعة حيث تلزم (نتركها على الافتراض)، ثم الأسئلة بالأجوبة المعطاة
  /// (أو «لاحقًا» لما لم يُعطَ)، ثم بطاقة الجواب.
  Future<void> ask(AskIntent intent, {required Map<String, Object> answers}) async {
    _log.writeln('— $name تسأل: ${intent.title}');
    final s0 = container.read(sessionProvider)!;
    final needs = BloodCalendar.precisionNeeds(store.state.marks, time.clock, today: container.read(todayProvider), now: s0.now,
        evaluate: (cal) => container.read(machineProvider).engine.evaluateProfile(s0.profile, [...cal, ...store.state.events.map((e) => e.event)], s0.now));
    if (needs.isNotEmpty) _log.writeln('  يطلب الساعة: ${needs.map((n) => '${Labels.shortDate(n.day)} ${n.isStart ? 'بدء' : 'انقطاع'}').join('، ')}');
    QuestionSession? ladder; // السلّم حالة الشاشة لا المخزن (كما في QuestionScreen).
    final machine = container.read(machineProvider);
    for (var i = 0; i < 16; i++) {
      final q = ladder != null ? machine.next(ladder) : container.read(nextQuestionProvider);
      if (q == null) break;
      asked.add(q.id);
      final a = answers[q.id];
      final reply = switch (a) {
        null => Reply.skip,
        'dont_remember' => Reply.dontRemember,
        'dont_understand' => Reply.dontUnderstand,
        _ => Reply.value(a),
      };
      _log.writeln('  س: ${q.text}  ← ${a ?? 'لاحقًا'}');
      final after = await notifier.answer(ladder ?? container.read(sessionProvider)!, q, reply);
      ladder = after.ladder == null ? null : after;
      if (after.ladder != null) _log.writeln('  (سلّم مفتوح: ${after.ladder!.parent.id})');
    }
    final s = container.read(sessionProvider)!;
    answer = AnswerSummary.build(intent: intent, r: result, time: time, now: s.now, events: s.events, marks: store.state.marks);
    _log.writeln('  الأيام: ${dayStates.entries.map((e) => '${e.key.day}:${e.value?.code ?? '-'}').join(' ')}');
    _log.writeln('  الجواب: ${answer.headline} [${Labels.state(answer.state)} · ${Labels.classification(answer.classification)}]');
    for (final d in answer.doNow) {
      _log.writeln('    افعلي: ${d.text}');
    }
    for (final (at, t) in answer.watch) {
      _log.writeln('    انتبهي: ${Labels.dateTime(at)} $t');
    }
    if (!result.qada.isEmpty) _log.writeln('  القضاء: صلاة ${result.qada.prayerDays.map((d) => d.day).toList()} صوم ${result.qada.fastDays.map((d) => d.day).toList()}');
    if (answer.notHaydBloodDays.isNotEmpty) _log.writeln('  أيام دم ليست حيضًا: ${answer.notHaydBloodDays.map((d) => d.day).toList()}');
    if (result.unsupported.isNotEmpty) _log.writeln('  خطأ: غير مغطى ${result.unsupported}');
    print(log);
  }
}
