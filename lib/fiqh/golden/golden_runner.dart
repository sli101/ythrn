import '../fiqh.dart';
import 'events_from_scenario.dart';
import 'golden_case.dart';
import 'scenario.dart';

/// نتيجة فحص واحد في حالة ذهبية.
class GoldenCheck {
  const GoldenCheck(this.name, this.ok, [this.reason]);
  final String name;
  final bool ok;
  final String? reason;

  @override
  String toString() => '${ok ? '✓' : '✗'} $name${reason == null ? '' : ': $reason'}';
}

/// تقرير تشغيل حالة: الفحوص (ناجحة أو فاشلة بسببها)، وما لم يُغطَّ بعد،
/// وناتج المحرك إن حُسب (للمستكشف).
class GoldenReport {
  final List<GoldenCheck> checks = [];
  final List<String> pending = [];
  EngineResult? engineResult;
  HabitState? habit;
  Scenario? scenario;

  Iterable<GoldenCheck> get failures => checks.where((c) => !c.ok);
  bool get passed => failures.isEmpty;

  void check(String name, bool ok, String reason) => checks.add(GoldenCheck(name, ok, ok ? null : reason));
  void equal(String name, Object? actual, Object? expected, [String? extra]) =>
      check(name, actual == expected, 'متوقع $expected، الناتج $actual${extra == null ? '' : '\n$extra'}');
}

