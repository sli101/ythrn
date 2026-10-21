import '../model/day_state.dart';
import '../model/events.dart';
import '../model/habit_state.dart';
import '../model/profile.dart';
import '../model/rule_ref.dart';
import '../time/fiqh_time.dart';
import 'duties.dart';
import 'eligibility.dart';
import 'hayd_engine.dart';
import 'istihadha.dart';
import 'overflow_resolver.dart';
import 'segments.dart';

/// محرك النفاس والسقط: الشريحة ٢.د (N1، N2، N3، M).
///
/// يتولى ما بعد الولادة (أو السقط المتخلق): بدء النفاس بأول دم بعد الولادة،
/// العشرة من فجر اليوم إن كان ليلًا، الدم الواحد والمتعدد عند التجاوز بحسب
/// العدد، النقاء المتخلل، الولادتان، ثم يسلّم ما بعد النفاس إلى محرك الحيض
/// بأقل الطهر من تمام النفاس (عشرة الاستحاضة) وانتظار الوقت لذات الوقت.
class NifasEngine {
  NifasEngine(this.time, {HaydEngine? hayd}) : hayd = hayd ?? HaydEngine(time);

  final FiqhTime time;
  final HaydEngine hayd;

  /// الدم بعد أكثر من عشرة أيام من الولادة لا يستند إليها (N1-01).
  static const maxDelayAfterBirth = Duration(days: 10);

