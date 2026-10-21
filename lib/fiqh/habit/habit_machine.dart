import '../model/habit_state.dart';
import '../model/judged_cycle.dart';
import '../model/rule_ref.dart';
import '../model/woman_type.dart';
import '../time/fiqh_time.dart';

/// نوع التوافق بين حيضتين (H4-01): وقتًا وعددًا، أو وقتًا، أو عددًا، أو لا شيء.
enum PairType { vw, v, w, none }

/// آلة حالة العادة (`docs/SPEC.md` §٤؛ H4-01، H4-04، H0-04، ج م٥٣٩–٥٤٢).
class HabitMachine {
  const HabitMachine({
    this.intervalMin = 28,
    this.intervalMax = 31,
    this.timeTolerance = 0.25,
    this.countTolerance = 0.25,
    this.nominalInterval = 30,
  });

  /// الفاصل المتعارف بين بدءي حيضتين بالأيام (ج م٥٤٦: ٢٨–٣١).
  final int intervalMin;
  final int intervalMax;

  /// التسامح العرفي في الوقت: ربع يوم (ج م٥٤٢).
  final double timeTolerance;

  /// التسامح في العدد: ربع يوم (ج م٥٣٩: لا نصف يوم ولا ثلثه).
  final double countTolerance;

  /// «الشهر» ثلاثون يومًا (H0-04).
  final int nominalInterval;

  // ------------------------------------------------------------ المقارنات

  /// هل الفاصل بين لحظتين يُعدّ «شهرًا» عرفًا؟
  bool _isMonthlyInterval(double days) =>
      days >= intervalMin - timeTolerance && days <= intervalMax + timeTolerance;

  bool sameStart(JudgedCycle a, JudgedCycle b) =>
      _isMonthlyInterval(FiqhTime.daysBetween(a.start, b.start));

  bool sameEnd(JudgedCycle a, JudgedCycle b) =>
      _isMonthlyInterval(FiqhTime.daysBetween(a.end, b.end));

  bool sameCount(JudgedCycle a, JudgedCycle b) =>
      (a.bloodDays - b.bloodDays).abs() <= countTolerance;

  /// نوع التوافق بين حيضتين متواليتين (H4-01).
  Traced<PairType> pairType(JudgedCycle a, JudgedCycle b) {
    final time = sameStart(a, b) || sameEnd(a, b);
    final count = sameCount(a, b);
    final t = time && count
        ? PairType.vw
        : time
            ? PairType.v
            : count
                ? PairType.w
                : PairType.none;
    return Traced(t, [RuleRef('H4-01', 'وقت=${time ? "✓" : "✗"} عدد=${count ? "✓" : "✗"}'), const RuleRef('H0-04')]);
  }

  /// هل توافق الحيضة [c] العادة الحالية [s] (وقتًا و/أو عددًا بحسب نوعها)؟
  bool matchesHabit(HabitState s, JudgedCycle c) {
    if (!s.type.hasHabit) return false;
    final timeOk = !s.type.hasTime || _matchesTime(s, c);
    final countOk = !s.type.hasCount || (s.count != null && (c.bloodDays - s.count!).abs() <= countTolerance);
    return timeOk && countOk;
  }

  /// توافق الوقت مع موعد العادة: الفاصل عن [HabitState.anchorDate] مضاعفٌ
  /// صحيح لشهر متعارف (يُحتمل أن تكون الحيضة قبل المرساة أو بعدها).
  bool _matchesTime(HabitState s, JudgedCycle c) {
    final anchor = s.anchorDate;
    if (anchor == null) return false;
    final point = s.anchor == HabitAnchor.start ? c.start : c.end;
    final diff = FiqhTime.daysBetween(anchor, point);
    final n = (diff / nominalInterval).round();
    if (n == 0) return diff.abs() <= timeTolerance;
    return _isMonthlyInterval((diff / n).abs());
  }

  // ------------------------------------------------------------ التحديث

