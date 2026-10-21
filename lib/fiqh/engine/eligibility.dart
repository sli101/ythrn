import '../model/day_state.dart';
import '../model/events.dart';
import '../model/habit_state.dart';
import '../model/rule_ref.dart';
import '../model/tri.dart';
import '../time/fiqh_time.dart';
import 'hayd_engine.dart';
import 'segments.dart';

/// مدخلات الأهلية (الوحدة H1).
class EligibilityInputs {
  const EligibilityInputs({
    this.ageLunarYears = const Tri.unknown(UnknownKind.dontRemember),
    this.doubtsNine = false,
    this.doubtsSixty = false,
    this.hysterectomy = const Tri.unknown(UnknownKind.dontRemember),
    this.pregnant = const Tri.unknown(UnknownKind.dontRemember),
    this.isQurashi = const Tri.unknown(UnknownKind.dontRemember),
  });

  /// العمر بالسنين القمرية عند بدء الدم (٣٥٤٫٣٦٧ يومًا للسنة).
  final Tri<double> ageLunarYears;

  /// لا تدري هل أكملت التسع (ج م٤٨٧).
  final bool doubtsNine;

  /// لا تدري هل أكملت الستين (ج م٤٨٩): تبني على عدمه.
  final bool doubtsSixty;

  final Tri<bool> hysterectomy;
  final Tri<bool> pregnant;

  /// لا أثر لها على الحكم الملزم عند السيستاني؛ تُحفظ للاحتياط الاستحبابي المؤجَّل.
  final Tri<bool> isQurashi;

  static const lunarYearDays = 354.367;

  static double ageAt(DateTime birth, DateTime at) => at.difference(birth).inMinutes / Duration.minutesPerDay / lunarYearDays;
}

/// الأهلية وتمييز جنس الدم (H1، H2): تمهيد قبل المحرك وتعقيب بعده.
class EligibilityResolver {
  const EligibilityResolver(this.time);
  final FiqhTime time;

  /// الأحداث التي يراها المحرك، وما حُكم عليه مسبقًا بأنه ليس من الدماء الثلاثة.
  ({List<FiqhEvent> events, List<StateInterval> ghayr, List<RuleRef> notices}) preprocess(List<FiqhEvent> events, DateTime now) {
    final sorted = [...events]..sort((a, b) => a.at.compareTo(b.at));
    final out = <FiqhEvent>[];
    final ghayr = <StateInterval>[];
    final notices = <RuleRef>[];
    final starts = sorted.whereType<BloodStart>().toList();
    final stops = sorted.whereType<BloodStop>().toList();
    final sources = sorted.whereType<SourceNote>().toList();
    final vtests = sorted.whereType<VirginityTest>().toList();
    DateTime? lastKeptStart;
    final dropped = <BloodStart>{};

    DateTime? stopAfter(DateTime t) {
      for (final s in stops) {
        if (s.at.isAfter(t)) return s.at;
      }
      return null;
    }

    for (final b in starts) {
      // H2-04: ما ليس بدم أو مشكوك فيه طاهر، إلا في أواخر حيض قائم (ضمن عشرته).
      if (!b.isBlood.isKnown || b.isBlood.valueOrNull == false) {
        final withinHayd = lastKeptStart != null && b.at.isBefore(time.tenDaysEndAt(lastKeptStart).value);
        if (b.isBlood.valueOrNull == false || !withinHayd) {
          ghayr.add(StateInterval(b.at, stopAfter(b.at), DayState.tahir,
              const [RuleRef('H2-04', 'ليس دمًا أو مشكوك في كونه دمًا: طاهر لا يوجب غسلًا ولا وضوءًا')]));
          dropped.add(b);
          continue;
        }
        notices.add(const RuleRef('H2-03', 'المشكوك في أواخر حيض قائم يُلحق به'));
      }
      // مصدر الدم (H2-01، H2-02، N1-06).
      final src = sources.where((s) => !s.at.isBefore(b.at) && (stopAfter(b.at) == null || s.at.isBefore(stopAfter(b.at)!))).map((s) => s.source).firstOrNull;
      if (src != null) {
        final verdict = _sourceVerdict(src, b, vtests, lastKeptStart);
        if (verdict != null) {
          ghayr.add(StateInterval(b.at, stopAfter(b.at), verdict.$1, verdict.$2, pendingInput: verdict.$3));
          dropped.add(b);
          continue;
        }
      }
      lastKeptStart = b.at;
    }
    for (final e in sorted) {
      if (e is BloodStart && dropped.contains(e)) continue;
      if (e is BloodStop && dropped.any((d) => !d.at.isAfter(e.at) && stopAfter(d.at) == e.at)) continue;
      out.add(e);
    }
    return (events: out, ghayr: ghayr, notices: notices);
  }

