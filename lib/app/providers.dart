import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/app_settings.dart';
import '../data/fiqh_store.dart';
import '../fiqh/fiqh.dart';
import 'clock.dart';
import 'rules_repository.dart';

/// المخزن المحلي؛ يُستبدل في `main` وفي الاختبارات.
final storeProvider = Provider<FiqhStore>((ref) => throw UnimplementedError('storeProvider يُستبدل في ProviderScope'));

/// القواعد من الأصول لشاشة «لماذا؟».
final rulesProvider = FutureProvider<RulesRepository>((ref) => RulesRepository.load(rootBundle));

/// الآن؛ يُحدَّث دوريًّا من الواجهة حتى تُعاد المعالم (الفجر والمغرب) آليًّا.
final nowProvider = StateProvider<DateTime>((ref) => DateTime.now());

/// حالة التطبيق المحفوظة.
final appStateProvider = AsyncNotifierProvider<AppStateNotifier, StoredState>(AppStateNotifier.new);

final settingsProvider = Provider<AppSettings>((ref) => ref.watch(appStateProvider).value?.settings ?? const AppSettings());

final clockProvider = Provider<DayClock>((ref) => clockFromSettings(ref.watch(settingsProvider)));

final timeProvider = Provider<FiqhTime>((ref) => FiqhTime(ref.watch(clockProvider)));

final machineProvider = Provider<QuestionMachine>((ref) => QuestionMachine(ref.watch(timeProvider)));

/// اليوم الفقهي الحالي (منتصف ليل اليوم التقويمي الذي يحمل رقمه).
final todayProvider = Provider<DateTime>((ref) => ref.watch(timeProvider).fiqhDayOf(ref.watch(nowProvider)));

/// أحداث التقويم (بدء الدم وانقطاعه وصفاته) من أيام الدم المحفوظة.
final calendarEventsProvider = Provider<List<FiqhEvent>>((ref) {
  final state = ref.watch(appStateProvider).value;
  final marks = state?.marks ?? const <BloodDay>[];
  final anchors = [for (final e in state?.events ?? const <StoredEvent>[]) if (e.event is Birth || e.event is Miscarriage) e.event.at];
  return BloodCalendar.toEvents(marks, ref.watch(clockProvider), today: ref.watch(todayProvider), anchors: anchors);
});

/// مدى رمضان بالتقويم الهجري الحسابي للسنوات التي تغطيها أيام الدم والآن
/// (H9-08؛ `docs/fiqh/assumptions.md` ٦١). يُستعمل إذا لم يُدخل مدى يدويًّا.
List<(DateTime, DateTime)> ramadanRanges({required DateTime from, required DateTime to}) {
  final a = HijriDate.fromDate(from).year;
  final b = HijriDate.fromDate(to).year;
  return [
    for (var y = a; y <= b; y++) (HijriDate(y, 9, 1).toDate(), HijriDate(y, 10, 1).toDate().subtract(const Duration(minutes: 1))),
  ];
}

