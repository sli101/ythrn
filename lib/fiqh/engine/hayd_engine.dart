import '../model/day_state.dart';
import '../model/events.dart';
import '../model/habit_state.dart';
import '../model/rule_ref.dart';
import '../model/tri.dart';
import '../model/woman_type.dart';
import '../time/fiqh_time.dart';
import 'duties.dart';
import 'overflow_resolver.dart';
import 'segments.dart';

/// فترة زمنية بحالة واحدة وأثرها.
class StateInterval {
  const StateInterval(this.from, this.to, this.state, this.trace, {this.pendingInput, this.classification = 'fatwa'});
  final DateTime from;

  /// `null` = مفتوحة إلى الآن.
  final DateTime? to;
  final DayState state;
  final List<RuleRef> trace;

  /// للحالة [DayState.pending]: المدخل المطلوب.
  final String? pendingInput;

  /// fatwa | ihtiyat_wujubi | ishkal.
  final String classification;

  bool covers(DateTime t) => !t.isBefore(from) && (to == null || t.isBefore(to!));

  @override
  String toString() => '[$from → ${to ?? "…"}) ${state.code} ← $trace';
}

/// موقع بدء الدم من نافذة عادة ذات الوقت (H5-01، H5-03، H5-04).
enum HabitWindowPosition {
  /// لا عادة وقتية أو لا مرساة.
  noHabit,

  /// في أيام العادة.
  inside,

  /// متقدم عليها بما لا يزيد على التعجيل العرفي (بلا سؤال).
  earlyWithinCustom,

  /// متقدم بأزيد من التعجيل العرفي وفي حدود عشرة أيام: يُسأل هل يصدق التعجيل.
  earlyBeyondCustom,

  /// خارج العادة.
  outside,
}

/// ما لا تغطيه الشريحة الحالية؛ يُرفع للشرائح القادمة بدل اختلاق حكم.
class Unsupported {
  const Unsupported(this.unit, this.reason, this.at);
  final String unit;
  final String reason;
  final DateTime at;

  @override
  String toString() => '$unit: $reason عند $at';
}

class EngineResult {
  const EngineResult({required this.intervals, required this.segments, required this.unsupported, required this.judgedEnd, this.notices = const [], this.alerts = const [], this.qada = const QadaLedger()});
  final List<StateInterval> intervals;

  /// تنبيهات لا تغيّر حالة اليوم (مثل غسل مس الميت للسقط M-06).
  final List<RuleRef> notices;

  /// تنبيهات عند المعالم (غسل، قضاء، صلاة الآن) بلحظاتها (H9).
  final List<Alert> alerts;

  /// ما يجب قضاؤه (H9-08، H9-14).
  final QadaLedger qada;
  final List<BloodSegment> segments;
  final List<Unsupported> unsupported;

  /// نهاية آخر حيض محكوم به (لأقل الطهر القادم).
  final DateTime? judgedEnd;

  bool get isFullyCovered => unsupported.isEmpty;

  StateInterval? at(DateTime t) {
    StateInterval? found;
    for (final i in intervals) {
      if (i.covers(t)) found = i;
    }
    return found;
  }
}

/// محرك الحيض الأساسي: الشريحة ٢.أ (H3، H5، H6 مع T).
///
/// يغطي: حيضة واحدة من أول الدم إلى العشرة، التحيض بالرؤية، تمام الثلاثة،
/// النقاء المتخلل، الانقطاع والاستبراء. ما يتجاوز العشرة (H7) أو يبدأ قبل أقل
/// الطهر (H8) أو النفاس (N) يُعلَّم [Unsupported] ويُترك لشريحته.
class HaydEngine {
  HaydEngine(this.time, {this.earlyHabitDays = 2, this.defaultHabitSpanDays = 3});

  final FiqhTime time;

  /// التعجيل العرفي المقبول بلا سؤال (H5-01: «بيوم أو يومين»).
  final int earlyHabitDays;

  /// افتراض: مدى «أيام العادة» لذات الوقتية فقط إذا لم يُعلم من التاريخ.
  /// يُراجعه المالك (مذكور في TRACKING).
  final int defaultHabitSpanDays;