  EngineResult evaluate({
    required HabitState habit,
    required List<FiqhEvent> events,
    required DateTime now,
    DateTime? lastBloodEnd,
    CountInputs inputs = const CountInputs(),
  }) {
    final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
    final notices = <RuleRef>[];
    final births = <DateTime>[];
    for (final e in sorted) {
      if (e is Birth) births.add(e.at);
      if (e is Miscarriage) {
        if (e.countsAsBirth) births.add(e.at);
        if (e.ensouled.valueOrNull == true) notices.add(const RuleRef('M-06', 'سقط بعد ولوج الروح: غسل مس الميت على الأحوط وجوبًا'));
      }
    }
    final unknownStage = sorted.whereType<Miscarriage>().where((m) => m.stage == null).map((m) => m.at).toList();

    if (births.isEmpty) {
      // لا ولادة: سقط غير متخلق فالدم بقواعد الحيض (M-01، M-04)، أو مرحلة مجهولة فمعلَّق.
      final r = hayd.evaluate(habit: habit, events: _withoutBirthEvents(sorted), now: now, lastBloodEnd: lastBloodEnd, inputs: inputs);
      final intervals = [...r.intervals];
      if (unknownStage.isNotEmpty) {
        final at = unknownStage.first;
        intervals.removeWhere((iv) => !iv.from.isBefore(at));
        for (var k = 0; k < intervals.length; k++) {
          final iv = intervals[k];
          if (iv.to == null || iv.to!.isAfter(at)) {
            intervals[k] = StateInterval(iv.from, at, iv.state, iv.trace, classification: iv.classification, pendingInput: iv.pendingInput);
          }
        }
        intervals.add(StateInterval(at, null, DayState.pending, const [RuleRef('M-01', 'مرحلة الجنين مجهولة: لا يُحكم بالنفاس ولا بغيره')], pendingInput: 'miscarriageStage'));
        return EngineResult(intervals: intervals, segments: r.segments, unsupported: r.unsupported, judgedEnd: r.judgedEnd, notices: notices);
      }
      return EngineResult(intervals: intervals, segments: r.segments, unsupported: r.unsupported, judgedEnd: r.judgedEnd,
          notices: [...notices, if (sorted.any((e) => e is Miscarriage)) const RuleRef('M-01', 'سقط لم يتجاوز المضغة: لا نفاس؛ الدم حيض بشروطه وإلا استحاضة')]);
    }

    final allSegments = SegmentBuilder(time).build(_withoutBirthEvents(sorted)).value;
    final intervals = <StateInterval>[];
    final unsupported = <Unsupported>[];
    DateTime? judgedEnd = lastBloodEnd;

    // ١) ما قبل الولادة الأولى: حيض بقواعده أو استحاضة (N1-06).
    final before = _withoutBirthEvents(sorted).where((e) => e.at.isBefore(births.first)).toList();
    if (allSegments.any((s) => s.start.isBefore(births.first))) {
      final cut = [...before, BloodStop(births.first)];
      final r = hayd.evaluate(habit: habit, events: cut, now: births.first, lastBloodEnd: lastBloodEnd, inputs: inputs);
      intervals.addAll(r.intervals.map((iv) => _clip(iv, null, births.first)).whereType<StateInterval>());
      unsupported.addAll(r.unsupported);
      intervals.add(StateInterval(births.first.subtract(const Duration(seconds: 1)), births.first, DayState.tahir, const [RuleRef('N1-06', 'الدم قبل ظهور الولد ليس نفاسًا')]));
      judgedEnd = r.judgedEnd;
    }

    // ٢) كل ولادة ونفاسها.
    for (var k = 0; k < births.length; k++) {
      final b = births[k];
      final nextB = k + 1 < births.length ? births[k + 1] : null;
      final segs = _clipSegments(allSegments, b, nextB ?? now, now);
      if (segs.isEmpty) continue;
      final first = segs.first;
      if (first.start.isAfter(b.add(maxDelayAfterBirth))) {
        // لا نفاس: الدم لا يستند إلى الولادة (N1-01)؛ بقواعد الحيض.
        final r = hayd.evaluate(habit: habit, events: _eventsBetween(sorted, b, nextB), now: nextB ?? now, lastBloodEnd: judgedEnd, inputs: inputs, afterNifas: false);
        intervals.addAll(r.intervals.map((iv) => _clip(iv, b, nextB)).whereType<StateInterval>());
        intervals.add(StateInterval(b, first.start, DayState.tahir, const [RuleRef('N1-01', 'لا نفاس لمن لم ترَ الدم من الولادة أو رأته بعد عشرة أيام')]));
        unsupported.addAll(r.unsupported);
        judgedEnd = r.judgedEnd ?? judgedEnd;
        continue;
      }

      final countStart = time.countingStart(first.start);
      final tenEnd = time.tenDaysEndAt(first.start).value;
      final limit = nextB != null && nextB.isBefore(tenEnd) ? nextB : tenEnd;
      final episode = segs.where((s) => s.start.isBefore(limit)).toList();
      final lastEnd = episode.last.end ?? now;
      final overflow = nextB == null || !nextB.isBefore(tenEnd) ? lastEnd.isAfter(tenEnd) : false;
      final count = _nifasCount(habit);
      final countEnd = count == null ? null : _sameClockAfterDays(countStart, count);
      DateTime? nifasEnd;
      DateTime? delegateFrom;
      final baseTrace = <RuleRef>[const RuleRef('N1-01'), const RuleRef('N1-03', 'العدّ من أول دم بعد الولادة؛ الليلي من فجر التالي')];

      if (!overflow) {
        // كل ما في العشرة نفاس والنقاء بينها جمع (N2-01 ق١، N2-03 ص١، N1-04).
        DateTime cursor = first.start;
        for (var i = 0; i < episode.length; i++) {
          final s = episode[i];
          if (i > 0) {
            intervals.add(StateInterval(cursor, s.start, DayState.jam3N, const [RuleRef('N1-04', 'النقاء المتخلل بين نفاس واحد: الجمع')], classification: 'ihtiyat_wujubi'));
          }
          final to = s.end == null ? null : (nextB != null && s.end!.isAfter(nextB) ? nextB : s.end);
          intervals.add(StateInterval(s.start, to, DayState.nifas, [...baseTrace, const RuleRef('N2-01', 'لم يتجاوز العشرة: جميع الدم نفاس')]));
          cursor = s.end ?? now;
        }
        nifasEnd = episode.last.end;
        delegateFrom = nifasEnd;
        if (nextB != null && nextB.isBefore(tenEnd) && nifasEnd != null && nifasEnd.isBefore(nextB)) {
          // تداخل عشرتي الولادتين: النقاء بينهما جمع (N1-05).
          intervals.add(StateInterval(nifasEnd, nextB, DayState.jam3N, const [RuleRef('N1-05', 'النقاء بين ولادتين مع تداخل عشرتهما: الجمع')], classification: 'ihtiyat_wujubi'));
          nifasEnd = nextB;
          delegateFrom = nextB;
        }
      } else if (episode.length == 1) {
        // دم واحد تجاوز العشرة (N2-01 ق٢، ق٣).
        final end = countEnd ?? tenEnd;
        intervals.add(StateInterval(first.start, end, DayState.nifas, [
          ...baseTrace,
          count != null ? const RuleRef('N2-01', 'ذات عدد في الحيض: نفاسها بمقدار عادتها') : const RuleRef('N2-01', 'لا عدد لها: نفاسها عشرة'),
          if (count != null && habit.type.isNasiya) const RuleRef('N2-01', 'الناسية تجعل أكبر عدد محتمل'),
          if (count != null && !habit.type.hasCount) const RuleRef('N2-02', 'الناقصة: الحد الأعلى'),
        ]));
        nifasEnd = end;
        delegateFrom = end; // الزائد على النفاس استحاضة (N2-01) بأقل الطهر من تمامه
      } else {
        // دماء متعددة في عشرة الولادة وتجاوز الأخير (N2-03 ص٢).
        final end = countEnd ?? tenEnd;
        DateTime cursor = first.start;
        for (var i = 0; i < episode.length; i++) {
          final s = episode[i];
          final sEnd = s.end ?? now;
          if (i > 0 && s.start.isAfter(cursor)) {
            intervals.add(StateInterval(cursor, s.start, DayState.jam3N, const [RuleRef('N1-04', 'النقاء المتخلل: الجمع')], classification: 'ihtiyat_wujubi'));
          }
          // ما في العادة نفاس.
          if (s.start.isBefore(end)) {
            intervals.add(StateInterval(s.start, sEnd.isBefore(end) ? s.end : end, DayState.nifas,
                [...baseTrace, count != null ? const RuleRef('N2-03', 'ذات عدد: ما في مقدار عادتها نفاس') : const RuleRef('N2-03', 'لا عدد: ما قبل العشرة نفاس')]));
          }
          // ما بعد العادة إلى العشرة: الجمع بين تروك النفساء وأعمال المستحاضة.
          if (count != null && sEnd.isAfter(end) && s.start.isBefore(tenEnd)) {
            final from = s.start.isAfter(end) ? s.start : end;
            intervals.add(StateInterval(from, sEnd.isBefore(tenEnd) ? s.end : tenEnd, DayState.jam3NM,
                const [RuleRef('N2-03', 'الخارج عن العادة إلى تمام العشرة: الجمع بين تروك النفساء وأعمال المستحاضة')], classification: 'ihtiyat_wujubi'));
          }
          cursor = sEnd;
        }
        nifasEnd = end;
        delegateFrom = tenEnd; // ما خرج عن العشرة استحاضة (N2-03) بأقل الطهر من تمام النفاس
      }

      // ٣) ما بعد النفاس: عشرة الاستحاضة من تمامه ثم الحيض بقواعده (N2-04).
      final handoff = delegateFrom;
      if (handoff != null && nifasEnd != null && (nextB == null || handoff.isBefore(nextB))) {
        final afterEvents = _eventsBetween(sorted, handoff, nextB);
        final open = allSegments.where((s) => s.start.isBefore(handoff) && (s.end == null || s.end!.isAfter(handoff))).toList();
        if (open.isNotEmpty) {
          afterEvents.insert(0, BloodStart(handoff, props: open.first.propsAt(handoff), spots: open.first.spotsAt(handoff)));
        }
        if (afterEvents.any((e) => e is BloodStart)) {
          final r = hayd.evaluate(habit: habit, events: afterEvents, now: nextB ?? now, lastBloodEnd: nifasEnd, inputs: inputs, afterNifas: true);
          intervals.addAll(r.intervals.map((iv) => _clip(iv, handoff, nextB)).whereType<StateInterval>());
          unsupported.addAll(r.unsupported);
          judgedEnd = r.judgedEnd ?? nifasEnd;
        } else {
          judgedEnd = nifasEnd;
        }
      } else {
        judgedEnd = nifasEnd ?? judgedEnd;
      }
    }

    return EngineResult(
      intervals: hayd.fillGaps(intervals, now),
      segments: allSegments,
      unsupported: unsupported,
      judgedEnd: judgedEnd,
      notices: notices,
    );
  }