/// جلسة الأسئلة من الحالة المحفوظة والآن (بلا سلّم جارٍ؛ السلّم حالة الشاشة):
/// أحداث التقويم أولًا ثم الأحداث المخزَّنة؛ والعادة مشتقة من الحيضات المغلقة
/// فوق المصرَّح به (`docs/fiqh/assumptions.md` ٥٩).
final sessionProvider = Provider<QuestionSession?>((ref) {
  final state = ref.watch(appStateProvider).value;
  if (state == null) return null;
  final now = ref.watch(nowProvider);
  final events = [...ref.watch(calendarEventsProvider), for (final e in state.events) e.event];
  var profile = state.profile;
  if (profile.ramadan.isEmpty) {
    final earliest = state.marks.map((m) => m.day).fold<DateTime>(now, (a, b) => b.isBefore(a) ? b : a);
    profile = profile.copyWith(ramadan: ramadanRanges(from: earliest, to: now.add(const Duration(days: 40))));
  }
  final engine = ref.watch(machineProvider).engine;
  final lastStart = events.whereType<BloodStart>().where((e) => !e.at.isAfter(now)).lastOrNull?.at;
  if (lastStart != null) {
    final pre = engine.evaluateProfile(profile, events, now);
    final derived = const HabitDerivation().derive(profile.habit, pre, before: lastStart);
    if (!identical(derived, profile.habit)) profile = profile.copyWith(habit: derived);
  }
  // ناسية الوقت التي تتذكر نصف الشهر: النافذة بالتقويم الهجري في شهر آخر دم أو الآن
  // (H7-05؛ `docs/fiqh/assumptions.md` ٥٦).
  if (profile.timeWindow == null && profile.nasiyaHalfMonth != null) {
    final ref0 = events.whereType<BloodStart>().where((e) => !e.at.isAfter(now)).lastOrNull?.at ?? now;
    profile = profile.copyWith(timeWindow: nasiyaHalfMonthWindow(profile.nasiyaHalfMonth!, ref0, ref.watch(clockProvider)));
  }
  return QuestionSession(profile: profile, events: events, now: now, settled: state.settled, explained: state.explained);
});

/// «ماذا لو؟» على الجلسة الحالية.
final whatIfProvider = Provider<List<WhatIfItem>>((ref) {
  final s = ref.watch(sessionProvider);
  if (s == null) return const [];
  return WhatIf(ref.watch(machineProvider)).items(s);
});

final resultProvider = Provider<EngineResult?>((ref) {
  final s = ref.watch(sessionProvider);
  if (s == null) return null;
  return ref.watch(machineProvider).evaluate(s);
});

/// فترة الحكم التي تغطي الآن.
final todayIntervalProvider = Provider<StateInterval?>((ref) {
  final r = ref.watch(resultProvider);
  if (r == null) return null;
  final now = ref.watch(nowProvider);
  return r.at(now) ?? (r.intervals.isEmpty ? null : r.intervals.last);
});

final nextQuestionProvider = Provider<Question?>((ref) {
  final s = ref.watch(sessionProvider);
  if (s == null) return null;
  return ref.watch(machineProvider).next(s);
});

/// هل الدم جارٍ الآن (آخر مقطع مفتوح)؟
final bloodOngoingProvider = Provider<bool>((ref) {
  final r = ref.watch(resultProvider);
  if (r == null || r.segments.isEmpty) return false;
  final now = ref.watch(nowProvider);
  return r.segments.any((s) => s.end == null && !s.start.isAfter(now));
});

class AppStateNotifier extends AsyncNotifier<StoredState> {
  static const _uuid = Uuid();

  FiqhStore get _store => ref.read(storeProvider);

  @override
  Future<StoredState> build() => _store.load();

  StoredState get _current => state.value ?? const StoredState();

  /// يطبّق جوابًا عبر الآلة ويحفظ الفرق: الملف، المفاتيح، الأحداث الجديدة أو المعدَّلة.
  /// يعيد الجلسة الناتجة (قد تحمل سلّمًا جاريًا تتابعه الشاشة).
  ///
  /// أحداث الجلسة = أحداث التقويم المشتقة ثم المخزَّنة؛ فما يُحفظ هو ما بعد
  /// الإزاحة. والملف يُحفظ كما أعادته الآلة (بما فيه العادة المشتقة).
  Future<QuestionSession> answer(QuestionSession session, Question q, Reply reply) async {
    // لا يُقرأ machineProvider من هنا (يعتمد على هذه الحالة عبر الإعدادات: دور).
    final before = _current;
    final machine = QuestionMachine(FiqhTime(clockFromSettings(before.settings)));
    final after = machine.apply(session, q, reply);
    final offset = session.events.length - before.events.length;
    var next = before;
    if (!identical(after.profile, session.profile)) {
      await _store.saveProfile(after.profile);
      next = next.copyWith(profile: after.profile);
    }
    if (!identical(after.settled, before.settled)) {
      await _store.saveSettled(after.settled);
      next = next.copyWith(settled: after.settled);
    }
    if (!identical(after.explained, before.explained)) {
      await _store.saveExplained(after.explained);
      next = next.copyWith(explained: after.explained);
    }
    if (!identical(after.events, session.events)) {
      // الآلة إما تُلحق حدثًا أو تستبدل حدثًا في موضعه (السقط).
      final stored = [...before.events];
      for (var i = offset; i < after.events.length; i++) {
        final e = after.events[i];
        if (i - offset < stored.length) {
          if (!identical(stored[i - offset].event, e)) {
            final se = StoredEvent(stored[i - offset].id, e);
            await _store.upsertEvent(se);
            stored[i - offset] = se;
          }
        } else {
          final se = StoredEvent(_uuid.v4(), e);
          await _store.upsertEvent(se);
          stored.add(se);
        }
      }
      next = next.copyWith(events: stored);
    }
    state = AsyncData(next);
    return after;
  }