  /// حكم مقطع بحسب مصدره: `null` = يبقى للمحرك (قد يكون حيضًا).
  (DayState, List<RuleRef>, String?)? _sourceVerdict(BloodSource src, BloodStart b, List<VirginityTest> vtests, DateTime? lastKeptStart) {
    switch (src) {
      case BloodSource.wound:
        return (DayState.ghayr, const [RuleRef('H2-02', 'دم الجروح والقروح لا حكم للحيض ولا للاستحاضة فيه')], null);
      case BloodSource.virginity:
        return (DayState.ghayr, const [RuleRef('H2-01', 'دم البكارة')], null);
      case BloodSource.labor:
        return (DayState.ghayr, const [RuleRef('N1-06', 'دم المخاض المُحرز بحكم دم الجروح'), RuleRef('H2-02')], null);
      case BloodSource.doubtWoundOrHayd:
        // ج م٥٠٧: حكم غير الحائض، إلا أن تكون حائضًا قبله فيُلحق بقدر الإمكان.
        final attached = lastKeptStart != null && b.at.isBefore(time.tenDaysEndAt(lastKeptStart).value);
        if (attached) return null;
        return (DayState.ghayr, const [RuleRef('H2-02', 'مردد بين الجرح والحيض والاحتمالان معقولان: حكم غير الحائض (ج م٥٠٧)')], null);
      case BloodSource.doubtVirginityOrHayd:
        final test = vtests.where((t) => !t.at.isBefore(b.at)).firstOrNull;
        if (test == null) {
          // تعذر الاختبار: الحالة السابقة؛ وإن جُهلت فالطهارة (م٢١٣).
          final attached = lastKeptStart != null && b.at.isBefore(time.tenDaysEndAt(lastKeptStart).value);
          if (attached) return null;
          return (DayState.tahir, const [RuleRef('H2-01', 'الاختبار واجب طريقيًّا؛ وبلا اختبار تبني على الطهارة إلا مع سبق حيض (م٢١٣)')], 'virginityTest');
        }
        if (test.result == VirginityTestResult.ringed) {
          return (DayState.ghayr, const [RuleRef('H2-01', 'القطنة مطوّقة: دم البكارة')], null);
        }
        return null; // مستنقعة: حيض بقواعده
    }
  }