  /// عدد النفاس عند التجاوز: عادتها العددية، أو أكبر محتمل للناسية، أو الحد
  /// الأعلى للناقصة (N2-01، N2-02)؛ وإلا لا عدد (فالعشرة).
  int? _nifasCount(HabitState habit) {
    if (habit.type.hasCount && habit.count != null) return habit.count;
    if (habit.type.isNasiya && habit.memory?.countMax != null) return habit.memory!.countMax;
    if (habit.deficient?.max != null) return habit.deficient!.max;
    return null;
  }

  List<FiqhEvent> _withoutBirthEvents(List<FiqhEvent> events) => events.where((e) => e is! Birth && e is! Miscarriage).toList();

  List<FiqhEvent> _eventsBetween(List<FiqhEvent> events, DateTime from, DateTime? to) => _withoutBirthEvents(events)
      .where((e) => !e.at.isBefore(from) && (to == null || e.at.isBefore(to)))
      .toList();

  /// المقاطع المقصوصة على [from, to).
  List<BloodSegment> _clipSegments(List<BloodSegment> segments, DateTime from, DateTime to, DateTime now) {
    final out = <BloodSegment>[];
    for (final s in segments) {
      final sEnd = s.end ?? now;
      if (!sEnd.isAfter(from) || !s.start.isBefore(to)) continue;
      final start = s.start.isBefore(from) ? from : s.start;
      final end = s.end == null ? null : (s.end!.isAfter(to) ? to : s.end);
      out.add(BloodSegment(start: start, end: end, props: s.propsAt(start), spots: s.spotsAt(start))..propsChanges.addAll(s.propsChanges.where((c) => c.at.isAfter(start))));
    }
    return out;
  }