  /// ملاحظات أثر يعتمد عليها غير المحرك (آلة الأسئلة) لتمييز الفرع المطبَّق.
  static const noteNoReturnConfidence = 'لا اطمئنان بالعود';
  static const noteHesitation = 'التردد: غسل وعمل المستحاضة؛ الاستظهار جائز';
  static const noteEarlyBeyondCustom = 'تقدم بأزيد من التعجيل العرفي';

  EngineResult evaluate({
    required HabitState habit,
    required List<FiqhEvent> events,
    required DateTime now,
    DateTime? lastBloodEnd,
    CountInputs inputs = const CountInputs(),
    List<DateTime> knownTimeDays = const [],
    (DateTime, DateTime)? timeWindow,

    /// بعد عشرة الاستحاضة التالية للنفاس: ذات الوقت تنتظر وقتها ولا ترجع إلى التمييز (N2-04).
    bool afterNifas = false,
  }) {
    final built = SegmentBuilder(time).build(events);
    final segments = built.value;
    final intervals = <StateInterval>[];
    final unsupported = <Unsupported>[];
    DateTime? judgedEnd = lastBloodEnd;
    final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));

    var i = 0;
    while (i < segments.length) {
      var seg = segments[i];

      // ١) أقل الطهر من آخر حيض محكوم به (T-04، H3-03).
      if (judgedEnd != null && !time.minTuhrElapsed(stop: judgedEnd, newStart: seg.start)) {
        intervals.add(StateInterval(seg.start, seg.end, DayState.istU,
            const [RuleRef('H3-03', 'دم قبل مضي عشرة من الحيض الأول ليس بحيض'), RuleRef('T-04')]));
        i++;
        continue;
      }

      // ١ب) بعد النفاس: ذات الوقت لا تتحيض إلا في وقتها (N2-04).
      if (afterNifas && habit.type.hasTime) {
        final window = _nextHabitWindow(habit, seg.start);
        if (window != null && seg.start.isBefore(window.$1)) {
          final segEnd = seg.end ?? now;
          if (!segEnd.isAfter(window.$1)) {
            intervals.add(StateInterval(seg.start, seg.end, DayState.istU, const [RuleRef('N2-04', 'بعد النفاس: ذات الوقت تنتظر أيام عادتها ولا ترجع إلى التمييز')]));
            i++;
            continue;
          }
          intervals.add(StateInterval(seg.start, window.$1, DayState.istU, const [RuleRef('N2-04', 'بعد النفاس: ذات الوقت تنتظر أيام عادتها')]));
          seg = BloodSegment(start: window.$1, end: seg.end, props: seg.propsAt(window.$1), spots: seg.spotsAt(window.$1))
            ..propsChanges.addAll(seg.propsChanges.where((c) => c.at.isAfter(window.$1)));
          segments[i] = seg;
        }
      }

      // ٢) مرشح حيضة: فحص الثلاثة (H3-01، T-02).
      final threeAt = time.threeDaysCompleteAt(seg.start).value;
      final segEnd = seg.end ?? now;
      if (segEnd.isBefore(threeAt)) {
        if (seg.ongoing) {
          // لم تتم الثلاثة بعد والدم جارٍ: حكم ظاهري (H5).
          intervals.add(_onsetInterval(habit, seg, sorted, now, provisional: true));
          i++;
          continue;
        }
        // انقطع قبل الثلاثة → ليس بحيض (H3-01، H3-07، H3-08).
        final onset = _onsetInterval(habit, seg, sorted, seg.end!, provisional: true);
        intervals.add(StateInterval(seg.start, seg.end, DayState.istU, [
          const RuleRef('H3-01', 'لم يستمر ثلاثة أيام'),
          const RuleRef('H3-08'),
          if (onset.state == DayState.hayd) const RuleRef('H5-01', 'انكشف أنه ليس بحيض: قضاء الصلاة'),
          if (onset.state == DayState.jam3M) const RuleRef('H5-02b', 'عملت بوظيفتها فلا قضاء'),
        ]));
        i++;
        continue;
      }

      // ٣) الحلقة: المقاطع المتتابعة التي لا يفصل بينها أقل الطهر (T-04).
      final episode = <BloodSegment>[seg];
      var j = i + 1;
      while (j < segments.length &&
          !time.minTuhrElapsed(stop: segments[j - 1].end ?? now, newStart: segments[j].start)) {
        episode.add(segments[j]);
        j++;
      }
      final cells = _cells(episode, seg.start, now);
      final beyondTen = cells.any((c) => c.blood && c.index >= 10);

      if (beyondTen) {
        // تجاوز العشرة أو دم ثانٍ قبل أقل الطهر: قواعد النوع (H7، H8، H3-05).
        final day0 = time.fiqhDayOf(seg.start);
        final res = const OverflowResolver().resolve(
          habit: habit,
          cells: cells,
          inputs: inputs,
          habitStartIndex: _habitStartIndex(habit, seg.start, day0),
          knownTimeDays: [for (final d in knownTimeDays) _dayIndex(d, day0)],
          timeWindow: timeWindow == null ? null : (_dayIndex(timeWindow.$1, day0), _dayIndex(timeWindow.$2, day0) - 1),
          habitSpan: habit.count ?? _spanFromHistory(habit) ?? defaultHabitSpanDays,
        );
        final ongoing = episode.last.ongoing;
        for (var k = 0; k < res.rulings.length; k++) {
          final r = res.rulings[k];
          final from = k == 0 ? seg.start : time.clock.fajr(day0.add(Duration(days: k)));
          final to = (k == res.rulings.length - 1 && ongoing) ? null : time.clock.fajr(day0.add(Duration(days: k + 1)));
          intervals.add(StateInterval(from, to, r.state, r.trace, classification: r.classification, pendingInput: r.pendingInput));
        }
        judgedEnd = res.lastHaydIndex >= 0 ? time.clock.fajr(day0.add(Duration(days: res.lastHaydIndex + 1))) : judgedEnd;
        i = j;
        continue;
      }

      // ٣ب) حيضة ضمن العشرة: كل دم فيها حيض والنقاء بينها جمع (H3-04، H3-05، H3-02).
      final tenEnd = time.tenDaysEndAt(seg.start).value;
      var cursor = seg.start;
      DateTime? haydEnd;
      for (var k = 0; k < episode.length; k++) {
        final s = episode[k];
        if (k > 0) {
          intervals.add(StateInterval(cursor, s.start, DayState.jam3,
              const [RuleRef('H3-02', 'النقاء المتخلل: الجمع بين أحكام الطاهرة والحائض'), RuleRef('H3-04')],
              classification: 'ihtiyat_wujubi'));
        }
        intervals.add(StateInterval(s.start, s.end, DayState.hayd,
            [const RuleRef('H3-01'), if (k > 0) const RuleRef('H3-05', 'ما ينزل أثناء العشرة حيض') else const RuleRef('H3-04')]));
        cursor = s.end ?? now;
        haydEnd = s.end;
      }

      // ٤) الدم انقطع ظاهرًا قبل العشرة (أو جارٍ): الاستبراء (H6).
      final lastSeg = episode.last;
      if (lastSeg.ongoing) {
        i = j;
        continue;
      }
      final stop = lastSeg.end!;
      final cutoff = _cutoff(habit, sorted, stop, tenEnd, now, lastSeg);
      intervals.addAll(cutoff.intervals);
      if (cutoff.unsupported != null) unsupported.add(cutoff.unsupported!);
      judgedEnd = cutoff.haydEnd ?? haydEnd ?? stop;
      i = j;
    }

    return EngineResult(intervals: fillGaps(intervals, now), segments: segments, unsupported: unsupported, judgedEnd: judgedEnd);
  }

  /// خلايا الأيام لحلقة دم من يوم أول الدم إلى آخر يوم فيه دم.
  List<DayCell> _cells(List<BloodSegment> episode, DateTime start, DateTime now) {
    final day0 = time.fiqhDayOf(start);
    final lastBlood = episode.last.end ?? now;
    final n = time.fiqhDayOf(lastBlood).difference(day0).inDays + 1;
    return List.generate(n, (k) {
      final dayStart = time.clock.fajr(day0.add(Duration(days: k)));
      final dayEnd = time.clock.fajr(day0.add(Duration(days: k + 1)));
      for (final s in episode) {
        final sEnd = s.end ?? now;
        if (s.start.isBefore(dayEnd) && sEnd.isAfter(dayStart)) {
          final at = s.start.isAfter(dayStart) ? s.start : dayStart;
          return DayCell(index: k, blood: true, props: s.propsAt(at), spots: s.spotsAt(at));
        }
      }
      return DayCell(index: k, blood: false);
    });
  }

  int _dayIndex(DateTime t, DateTime day0) => time.fiqhDayOf(t).difference(day0).inDays;

  /// يوم بدء العادة بالنسبة إلى يوم أول الدم (أقرب موعد من مضاعفات الشهر).
  int? _habitStartIndex(HabitState habit, DateTime bloodStart, DateTime day0) {
    if (!habit.type.hasTime && habit.type != WomanType.nasC) return null;
    final anchor = habit.anchorDate;
    if (anchor == null || habit.anchor == HabitAnchor.end) return null;
    final diff = FiqhTime.daysBetween(anchor, bloodStart);
    final n = (diff / 30).round();
    final expected = anchor.add(Duration(days: 30 * n));
    return _dayIndex(expected, day0);
  }

  /// ما لا دم فيه ولا حكم قائم → طهر (وظيفة الطاهرة).
  List<StateInterval> fillGaps(List<StateInterval> intervals, DateTime now) {
    final sorted = [...intervals]..sort((a, b) => a.from.compareTo(b.from));
    // فترة مفتوحة يتلوها حكم لاحق تُغلق عند بدايته.
    for (var k = 0; k < sorted.length - 1; k++) {
      final iv = sorted[k];
      if (iv.to == null) {
        final next = sorted[k + 1].from;
        if (next.isAfter(iv.from)) {
          sorted[k] = StateInterval(iv.from, next, iv.state, iv.trace, classification: iv.classification, pendingInput: iv.pendingInput);
        }
      }
    }
    final out = <StateInterval>[];
    DateTime? cursor;
    for (final iv in sorted) {
      if (cursor != null && iv.from.isAfter(cursor)) {
        out.add(StateInterval(cursor, iv.from, DayState.tahir, const [RuleRef('H3-03', 'لا دم: طهر')]));
      }
      out.add(iv);
      if (iv.to == null) {
        cursor = null;
        break;
      }
      cursor = cursor == null || iv.to!.isAfter(cursor) ? iv.to : cursor;
    }
    if (cursor != null && now.isAfter(cursor)) {
      out.add(StateInterval(cursor, null, DayState.tahir, const [RuleRef('H3-03', 'لا دم: طهر')]));
    }
    return out;
  }

  // ---------------------------------------------------------------- H5

  /// الحكم الظاهري عند بدء الدم قبل تمام الثلاثة.
  StateInterval _onsetInterval(HabitState habit, BloodSegment seg, List<FiqhEvent> events, DateTime until, {required bool provisional}) {
    final trace = <RuleRef>[];
    // ذات الوقت داخل نافذة العادة (H5-01) أو تعجيل عرفي.
    if (habit.type.hasTime && _withinHabitWindow(habit, seg.start, events, trace)) {
      trace.add(const RuleRef('H5-01', 'ذات الوقت تتحيض بمجرد الرؤية'));
      return StateInterval(seg.start, seg.end, DayState.hayd, trace);
    }
    if (habit.type.hasTime) trace.add(const RuleRef('H5-03', 'خارج وقت العادة: كغير ذات الوقت'));
    final props = seg.propsAt(seg.start);
    if (props == BloodProps.wajid) {
      trace.add(const RuleRef('H5-02a', 'واجد للصفات: تتحيض بمجرد الرؤية'));
      return StateInterval(seg.start, seg.end, DayState.hayd, trace);
    }
    final knows = _expectation(events, ExpectationKind.willLastThreeDays, seg.start);
    if (knows == const Tri<bool>.known(true)) {
      trace.add(const RuleRef('H5-02a', 'علمت باستمراره ثلاثة أيام'));
      return StateInterval(seg.start, seg.end, DayState.hayd, trace);
    }
    trace.add(const RuleRef('H5-02b', 'فاقد للصفات مع احتمال الاستمرار: الجمع'));
    trace.add(const RuleRef('H3-06'));
    return StateInterval(seg.start, seg.end, DayState.jam3M, trace, classification: 'ihtiyat_wujubi');
  }

  /// موقع بدء الدم من نافذة العادة لذات الوقت (H5-01، H5-03، H5-04).
  ///
  /// النافذة: [الموعد المتوقع − التعجيل العرفي، الموعد + مدى الأيام). ما تقدم
  /// عليها بأزيد من التعجيل العرفي وفي حدود عشرة أيام يُسأل عنه «هل يصدق
  /// التعجيل عرفًا؟» (الافتراض ٢).
  HabitWindowPosition habitWindowPosition(HabitState habit, DateTime start) {
    final anchor = habit.anchorDate;
    if (!habit.type.hasTime || anchor == null) return HabitWindowPosition.noHabit;
    // أقرب موعد متوقع (مضاعفات الشهر من المرساة).
    final diff = FiqhTime.daysBetween(anchor, start);
    final n = (diff / 30).round();
    final expected = anchor.add(Duration(days: 30 * n));
    final span = habit.count ?? _spanFromHistory(habit) ?? defaultHabitSpanDays;
    final windowStart = expected.subtract(Duration(days: earlyHabitDays));
    final windowEnd = expected.add(Duration(days: span));
    if (!start.isBefore(windowStart) && start.isBefore(windowEnd)) {
      return start.isBefore(expected) ? HabitWindowPosition.earlyWithinCustom : HabitWindowPosition.inside;
    }
    if (start.isBefore(windowStart) && FiqhTime.daysBetween(start, expected) <= 10) {
      return HabitWindowPosition.earlyBeyondCustom;
    }
    return HabitWindowPosition.outside;
  }

  /// هل بدء الدم في أيام عادتها أو قبلها بما يصدق عليه التعجيل؟
  bool _withinHabitWindow(HabitState habit, DateTime start, List<FiqhEvent> events, List<RuleRef> trace) {
    switch (habitWindowPosition(habit, start)) {
      case HabitWindowPosition.noHabit:
        return false;
      case HabitWindowPosition.inside:
        trace.add(const RuleRef('H5-01', 'في أيام العادة'));
        return true;
      case HabitWindowPosition.earlyWithinCustom:
        trace.add(RuleRef('H5-01', 'تعجيل عرفي ≤ $earlyHabitDays'));
        return true;
      case HabitWindowPosition.earlyBeyondCustom:
        // تقدم بأكثر من يومين: يُسأل هل يصدق التعجيل عرفًا.
        final early = _isEarlyHabit(events, start);
        if (early == const Tri<bool>.known(true)) {
          trace.add(const RuleRef('H5-01', 'تعجيل عرفي بإقرارها'));
          return true;
        }
        trace.add(const RuleRef('H5-03', noteEarlyBeyondCustom));
        return false;
      case HabitWindowPosition.outside:
        trace.add(const RuleRef('H5-04', 'بعد انقضاء العادة أو خارجها'));
        return false;
    }
  }

  /// أول نافذة عادة تنتهي بعد [t]: [بدء − تعجيل، بدء + المدى).
  (DateTime, DateTime)? _nextHabitWindow(HabitState habit, DateTime t) {
    final anchor = habit.anchorDate;
    if (anchor == null) return null;
    final span = habit.count ?? _spanFromHistory(habit) ?? defaultHabitSpanDays;
    var n = (FiqhTime.daysBetween(anchor, t) / 30).floor() - 1;
    for (var k = 0; k < 4; k++, n++) {
      final expected = anchor.add(Duration(days: 30 * n));
      final start = expected.subtract(Duration(days: earlyHabitDays));
      final end = expected.add(Duration(days: span));
      if (end.isAfter(t)) return (start, end);
    }
    return null;
  }

  int? _spanFromHistory(HabitState habit) {
    if (habit.history.isEmpty) return null;
    final maxDays = habit.history.map((c) => c.bloodDays).reduce((a, b) => a > b ? a : b);
    return maxDays.ceil();
  }

  // ---------------------------------------------------------------- H6

  ({List<StateInterval> intervals, Unsupported? unsupported, DateTime? haydEnd}) _cutoff(
    HabitState habit,
    List<FiqhEvent> events,
    DateTime stop,
    DateTime tenEnd,
    DateTime now,
    BloodSegment lastSeg,
  ) {
    final intervals = <StateInterval>[];
    // جواب هذا الانقطاع لا جواب انقطاع سابق: ما سُجّل من يوم قبله فصاعدًا.
    final inner = _latest<InnerContinuity>(events, stop, after: stop.subtract(const Duration(days: 1)))?.value ?? const Tri<bool>.unknown(UnknownKind.dontRemember);
    final kursuf = _latest<KursufTest>(events, stop, after: stop);

    if (inner == const Tri<bool>.known(false)) {
      // لا تحتمل بقاءه داخلًا: انتهى الحيض (H6-01).
      intervals.add(StateInterval(stop, null, DayState.tahir, const [RuleRef('H6-01', 'لا تحتمل بقاءه في الداخل: اغتسلت')]));
      return (intervals: intervals, unsupported: null, haydEnd: stop);
    }
    if (kursuf == null) {
      if (!now.isBefore(tenEnd)) {
        // مضت العشرة ولم يعد الدم: انتهى الحيض بالانقطاع الظاهر وإن لم تستبرئ
        // (H6-02؛ `docs/fiqh/assumptions.md` ٦٠). الاستبراء وظيفة وقتها لا حكم رجعي.
        intervals.add(StateInterval(stop, null, DayState.tahir, const [RuleRef('H6-02', 'لم يعد الدم حتى العشرة: انتهى الحيض بالانقطاع'), RuleRef('H6-01')]));
        return (intervals: intervals, unsupported: null, haydEnd: stop);
      }
      // تحتمل (أو لا تدري) ولم تستبرئ: يلزم الاستبراء ولا يجوز ترك العبادة بدونه.
      intervals.add(StateInterval(stop, null, DayState.pending,
          const [RuleRef('H6-01', 'يجب الاستبراء بالقطنة')], pendingInput: 'kursufTest'));
      return (intervals: intervals, unsupported: null, haydEnd: null);
    }
    if (kursuf.result == KursufResult.clean) {
      final willReturn = _expectation(events, ExpectationKind.willReturnBeforeTen, kursuf.at);
      if (willReturn == const Tri<bool>.known(true)) {
        // اطمئنان بالعود قبل العشرة: الجمع (H6-02).
        intervals.add(StateInterval(stop, tenEnd, DayState.jam3,
            const [RuleRef('H6-02', 'تطمئن بعود الدم قبل العشرة: الجمع'), RuleRef('H3-02')], classification: 'ihtiyat_wujubi'));
        intervals.add(StateInterval(tenEnd, null, DayState.tahir, const [RuleRef('H6-02', 'لم يعد الدم: طهر')]));
        return (intervals: intervals, unsupported: null, haydEnd: stop);
      }
      intervals.add(StateInterval(stop, null, DayState.tahir, const [RuleRef('H6-01', 'القطنة نظيفة: اغتسلت وعملت عمل الطاهرة'), RuleRef('H6-02', noteNoReturnConfidence)]));
      return (intervals: intervals, unsupported: null, haydEnd: stop);
    }

    // القطنة ملوثة (H6-03).
    final trace = <RuleRef>[const RuleRef('H6-03')];
    final count = habit.count;
    if (!habit.type.hasCount || count == 10) {
      trace.add(const RuleRef('H6-03', 'مبتدئة أو مضطربة أو ناسية أو عادتها عشرة: تبقى على التحيض إلى العشرة'));
      intervals.add(StateInterval(stop, tenEnd, DayState.hayd, trace));
      return (intervals: intervals, unsupported: null, haydEnd: tenEnd);
    }
    final habitEnd = _habitEndFor(habit, lastSeg.start, count!);
    if (stop.isBefore(habitEnd)) {
      trace.add(const RuleRef('H6-03', 'الاستبراء في أيام العادة: تبقى على التحيض إلى تمامها'));
      intervals.add(StateInterval(stop, habitEnd, DayState.hayd, trace));
      final after = _afterHabit(habit, events, habitEnd, tenEnd, now, trace);
      intervals.addAll(after.intervals);
      return (intervals: intervals, unsupported: after.unsupported, haydEnd: after.haydEnd ?? habitEnd);
    }
    final after = _afterHabit(habit, events, stop, tenEnd, now, trace);
    intervals.addAll(after.intervals);
    return (intervals: intervals, unsupported: after.unsupported, haydEnd: after.haydEnd ?? stop);
  }

  /// بعد انقضاء أيام العادة والقطنة ملوثة: تعلم الانقطاع قبل العشرة → حيض؛
  /// تعلم التجاوز → استحاضة من الآن؛ تتردد → غسل وعمل المستحاضة (الاستظهار
  /// جائز لا واجب، والاحتياط الاستحبابي مؤجَّل بقرار المالك).
  ({List<StateInterval> intervals, Unsupported? unsupported, DateTime? haydEnd}) _afterHabit(
    HabitState habit,
    List<FiqhEvent> events,
    DateTime from,
    DateTime tenEnd,
    DateTime now,
    List<RuleRef> trace,
  ) {
    final willExceed = _expectation(events, ExpectationKind.willExceedTen, from);
    if (willExceed == const Tri<bool>.known(false)) {
      return (
        intervals: [StateInterval(from, tenEnd, DayState.hayd, [...trace, const RuleRef('H6-03', 'تعلم الانقطاع قبل العشرة: تبقى على التحيض')])],
        unsupported: null,
        haydEnd: tenEnd,
      );
    }
    if (willExceed == const Tri<bool>.known(true)) {
      return (
        intervals: [StateInterval(from, null, DayState.istU, [...trace, const RuleRef('H6-03', 'تعلم التجاوز: اغتسلت وعملت عمل المستحاضة')])],
        unsupported: null,
        haydEnd: from,
      );
    }
    return (
      intervals: [StateInterval(from, null, DayState.istU, [...trace, const RuleRef('H6-03', noteHesitation)])],
      unsupported: null,
      haydEnd: from,
    );
  }

  DateTime _habitEndFor(HabitState habit, DateTime bloodStart, int count) {
    if (habit.type.hasTime && habit.anchorDate != null) {
      final diff = FiqhTime.daysBetween(habit.anchorDate!, bloodStart);
      final n = (diff / 30).round();
      final expected = habit.anchorDate!.add(Duration(days: 30 * n));
      final base = bloodStart.isBefore(expected) ? expected : bloodStart;
      return base.add(Duration(days: count));
    }
    return bloodStart.add(Duration(days: count));
  }

  // ---------------------------------------------------------------- أدوات

  T? _latest<T extends FiqhEvent>(List<FiqhEvent> events, DateTime at, {DateTime? after}) {
    T? found;
    for (final e in events) {
      if (e is T && (after == null ? !e.at.isAfter(at.add(const Duration(days: 1))) : !e.at.isBefore(after))) {
        if (found == null || !e.at.isBefore(found.at)) found = e;
      }
    }
    return found;
  }

  Tri<bool>? _expectation(List<FiqhEvent> events, ExpectationKind kind, DateTime at) {
    Expectation? found;
    for (final e in events) {
      if (e is Expectation && e.kind == kind && !e.at.isBefore(at.subtract(const Duration(days: 1)))) {
        if (found == null || !e.at.isBefore(found.at)) found = e;
      }
    }
    return found?.value;
  }

  Tri<bool>? _isEarlyHabit(List<FiqhEvent> events, DateTime at) {
    for (final e in events) {
      if (e is IsEarlyHabit) return e.value;
    }
    return null;
  }
}