  /// حفظ أيام الدم كاملة (التقويم مصدرها).
  Future<void> saveMarks(List<BloodDay> marks) async {
    final sorted = [...marks]..sort((a, b) => a.day.compareTo(b.day));
    await _store.saveMarks(sorted);
    state = AsyncData(_current.copyWith(marks: sorted));
  }

  /// تبديل يوم: إضافته دمًا أو إزالته.
  Future<void> toggleDay(DateTime day) async {
    final d = BloodDay.normalize(day);
    final marks = _current.marks;
    if (marks.any((m) => m.day == d)) {
      await saveMarks(marks.where((m) => m.day != d).toList());
    } else {
      await saveMarks([...marks, BloodDay(d)]);
    }
  }

  /// تلوين مدى كاملًا دمًا (السحب).
  Future<void> markRange(DateTime from, DateTime to) async {
    var a = BloodDay.normalize(from);
    var b = BloodDay.normalize(to);
    if (b.isBefore(a)) (a, b) = (b, a);
    final marks = [..._current.marks];
    for (var d = a; !d.isAfter(b); d = HijriDate.nextDay(d)) {
      if (!marks.any((m) => m.day == d)) marks.add(BloodDay(d));
    }
    await saveMarks(marks);
  }

  /// تعديل تفاصيل يوم (الصفات، ليلًا أو نهارًا، الساعة).
  Future<void> updateDay(BloodDay day) => saveMarks([for (final m in _current.marks) m.day == day.day ? day : m]);

  Future<void> addEvent(FiqhEvent e) async {
    final se = StoredEvent(_uuid.v4(), e);
    await _store.upsertEvent(se);
    state = AsyncData(_current.copyWith(events: [..._current.events, se]));
  }

  /// تعديل حدث في موضعه (مثل تصحيح وقته) بالمعرّف نفسه.
  Future<void> updateEvent(StoredEvent e) async {
    await _store.upsertEvent(e);
    state = AsyncData(_current.copyWith(events: [for (final x in _current.events) x.id == e.id ? e : x]));
  }

  /// استبدال كل البيانات بنسخة مستوردة.
  Future<void> importState(StoredState s) async {
    await _store.replaceAll(s);
    state = AsyncData(s);
  }

  Future<void> deleteEvent(String id) async {
    await _store.deleteEvent(id);
    state = AsyncData(_current.copyWith(events: _current.events.where((e) => e.id != id).toList()));
  }

  /// إلغاء تسوية سؤال حتى يُعاد (مثلًا بعد حذف حدث).
  Future<void> unsettle(String key) async {
    final settled = {..._current.settled}..remove(key);
    await _store.saveSettled(settled);
    state = AsyncData(_current.copyWith(settled: settled));
  }

  Future<void> updateSettings(AppSettings s) async {
    await _store.saveSettings(s);
    state = AsyncData(_current.copyWith(settings: s));
  }

  Future<void> updateProfile(FiqhProfile p) async {
    await _store.saveProfile(p);
    state = AsyncData(_current.copyWith(profile: p));
  }

  Future<void> clearAll() async {
    await _store.clearAll();
    state = AsyncData(StoredState(settings: _current.settings));
  }
}