  /// تعقيب الأهلية على ناتج المحرك (H1).
  EngineResult apply(EngineResult r, EligibilityInputs inputs, HabitState habit, List<FiqhEvent> events) {
    var intervals = r.intervals;
    final notices = [...r.notices];

    // H1-05: استئصال الرحم كاملًا → لا حيض ولا نفاس؛ الدم استحاضة ما لم يُحرز أنه جرح.
    if (inputs.hysterectomy.valueOrNull == true) {
      intervals = intervals.map((iv) => iv.state.isBloodRuling || iv.state == DayState.pending
          ? StateInterval(iv.from, iv.to, DayState.istU, [...iv.trace, const RuleRef('H1-05', 'استُؤصل الرحم: لا حيض ولا نفاس والدم استحاضة')])
          : iv).toList();
      return _copy(r, intervals, notices);
    }

    final age = inputs.ageLunarYears.valueOrNull;
    // H1-01: قبل تسع سنين قمرية لا حيض ولا استحاضة (I1-02).
    if (age != null && age < 9) {
      intervals = intervals.map((iv) => iv.state.isBloodRuling || iv.state.isIstihadha || iv.state == DayState.pending
          ? StateInterval(iv.from, iv.to, DayState.ghayr, [...iv.trace, const RuleRef('H1-01a', 'قبل إكمال التسع لا يكون دم حيض'), const RuleRef('I1-02', 'ولا تتحقق الاستحاضة قبل البلوغ')])
          : iv).toList();
      return _copy(r, intervals, notices);
    }
    // H1-02، H1-06: بعد الستين لا حيض؛ وظائف المستحاضة على الأحوط وجوبًا. الشك في إكمالها: تبني على عدمه.
    if (age != null && age >= 60 && !inputs.doubtsSixty) {
      intervals = intervals.map((iv) => iv.state.isBloodRuling || iv.state.isIstihadha || iv.state == DayState.pending
          ? StateInterval(iv.from, iv.to, iv.state.isIstihadha && iv.state != DayState.istU ? iv.state : DayState.istU,
              [...iv.trace, const RuleRef('H1-02', 'بعد الستين لا تكون له أحكام الحيض'), const RuleRef('H1-06', 'العمل بوظائف المستحاضة على الأحوط وجوبًا')],
              classification: 'ihtiyat_wujubi', pendingInput: iv.pendingInput)
          : iv).toList();
      return _copy(r, intervals, notices);
    }
    if (inputs.doubtsSixty) notices.add(const RuleRef('H1-02', 'الشاكة في إكمال الستين تبني على عدمه (ج م٤٨٩)'));

    // H1-01b: الشاكة في إكمال التسع: فاقد → ليس بحيض؛ واجد → محل إشكال.
    if (inputs.doubtsNine) {
      intervals = intervals.map((iv) {
        if (!iv.state.isBloodRuling) return iv;
        final seg = _segmentAt(r.segments, iv.from);
        final wajid = seg?.propsAt(seg.start) == BloodProps.wajid;
        if (wajid) {
          return StateInterval(iv.from, iv.to, iv.state, [...iv.trace, const RuleRef('H1-01b', 'الشاكة في إكمال التسع ترى دمًا بصفات الحيض: محل إشكال')], classification: 'ishkal');
        }
        return StateInterval(iv.from, iv.to, DayState.istU, [...iv.trace, const RuleRef('H1-01b', 'الشاكة في إكمال التسع: الفاقد ليس بحيض')]);
      }).toList();
    }

    // H1-03b: الحامل ذات الوقت ترى بعد عشرين يومًا من أول عادتها دمًا بصفات الحيض → الجمع.
    if (inputs.pregnant.valueOrNull == true && habit.type.hasTime && habit.anchorDate != null) {
      intervals = intervals.map((iv) {
        if (iv.state != DayState.hayd) return iv;
        final seg = _segmentAt(r.segments, iv.from);
        if (seg == null || seg.propsAt(seg.start) != BloodProps.wajid) return iv;
        final diff = FiqhTime.daysBetween(habit.anchorDate!, seg.start);
        final sinceHabit = diff - 30 * (diff / 30).floor();
        if (sinceHabit >= 20) {
          return StateInterval(iv.from, iv.to, DayState.jam3,
              [...iv.trace, const RuleRef('H1-03b', 'الحامل ذات الوقت بعد عشرين يومًا من أول عادتها بصفات الحيض: الجمع')],
              classification: 'ihtiyat_wujubi');
        }
        return iv;
      }).toList();
      notices.add(const RuleRef('H1-03a', 'الحيض يجتمع مع الحمل'));
    }
    return _copy(r, intervals, notices);
  }

  BloodSegment? _segmentAt(List<BloodSegment> segments, DateTime t) {
    for (final s in segments) {
      if (s.contains(t) || s.start == t) return s;
    }
    return null;
  }

  EngineResult _copy(EngineResult r, List<StateInterval> intervals, List<RuleRef> notices) =>
      EngineResult(intervals: intervals, segments: r.segments, unsupported: r.unsupported, judgedEnd: r.judgedEnd, notices: notices);
}