  StateInterval? _clip(StateInterval iv, DateTime? from, DateTime? to) {
    final f = from != null && iv.from.isBefore(from) ? from : iv.from;
    final t = to != null && (iv.to == null || iv.to!.isAfter(to)) ? to : iv.to;
    if (t != null && !t.isAfter(f)) return null;
    return StateInterval(f, t, iv.state, iv.trace, classification: iv.classification, pendingInput: iv.pendingInput);
  }

  static DateTime _sameClockAfterDays(DateTime t, int days) => DateTime(t.year, t.month, t.day + days, t.hour, t.minute, t.second);
}

/// الواجهة الموحدة: نفاس إن وُجدت ولادة أو سقط، وإلا حيض.
class FiqhEngine {
  FiqhEngine(this.time) : _nifas = NifasEngine(time);
  final FiqhTime time;
  final NifasEngine _nifas;

  /// محرك الحيض الأساسي (لآلة الأسئلة: نافذة العادة).
  HaydEngine get hayd => _nifas.hayd;

  EngineResult evaluate({
    required HabitState habit,
    required List<FiqhEvent> events,
    required DateTime now,
    DateTime? lastBloodEnd,
    CountInputs inputs = const CountInputs(),
    List<DateTime> knownTimeDays = const [],
    (DateTime, DateTime)? timeWindow,
    EligibilityInputs eligibility = const EligibilityInputs(),
    List<(DateTime, DateTime)> ramadan = const [],
  }) {
    // تمييز جنس الدم قبل المحرك (H2).
    final elig = EligibilityResolver(time);
    final pre = elig.preprocess(events, now);
    final EngineResult r;
    if (pre.events.any((e) => e is Birth || e is Miscarriage)) {
      r = _nifas.evaluate(habit: habit, events: pre.events, now: now, lastBloodEnd: lastBloodEnd, inputs: inputs);
    } else {
      r = _nifas.hayd.evaluate(
        habit: habit,
        events: pre.events,
        now: now,
        lastBloodEnd: lastBloodEnd,
        inputs: inputs,
        knownTimeDays: knownTimeDays,
        timeWindow: timeWindow,
      );
    }
    // الأهلية بعد المحرك (H1)، ثم تعيين قسم الاستحاضة بالاختبار (I).
    final applied = elig.apply(r, eligibility, habit, pre.events);
    final merged = _nifas.hayd.fillGaps([...applied.intervals, ...pre.ghayr], now);
    final refined = EngineResult(
      intervals: const IstihadhaResolver().refine(merged, events),
      segments: applied.segments,
      unsupported: applied.unsupported,
      judgedEnd: applied.judgedEnd,
      notices: [...applied.notices, ...pre.notices],
    );
    // الوظائف والتنبيهات وسجل القضاء (H9).
    return DutiesResolver(time).annotate(refined, events, habit, ramadan: ramadan);
  }

  /// التقييم من الملف الشخصي الفقهي (`docs/SPEC.md` §٣.١، §٥.١).
  EngineResult evaluateProfile(FiqhProfile profile, List<FiqhEvent> events, DateTime now) {
    final firstBlood = events.whereType<BloodStart>().map((e) => e.at).fold<DateTime?>(null, (a, b) => a == null || b.isBefore(a) ? b : a);
    return evaluate(
      habit: profile.habit,
      events: events,
      now: now,
      lastBloodEnd: profile.lastBloodEnd.valueOrNull,
      inputs: profile.countInputs,
      knownTimeDays: profile.knownTimeDays,
      timeWindow: profile.timeWindow,
      eligibility: profile.eligibilityAt(firstBlood ?? now),
      ramadan: profile.ramadan,
    );
  }
}