/// يشغّل حالة ذهبية على المحرك والآلة ويعيد تقريرًا بلا رمي استثناء؛ الاختبارات
/// تتحقق من خلوّه من الفشل، والمستكشف يعرضه (`docs/SPEC.md` §١١ ٨).
///
/// يغطي: الزمن (T)، آلة العادة (H4)، حالات الأيام، العدّ، القضاء والتنبيهات،
/// المدخلات المعلَّقة، وآلة الأسئلة (`nextQuestion`، `questionPath`).
GoldenReport runGoldenCase(GoldenCase c) {
  final sc = Scenario(c);
  final time = sc.time;
  const machine = HabitMachine();
  final r = GoldenReport()..scenario = sc;

  HabitState? habit;
  HabitState computeHabit() {
    var s = sc.initialHabit();
    for (final cycle in sc.historyCycles()) {
      s = machine.update(s, cycle).value;
    }
    return r.habit = s;
  }

  EngineResult? hayd;
  String? haydSkipReason;
  EngineResult? computeHayd() {
    if (c.pendingOwner != null) {
      haydSkipReason = 'بانتظار المالك';
      return null;
    }
    final p = c.profile;
    final events = eventsFromScenario(c, sc);
    final lastEnd = p['lastBloodEnd'] as int?;
    final tw = sc.memoryTimeWindow();
    final mem = ((c.profile['habit'] as Map<String, dynamic>?)?['memory'] as Map<String, dynamic>?);
    final res = FiqhEngine(time).evaluate(
      habit: computeHabit(),
      events: events,
      now: sc.fajr(c.lastDay + 1),
      lastBloodEnd: lastEnd == null ? null : sc.maghrib(lastEnd),
      inputs: sc.countInputs(),
      knownTimeDays: mem?['knownDays'] == null ? const [] : [for (final d in mem!['knownDays'] as List<dynamic>) sc.fajr(d as int)],
      timeWindow: tw == null ? null : (sc.fajr(tw.$1), sc.fajr(tw.$2 + 1)),
      eligibility: sc.eligibilityInputs(),
    );
    r.engineResult = res;
    if (!res.isFullyCovered) {
      haydSkipReason = res.unsupported.map((u) => u.unit).toSet().join('،');
      return null;
    }
    return res;
  }

  var haydComputed = false;
  EngineResult? ensureHayd() {
    if (!haydComputed) {
      hayd = computeHayd();
      haydComputed = true;
    }
    return hayd;
  }

  for (final e in c.expected) {
    final assertion = e['assert'] as String?;
    if (assertion == null) {
      final days = e['days'] as String;
      final expected = e['state'] as String;
      final h = ensureHayd();
      if (h == null) {
        r.pending.add('days $days → $expected (${haydSkipReason ?? "غير مغطى"})');
        continue;
      }
      for (var day = GoldenCase.dayRangeStart(days); day <= GoldenCase.dayRangeEnd(days); day++) {
        final actual = goldenDayState(sc, h, day);
        if (actual == null) {
          r.check('يوم $day', false, 'لا حالة');
          continue;
        }
        r.check('يوم $day = $expected', goldenStateMatches(expected, actual), 'الناتج ${actual.code}\n${h.intervals.join("\n")}');
      }
      final cls = e['classification'] as String?;
      if (cls != null) {
        final iv = h.at(sc.fajr(GoldenCase.dayRangeStart(days)).add(const Duration(hours: 6)));
        r.equal('التصنيف $days', iv?.classification, cls);
      }
      continue;
    }
    final at = e['at'] as String?;
    final value = e['value'];
    switch (assertion) {
      case 'threeDaysCompleteAt':
        r.equal(assertion, time.threeDaysCompleteAt(sc.firstBloodAt()!).value, sc.instant(at!));
      case 'tenDaysEndAt':
        r.equal(assertion, time.tenDaysEndAt(sc.firstBloodAt()!).value, sc.instant(at!));
      case 'minTuhrEndsAt':
        r.equal(assertion, time.minTuhrEndsAt(sc.firstStopAt()!).value, sc.instant(at!));
      case 'overflow':
      case 'noOverflow':
        final end = time.tenDaysEndAt(sc.firstBloodAt()!).value;
        final last = sc.lastBloodAt()!;
        r.check(assertion, last.isAfter(end) == (assertion == 'overflow'), 'end=$end, last=$last');
      case 'habitType':
        habit ??= computeHabit();
        r.equal(assertion, habit.type.code, value, '$habit');
      case 'habitCount':
        habit ??= computeHabit();
        r.equal(assertion, habit.count, value, '$habit');
      case 'habitStart':
        habit ??= computeHabit();
        final next = habit.expectedNextStart;
        if (next == null) {
          r.check(assertion, false, 'لا موعد متوقع ($habit)');
        } else {
          r.equal(assertion, sc.dayOf(next), value);
        }
      case 'haydCount':
        final h = ensureHayd();
        if (h == null) {
          r.pending.add('assert $assertion (${haydSkipReason ?? "غير مغطى"})');
          continue;
        }
        var count = 0;
        for (var day = 1; day <= c.lastDay; day++) {
          if (goldenDayState(sc, h, day) == DayState.hayd) count++;
        }
        r.equal(assertion, count, value, h.intervals.join('\n'));
      case 'qadaPrayers':
      case 'alertGhuslBeforeFajr':
      case 'alertGhuslHayd':
        final h = ensureHayd();
        if (h == null) {
          r.pending.add('assert $assertion (${haydSkipReason ?? "غير مغطى"})');
          continue;
        }
        if (assertion == 'qadaPrayers') {
          r.equal(assertion, h.qada.prayerDays.length, value, '${h.qada.prayerDays}');
        } else {
          final rule = assertion == 'alertGhuslBeforeFajr' ? 'H9-15' : 'H9-07a';
          final matches = h.alerts.where((a) => a.rule.id == rule && (at == null || a.at == sc.instant(at))).toList();
          r.check(assertion, matches.isNotEmpty == (value != false), h.alerts.join('\n'));
        }
      case 'nextQuestion':
      case 'questionPath':
        // آلة الأسئلة على الملف والأحداث. الآن = مغرب آخر يوم أو اللحظة `at`.
        if (c.pendingOwner != null) {
          r.pending.add('assert $assertion (بانتظار المالك)');
          continue;
        }
        final qm = QuestionMachine(time);
        var session = QuestionSession(
          profile: sc.questionProfile(computeHabit()),
          events: eventsFromScenario(c, sc),
          now: at == null ? sc.maghrib(c.lastDay) : sc.instant(at),
          settled: sc.questionSettled(),
        );
        if (assertion == 'nextQuestion') {
          final q = qm.next(session);
          r.equal(assertion, q?.id, value, 'الناتج ${q?.key}');
          continue;
        }
        var broken = false;
        for (final step in (value as List<dynamic>).cast<List<dynamic>>()) {
          final id = step[0] as String;
          final q = qm.next(session);
          if (q?.id != id) {
            r.check('$assertion/$id', false, 'الناتج ${q?.key}');
            broken = true;
            break;
          }
          session = qm.apply(session, q!, _reply(q, step[1], sc));
        }
        if (broken) continue;
        final then = qm.next(session);
        r.equal('$assertion/then', then?.id, e['then'], 'الناتج ${then?.key}');
        final expectedState = e['state'] as String?;
        if (expectedState != null) {
          final t = e['stateAt'] == null ? sc.fajr(c.lastDay).add(const Duration(hours: 6)) : sc.instant(e['stateAt'] as String);
          final actual = qm.evaluate(session).at(t)?.state;
          if (actual == null) {
            r.check('$assertion/state', false, 'لا حالة');
          } else {
            r.check('$assertion/state = $expectedState', goldenStateMatches(expectedState, actual), 'الناتج ${actual.code}');
          }
        }
      case 'pendingInput':
      case 'alertGhuslMayyit':
        final h = ensureHayd();
        if (h == null) {
          r.pending.add('assert $assertion (${haydSkipReason ?? "غير مغطى"})');
          continue;
        }
        if (assertion == 'alertGhuslMayyit') {
          r.check(assertion, h.notices.any((n) => n.id == 'M-06') == (value != false), h.notices.join('، '));
          continue;
        }
        final pendings = h.intervals.where((iv) => iv.pendingInput != null).map((iv) => iv.pendingInput).toSet();
        r.check('$assertion = $value', pendings.contains(value), 'المعلَّق: $pendings');
      default:
        r.pending.add('assert $assertion');
    }
  }
  return r;
}