  /// تحديث الحالة بعد إغلاق حيضة (`SPEC` §٤ الخطوات ١–٥).
  Traced<HabitState> update(HabitState state, JudgedCycle cycle) {
    final history = [...state.history, cycle];
    final trace = <RuleRef>[];
    var s = state.copyWith(history: history);

    if (history.length < 2) {
      // حيضة واحدة لا تُثبت ولا تُزيل (ج م٥٥٠)؛ الحالة المصرَّح بها تبقى كما هي.
      trace.add(const RuleRef('H4-04', 'حيضة واحدة لا تغيّر النوع'));
      if (s.type.hasHabit && matchesHabit(state, cycle)) s = _reanchor(s, cycle);
      return Traced(s, trace);
    }

    final a = history[history.length - 2];
    final b = history[history.length - 1];
    final pair = pairType(a, b);

    if (!s.type.hasHabit) {
      // لا عادة بعد (مبتدئة / مضطربة / ناسية تبني عادة جديدة): تثبت بمرتين.
      if (pair.value == PairType.none) {
        trace.add(const RuleRef('H4-01', 'لا توافق → مضطربة'));
        trace.add(const RuleRef('H4-05'));
        return Traced(s.copyWith(type: s.type.isNasiya ? s.type : WomanType.mud), trace);
      }
      trace.addAll(pair.trace);
      trace.add(const RuleRef('H4-01', 'ثبتت العادة بحيضتين متواليتين'));
      return Traced(_establish(s, pair.value, a, b), trace);
    }

    // لها عادة.
    final bMatches = matchesHabit(state, b);
    if (bMatches) {
      trace.add(const RuleRef('H4-04', 'موافقة للعادة'));
      return Traced(_reanchor(s, b), trace);
    }
    // إن كانت [a] موافقة فقد أُعيد إرساء المرساة عليها عند إضافتها، فالفحص
    // على الحالة الحالية صحيح؛ وإن كانت مخالفة فالمرساة لم تتغير بها.
    final aMatches = matchesHabit(state, a);
    if (aMatches) {
      // مخالفة واحدة لا تزيل العادة (ج م٥٥٠)؛ وتغيّر العدد مرة ثم عودته (ج م٥٥١).
      trace.add(const RuleRef('H4-04', 'حيضة واحدة مخالفة لا تزيل العادة (ج م٥٥٠)'));
      return Traced(s, trace);
    }
    if (pair.value != PairType.none) {
      // حيضتان مخالفتان للسابق ومتماثلتان → تبدلت العادة (ج م٥٤٩).
      trace.addAll(pair.trace);
      trace.add(const RuleRef('H4-04', 'تبدلت العادة بحيضتين متماثلتين مخالفتين (ج م٥٤٩)'));
      return Traced(_establish(s, pair.value, a, b), trace);
    }
    // حيضتان مخالفتان ومختلفتان فيما بينهما → زالت العادة (ج م٥٥١).
    trace.add(const RuleRef('H4-04', 'زالت العادة بحيضتين مخالفتين مختلفتين (ج م٥٥١)'));
    trace.add(const RuleRef('H4-05'));
    return Traced(
      s.copyWith(type: WomanType.mud, clearAnchorDate: true, clearCount: true, origin: HabitOrigin.derived),
      trace,
    );
  }

  HabitState _establish(HabitState s, PairType p, JudgedCycle a, JudgedCycle b) {
    final anchor = p == PairType.w ? s.anchor : (sameStart(a, b) ? HabitAnchor.start : HabitAnchor.end);
    final type = switch (p) {
      PairType.vw => WomanType.vw,
      PairType.v => WomanType.v,
      PairType.w => WomanType.w,
      PairType.none => WomanType.mud,
    };
    final hasCount = p == PairType.vw || p == PairType.w;
    final hasTime = p == PairType.vw || p == PairType.v;
    return s.copyWith(
      type: type,
      anchor: anchor,
      anchorDate: hasTime ? (anchor == HabitAnchor.start ? b.start : b.end) : null,
      clearAnchorDate: !hasTime,
      count: hasCount ? _countOf(a, b) : null,
      clearCount: !hasCount,
      origin: HabitOrigin.derived,
    );
  }

  /// عدد العادة من حيضتين متساويتين عرفًا: الأقرب إلى العدد الصحيح.
  int _countOf(JudgedCycle a, JudgedCycle b) => ((a.bloodDays + b.bloodDays) / 2).round();

  /// تحديث المرساة الزمنية بحيضة موافقة حتى لا يتراكم الانحراف.
  HabitState _reanchor(HabitState s, JudgedCycle c) {
    if (!s.type.hasTime) return s;
    return s.copyWith(anchorDate: s.anchor == HabitAnchor.start ? c.start : c.end);
  }
}