bool goldenStateMatches(String expected, DayState actual) => switch (expected) {
      'IST' => actual.isIstihadha,
      'NOT_HAYD' => !actual.isBloodRuling && actual != DayState.pending,
      _ => actual.code == expected,
    };

/// حالة اليوم: حكم الدم إن وُجد في نهار اليوم، وإلا الحالة الأطول.
DayState? goldenDayState(Scenario sc, EngineResult r, int day) {
  final from = sc.fajr(day);
  final to = sc.maghrib(day);
  DayState? best;
  var bestLen = 0;
  for (final iv in r.intervals) {
    final a = iv.from.isAfter(from) ? iv.from : from;
    final b = (iv.to == null || iv.to!.isAfter(to)) ? to : iv.to!;
    if (!b.isAfter(a)) continue;
    if (iv.state.isBloodRuling) return iv.state;
    final len = b.difference(a).inMinutes;
    if (len > bestLen) {
      bestLen = len;
      best = iv.state;
    }
  }
  return best;
}

/// جواب حالة ذهبية إلى [Reply] بحسب نوع السؤال: الرموز `dont_understand`
/// و`dont_remember` و`skip`، وإلا قيمة (رقم اليوم للتاريخ).
Reply _reply(Question q, Object? v, Scenario sc) {
  switch (v) {
    case 'dont_understand':
      return Reply.dontUnderstand;
    case 'dont_remember':
      return Reply.dontRemember;
    case 'skip':
      return Reply.skip;
  }
  if (q.kind == QuestionKind.date) return Reply.value(sc.date(v as int));
  return Reply.value(v!);
}
