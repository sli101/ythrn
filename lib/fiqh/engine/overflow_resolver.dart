import '../model/day_state.dart';
import '../model/events.dart';
import '../model/habit_state.dart';
import '../model/rule_ref.dart';
import '../model/tri.dart';
import '../model/woman_type.dart';

/// خلية يوم داخل حلقة دم: اليوم `index` من بدء الحلقة (٠ = يوم أول الدم).
class DayCell {
  const DayCell({required this.index, required this.blood, this.props, this.spots = false});
  final int index;
  final bool blood;
  final BloodProps? props;
  final bool spots;

  bool get wajid => blood && props == BloodProps.wajid;
}

/// مدى متصل من أيام الدم [start, end] (شاملين).
class BloodRun {
  const BloodRun(this.start, this.end, this.cells);
  final int start;
  final int end;
  final List<DayCell> cells;
  int get length => end - start + 1;
  bool get allWajid => cells.every((c) => c.wajid);
  bool get anyWajid => cells.any((c) => c.wajid);
  bool get allSpots => cells.every((c) => c.spots);
  bool contains(int i) => i >= start && i <= end;
  bool get crossesTen => start < 10 && end >= 10;
}

/// مدخلات تعيين العدد (H7-04، H7-07).
class CountInputs {
  const CountInputs({this.kinCount, this.kinConditionsMet, this.chosenCount});
  final int? kinCount;
  final Tri<bool>? kinConditionsMet;
  final int? chosenCount;

  bool get kinUsable => kinCount != null && kinConditionsMet?.valueOrNull != false;
}

/// حكم يوم داخل الحلقة.
class DayRuling {
  DayRuling(this.state, this.trace, {this.classification = 'fatwa', this.pendingInput});
  DayState state;
  List<RuleRef> trace;
  String classification;
  String? pendingInput;
}

/// ناتج الحلّ: حكم كل يوم من ٠ إلى آخر يوم في الحلقة.
class OverflowResolution {
  const OverflowResolution(this.rulings, {this.pendingInput, this.unsupported});
  final List<DayRuling> rulings;
  final String? pendingInput;
  final String? unsupported;

  int get haydDays => rulings.where((r) => r.state == DayState.hayd).length;

  /// آخر يوم حيض (أو −١).
  int get lastHaydIndex {
    var last = -1;
    for (var i = 0; i < rulings.length; i++) {
      if (rulings[i].state == DayState.hayd) last = i;
    }
    return last;
  }
}

/// حلّ حلقة دم تجاوزت العشرة أو فيها دمان قبل أقل الطهر (H7، H8، H3-05)
/// بحساب الأيام (الوحدة T: اليوم من الفجر إلى المغرب والليلة تتبعه).
///
/// الأصطلاح: «العشرة» = الأيام ٠..٩ من أول الدم. «المدى» = أيام دم متصلة.
/// المدى «المتجاوز» = ما يبدأ قبل العاشر ويستمر إلى ما بعده.
class OverflowResolver {
  const OverflowResolver();

  OverflowResolution resolve({
    required HabitState habit,
    required List<DayCell> cells,
    required CountInputs inputs,

    /// يوم بدء العادة بالنسبة إلى يوم ٠ (قد يكون سالبًا)؛ لذات الوقت.
    int? habitStartIndex,

    /// أيام معلومة من وقت الناسية بالنسبة إلى يوم ٠ (H7-05 م٢٢٤).
    List<int> knownTimeDays = const [],

    /// نافذة الوقت المحصور للناسية [من، إلى] بالنسبة إلى يوم ٠.
    (int, int)? timeWindow,

    /// مدى «أيام العادة» لذات الوقتية (عددها، أو أطول حيضة في تاريخها، أو الافتراض).
    int habitSpan = 3,
  }) {
    final n = cells.length;
    final rulings = List<DayRuling>.generate(n, (i) => DayRuling(cells[i].blood ? DayState.istU : DayState.tahir, const []));
    final runs = _runs(cells);
    if (runs.isEmpty) return OverflowResolution(rulings);

    final hayd = <int>{};
    final trace = <RuleRef>[];
    String? pending;
    var classification = 'fatwa';

    final type = habit.type;

    // ---------------------------------------------------------- بحسب النوع
    _CoreResult core;
    switch (type) {
      case WomanType.vw:
        core = _vw(habit, cells, runs, habitStartIndex, inputs);
      case WomanType.w:
        core = _w(habit, cells, runs, inputs, habit.count);
      case WomanType.v:
        core = _v(habit, cells, runs, habitStartIndex, inputs, null, habitSpan);
      case WomanType.nasC:
        // ناسية العدد حافظة الوقت: كذات الوقتية مع قصّ العدد بذاكرتها (م٢٢٣).
        core = _v(habit, cells, runs, habitStartIndex, inputs, habit.memory, habitSpan);
      case WomanType.nasT:
        // ناسية الوقت: العدد بعادتها إن حفظته وإلا كالمبتدئة؛ الوقت بقيودها (م٢٢٤).
        core = habit.count != null
            ? _w(habit, cells, runs, inputs, habit.count, knownTimeDays: knownTimeDays, timeWindow: timeWindow)
            : _mub(habit, cells, runs, inputs, knownTimeDays: knownTimeDays, timeWindow: timeWindow);
      case WomanType.nasB:
        core = _mub(habit, cells, runs, inputs, knownTimeDays: knownTimeDays, timeWindow: timeWindow, memory: habit.memory);
      case WomanType.mub:
      case WomanType.mud:
        core = _mub(habit, cells, runs, inputs);
    }
    hayd.addAll(core.hayd);
    trace.addAll(core.trace);
    pending = core.pendingInput;
    classification = core.classification;

    // ---------------------------------------------------------- H8-03: واجد مستقل بعد عشرة غير حيض
    if (hayd.isNotEmpty) {
      var lastHayd = hayd.reduce((a, b) => a > b ? a : b);
      for (final r in _wajidRuns(cells)) {
        final tenFaqidBetween = r.start >= lastHayd + 11 &&
            List.generate(r.start - lastHayd - 1, (k) => cells[lastHayd + 1 + k]).every((c) => c.blood && !c.wajid);
        if (tenFaqidBetween && r.length >= 3) {
          final take = r.length > 10 ? 10 : r.length;
          for (var i = r.start; i < r.start + take; i++) {
            hayd.add(i);
          }
          trace.add(const RuleRef('H8-03', 'واجد ≥ ٣ بعد عشرة أيام غير حيض: حيض مستقل'));
          lastHayd = r.start + take - 1;
        }
      }
    }

    // ---------------------------------------------------------- H7-06: مستمرة الدم شهورًا
    if (core.monthlyCount != null && hayd.isNotEmpty) {
      final count = core.monthlyCount!;
      var monthStart = core.monthStart + 30;
      while (monthStart < n) {
        var added = false;
        for (var i = monthStart; i < monthStart + count && i < n; i++) {
          if (cells[i].blood) {
            hayd.add(i);
            added = true;
          }
        }
        if (added) trace.add(const RuleRef('H7-06', 'التحيض في كل شهر بالعدد نفسه'));
        monthStart += 30;
      }
    }

    // ---------------------------------------------------------- التوزيع
    for (var i = 0; i < n; i++) {
      final c = cells[i];
      if (hayd.contains(i)) {
        rulings[i] = DayRuling(DayState.hayd, trace, classification: classification);
      } else if (c.blood) {
        rulings[i] = DayRuling(DayState.istU, [...trace, const RuleRef('H3-03', 'ما ليس حيضًا من الدم استحاضة')]);
      } else {
        // نقاء: بين يومي حيض بلا دم غير حيض بينهما → جمع؛ وإلا طهر.
        final between = _betweenHayd(i, hayd, cells);
        rulings[i] = between
            ? DayRuling(DayState.jam3, const [RuleRef('H3-02', 'النقاء المتخلل: الجمع'), RuleRef('H8-01b')], classification: 'ihtiyat_wujubi')
            : DayRuling(DayState.tahir, const [RuleRef('H3-03')]);
      }
      if (pending != null && hayd.isEmpty) {
        rulings[i] = DayRuling(DayState.pending, trace, pendingInput: pending);
      }
    }
    return OverflowResolution(rulings, pendingInput: pending);
  }

  // ================================================================ الأنواع

  /// ذات العادة الوقتية والعددية (H7-01، ج م٥٥٩–٥٦٥، H8-01a).
  _CoreResult _vw(HabitState habit, List<DayCell> cells, List<BloodRun> runs, int? habitStart, CountInputs inputs) {
    final count = habit.count!;
    if (habitStart == null) return _mub(habit, cells, runs, inputs, fixedCount: count);
    final habitEnd = habitStart + count; // حصري
    final inHabit = runs.where((r) => r.end >= habitStart && r.start < habitEnd).toList();
    if (inHabit.isEmpty) {
      // لم ترَ في وقتها: بعدد عادتها في غيره (ج م٥٦٥) أو الواجد (H8-01a).
      final r = _mub(habit, cells, runs, inputs, fixedCount: count);
      r.trace.add(const RuleRef('H7-01a', 'لم ترَ في وقتها: رأت في غيره (ج م٥٦٥)'));
      return r;
    }
    final hayd = <int>{};
    final trace = <RuleRef>[const RuleRef('H7-01a', 'ما في العادة حيض والزائد استحاضة')];
    if (_onlySpotsAfterTen(runs)) {
      // لم يتجاوز الدم الأخير العشرة متصلًا ولا دم ثانٍ بعدها: كل ما قبل العشرة حيض وما بعدها استحاضة (8524).
      for (final c in cells) {
        if (c.blood && c.index < 10) hayd.add(c.index);
      }
      trace.add(const RuleRef('H3-05', 'لم يتجاوز الدم الأخير العشرة: ما قبلها حيض وما بعدها استحاضة (8524)'));
      return _CoreResult(hayd, trace);
    }
    final windowStart = habitEnd - 10 > 0 ? habitEnd - 10 : 0;
    for (final r in inHabit) {
      for (final c in r.cells) {
        if (c.index >= windowStart && c.index < habitEnd) hayd.add(c.index);
      }
    }
    if (hayd.any((i) => i < habitStart)) trace.add(const RuleRef('H7-01a', 'تعجيل عرفي ضمن العشرة (ج م٥٦٣)'));

    // تكميل العدد من المجاور عند دم متصل بدأ في أثناء العادة أو انتهى قبلها (ج م٥٦٠).
    if (runs.length == 1 && hayd.length < count) {
      final r = runs.first;
      var last = hayd.isEmpty ? r.start - 1 : hayd.reduce((a, b) => a > b ? a : b);
      var first = hayd.isEmpty ? r.start : hayd.reduce((a, b) => a < b ? a : b);
      while (hayd.length < count && last + 1 <= r.end && last + 1 < 10) {
        last++;
        hayd.add(last);
      }
      while (hayd.length < count && first - 1 >= r.start) {
        first--;
        hayd.add(first);
      }
      trace.add(const RuleRef('H7-01a', 'تكميل العدد من الأيام المجاورة (ج م٥٦٠)'));
    }

    // الواجد بعد نقاء ضمن العشرة يُلحق بالعادة (م٢٢١، H8-01a استثناء).
    final lastHabitRun = inHabit.last;
    for (final r in runs) {
      if (r.start <= lastHabitRun.end) continue;
      for (final c in r.cells) {
        if (c.wajid && c.index < 10) hayd.add(c.index);
      }
    }
    if (runs.any((r) => r.start > lastHabitRun.end && r.anyWajid)) trace.add(const RuleRef('H7-01a', 'الواجد بعد النقاء يُلحق بما في العادة (م٢٢١)'));
    return _CoreResult(hayd, trace);
  }

  /// ذات العادة العددية (H7-02، ج م٥٧٩، ج م٥٨٢)؛ وناسية الوقت الحافظة للعدد.
  _CoreResult _w(HabitState habit, List<DayCell> cells, List<BloodRun> runs, CountInputs inputs, int? countIn,
      {List<int> knownTimeDays = const [], (int, int)? timeWindow}) {
    var count = countIn!;
    final trace = <RuleRef>[const RuleRef('H7-02')];
    if (habit.deficient != null) count = habit.deficient!.clamp(count);
    final hayd = <int>{};
    if (_onlySpotsAfterTen(runs) && timeWindow == null) {
      for (final c in cells) {
        if (c.blood && c.index < 10) hayd.add(c.index);
      }
      trace.add(const RuleRef('H3-05', 'لم يتجاوز الدم الأخير العشرة: ما قبلها حيض وما بعدها استحاضة (8524)'));
      return _CoreResult(hayd, trace);
    }
    final wajidRuns = _wajidRuns(cells).where((w) => _timeAllowed(w, knownTimeDays, timeWindow)).toList();
    final bloodIdx = cells.where((c) => c.blood).map((c) => c.index).toList();
    if (wajidRuns.isEmpty || _homogeneous(cells)) {
      // لون واحد: من حين الرؤية بعدد العادة.
      final from = timeWindow == null ? 0 : (timeWindow.$1 > 0 ? timeWindow.$1 : 0);
      for (var i = from; i < from + count; i++) {
        if (i < cells.length && cells[i].blood) hayd.add(i);
      }
      trace.add(const RuleRef('H7-02', 'لون واحد: من حين الرؤية بعدد العادة'));
      return _CoreResult(hayd, trace);
    }
    final w = wajidRuns.first;
    if (w.length == count) {
      hayd.addAll(List.generate(w.length, (k) => w.start + k));
      trace.add(const RuleRef('H7-02', 'أيام الواجد = العدد'));
    } else if (w.length > count) {
      hayd.addAll(List.generate(count, (k) => w.start + k));
      trace.add(const RuleRef('H7-02', 'الواجد أكثر من العدد: بقدر العدد من أوله'));
    } else {
      hayd.addAll(List.generate(w.length, (k) => w.start + k));
      var need = count - w.length;
      // من الدم السابق المتصل به.
      var i = w.start - 1;
      while (need > 0 && i >= 0 && cells[i].blood) {
        hayd.add(i);
        need--;
        i--;
      }
      // ثم اللاحق (يومًا بيوم، والنقاء بينها جمع) ضمن العشرة.
      var j = w.end + 1;
      final bound = (hayd.reduce((a, b) => a < b ? a : b)) + 10;
      while (need > 0 && j < cells.length && j < bound) {
        if (cells[j].blood) hayd.add(j);
        need--;
        j++;
      }
      trace.add(const RuleRef('H7-02', 'الواجد أقل من العدد: تكميل من السابق ثم اللاحق (ج م٥٧٩ ج، ج م٥٨٢)'));
    }
    if (bloodIdx.isEmpty) return _CoreResult(hayd, trace);
    return _CoreResult(hayd, trace);
  }

  /// ذات العادة الوقتية فقط (H7-03، ج م٥٧٠–٥٧٥، 8523)؛ وناسية العدد الحافظة للوقت.
  _CoreResult _v(HabitState habit, List<DayCell> cells, List<BloodRun> runs, int? habitStart, CountInputs inputs, NasiyaMemory? memory, int habitSpan) {
    final trace = <RuleRef>[const RuleRef('H7-03')];
    if (habitStart == null) return _mub(habit, cells, runs, inputs, memory: memory);
    final start = habitStart < 0 ? 0 : habitStart;
    // رأت في وقتها: بدء الدم قبل العادة بما لا يزيد على يومين أو في أثناء أيامها.
    final sawInTime = habitStart <= 2 && habitStart > -habitSpan && runs.any((r) => r.contains(start));
    if (!sawInTime || start >= cells.length) {
      final r = _mub(habit, cells, runs, inputs, memory: memory);
      r.trace.add(const RuleRef('H7-03', 'لم ترَ في وقتها (ج م٥٧٣)'));
      return r;
    }
    final primary = runs.firstWhere((r) => r.contains(start), orElse: () => runs.firstWhere((r) => r.start >= start));
    final hayd = <int>{};
    final tenEnd = start + 10; // حصري

    if (!primary.crossesTen && primary.end < tenEnd - 1) {
      // الدم في وقتها انقطع قبل العشرة (8523): ما قبل العشرة حيض؛ المدى الأخير
      // المتجاوز: واجد → حيض إلى تمام العشرة، فاقد → استحاضة.
      for (final r in runs) {
        if (r.start < primary.start) continue;
        final crosses = r.start < tenEnd && r.end >= tenEnd;
        if (crosses) {
          if (r.allWajid) {
            for (final c in r.cells) {
              if (c.index < tenEnd) hayd.add(c.index);
            }
            trace.add(const RuleRef('H3-05', 'الأخير المتجاوز بصفة الحيض: حيض إلى تمام العشرة (8523)'));
          } else {
            trace.add(const RuleRef('H3-05', 'الأخير المتجاوز بصفة الاستحاضة: استحاضة (8523)'));
          }
          break;
        }
        if (r.start >= tenEnd) break;
        for (final c in r.cells) {
          if (c.index >= start && c.index < tenEnd) hayd.add(c.index);
        }
      }
      trace.add(const RuleRef('H7-03', 'ما قبل العشرة في وقتها حيض بصفات أو بدونها'));
      return _CoreResult(hayd, trace);
    }

    // الدم في وقتها متصل متجاوز: البداية من أول الوقت (ج م٥٧١–٥٧٢).
    final wajidAtStart = cells.length > start && cells[start].wajid ? _wajidRuns(cells).firstWhere((w) => w.contains(start)) : null;
    if (wajidAtStart != null && wajidAtStart.length >= 3) {
      for (final c in wajidAtStart.cells) {
        if (c.index < tenEnd) hayd.add(c.index);
      }
      trace.add(const RuleRef('H7-03', 'واجد ٣–١٠ في أول الوقت: هو الحيض (ج م٥٧٢ ب١)'));
      // واجد لاحق لا يفصله إلا نقاء يُلحق ضمن العشرة (ج م٥٧٥).
      _attachWajidAfterGaps(cells, hayd, tenEnd);
      return _CoreResult(hayd, trace);
    }
    final picked = _pickCount(habit, inputs, memory, trace);
    if (picked.count == null) return _CoreResult(hayd, trace, pendingInput: picked.pending, classification: picked.classification);
    for (var i = start; i < start + picked.count! && i < cells.length; i++) {
      if (cells[i].blood) hayd.add(i);
    }
    // إلحاق الواجد الواقع ضمن العشرة من أول الوقت (ج م٥٧٢ ب٢، ج).
    for (final c in cells) {
      if (c.wajid && c.index >= start && c.index < tenEnd) hayd.add(c.index);
    }
    trace.add(const RuleRef('H7-03', 'من أول الوقت بعدد الأقارب/المختار مع إلحاق الواجد ضمن العشرة (ج م٥٧٢)'));
    return _CoreResult(hayd, trace, classification: picked.classification);
  }

  /// المبتدئة والمضطربة (H7-04)، ومن يُعيَّن عددها بالأقارب/الاختيار، و8525، وH8-01a.
  _CoreResult _mub(HabitState habit, List<DayCell> cells, List<BloodRun> runs, CountInputs inputs,
      {int? fixedCount, NasiyaMemory? memory, List<int> knownTimeDays = const [], (int, int)? timeWindow}) {
    final trace = <RuleRef>[const RuleRef('H7-04a')];
    final hayd = <int>{};
    final primary = runs.first;
    final wajidRuns = _wajidRuns(cells).where((w) => _timeAllowed(w, knownTimeDays, timeWindow)).toList();
    if (wajidRuns.isEmpty && _wajidRuns(cells).isNotEmpty) trace.add(const RuleRef('H7-05a', 'الواجد خارج ما تعلمه من وقتها: فاقدة للتمييز (م٢٢٤)'));

    // دمان كلٌّ ٣–١٠ وبينهما نقاء والمجموع > ١٠ ولا عادة وقتية (H8-01a).
    if (runs.length >= 2 && !primary.crossesTen) {
      final second = runs.skip(1).firstWhere((r) => r.length >= 3, orElse: () => runs.last);
      if (second.length >= 3 && second.end >= 10 && primary.length >= 3) {
        final pw = primary.allWajid;
        final sw = second.allWajid;
        final pf = primary.cells.every((c) => c.props == BloodProps.faqid);
        final sf = second.cells.every((c) => c.props == BloodProps.faqid);
        final BloodRun winner;
        if ((pw && sf) || (sw && pf)) {
          winner = sw ? second : primary;
          trace.add(const RuleRef('H8-01a', 'دمان: الواجد حيض والفاقد استحاضة'));
        } else {
          winner = primary;
          trace.add(const RuleRef('H8-01a', 'دمان تساويا في الصفات: الأول حيض'));
        }
        final take = winner.length > 10 ? 10 : winner.length;
        hayd.addAll(List.generate(take, (k) => winner.start + k));
        if (winner == primary) _attachSpotsWithinTen(cells, runs, hayd, primary, trace);
        return _CoreResult(hayd, trace);
      }
    }

    if (!primary.crossesTen && primary.length >= 3) {
      // الدم الأول (٣–١٠) واللطخات قبل العشرة حيض؛ الأخير المتجاوز استحاضة (8525).
      hayd.addAll(List.generate(primary.length > 10 ? 10 : primary.length, (k) => primary.start + k));
      _attachSpotsWithinTen(cells, runs, hayd, primary, trace);
      trace.add(const RuleRef('H3-05', 'الدم الأول واللطخات قبل العشرة حيض والأخير المتجاوز استحاضة (8525)'));
      return _CoreResult(hayd, trace);
    }

    // دم متصل متجاوز: التمييز (H7-04a).
    if (wajidRuns.isNotEmpty && !_homogeneous(cells)) {
      final w = wajidRuns.first;
      if (w.length >= 3 && w.length <= 10) {
        hayd.addAll(List.generate(w.length, (k) => w.start + k));
        trace.add(const RuleRef('H7-04a', 'الواجد ٣–١٠ حيض والفاقد استحاضة'));
        _clampMemory(hayd, memory, cells, trace);
        return _CoreResult(hayd, trace);
      }
      final picked = fixedCount != null ? _Picked(fixedCount, 'fatwa') : _pickCount(habit, inputs, memory, trace);
      if (picked.count == null) return _CoreResult(hayd, trace, pendingInput: picked.pending, classification: picked.classification);
      if (w.length > 10) {
        hayd.addAll(List.generate(picked.count!, (k) => w.start + k).where((i) => i <= w.end));
        trace.add(const RuleRef('H7-04a', 'الواجد أكثر من العشرة: بقدر العدد من أوله'));
      } else {
        hayd.addAll(List.generate(w.length, (k) => w.start + k));
        var need = picked.count! - w.length;
        var j = w.end + 1;
        while (need > 0 && j < cells.length && cells[j].blood && j < w.start + 10) {
          hayd.add(j);
          need--;
          j++;
        }
        trace.add(const RuleRef('H7-04a', 'الواجد أقل من ثلاثة: تكميل العدد من اللاحق'));
      }
      return _CoreResult(hayd, trace, classification: picked.classification);
    }

    // لون واحد: الأقارب ثم العدد، من ابتداء الدم (أو من أول الوقت المحصور).
    final picked = fixedCount != null ? _Picked(fixedCount, 'fatwa') : _pickCount(habit, inputs, memory, trace);
    if (picked.count == null) return _CoreResult(hayd, trace, pendingInput: picked.pending, classification: picked.classification);
    final from = timeWindow == null ? primary.start : (timeWindow.$1 > primary.start ? timeWindow.$1 : primary.start);
    for (var i = from; i < from + picked.count! && i < cells.length; i++) {
      if (cells[i].blood) hayd.add(i);
    }
    trace.add(const RuleRef('H7-04a', 'لون واحد: بعدد الأقارب أو المختار من ابتداء الدم'));
    return _CoreResult(hayd, trace, classification: picked.classification, monthlyCount: picked.count, monthStart: from);
  }

  // ================================================================ أدوات

  /// اختيار العدد: الأقارب بالشرطين، وإلا المختار ٣–١٠، مع القصّ بالناقصة
  /// وبذاكرة الناسية (H7-04، H7-07، H4-06، H7-05).
  _Picked _pickCount(HabitState habit, CountInputs inputs, NasiyaMemory? memory, List<RuleRef> trace) {
    int? count;
    var cls = 'fatwa';
    if (inputs.kinUsable) {
      count = inputs.kinCount;
      trace.add(const RuleRef('H7-07', 'عدد عادة قريبة بالشرطين'));
      if (habit.type == WomanType.mud) {
        cls = 'ihtiyat_wujubi';
        trace.add(const RuleRef('H7-04b', 'رجوع المضطربة إلى النساء: احتياط وجوبي'));
      }
    } else if (inputs.chosenCount != null) {
      count = inputs.chosenCount;
      trace.add(const RuleRef('H7-04a', 'اختيار العدد بين الثلاثة والعشرة'));
    } else {
      return _Picked(null, cls, pending: 'chosenCount');
    }
    if (habit.deficient != null) {
      final c = habit.deficient!.clamp(count!);
      if (c != count) trace.add(const RuleRef('H4-06', 'قصّ العدد بالعادة الناقصة'));
      count = c;
    }
    if (memory != null) {
      var c = count!;
      if (memory.countMin != null && c < memory.countMin!) c = memory.countMin!;
      if (memory.countMax != null && c > memory.countMax!) c = memory.countMax!;
      if (c != count) trace.add(const RuleRef('H7-05a', 'قصّ العدد بما تتذكره الناسية (م٢٢٣)'));
      count = c;
    }
    return _Picked(count, cls);
  }

  void _clampMemory(Set<int> hayd, NasiyaMemory? memory, List<DayCell> cells, List<RuleRef> trace) {
    if (memory == null || hayd.isEmpty) return;
    final sorted = hayd.toList()..sort();
    if (memory.countMax != null && sorted.length > memory.countMax!) {
      hayd.removeAll(sorted.sublist(memory.countMax!));
      trace.add(const RuleRef('H7-05a', 'قصّ العدد بأكبر محتمل (م٢٢٣)'));
    }
    if (memory.countMin != null && sorted.length < memory.countMin!) {
      var j = sorted.last + 1;
      while (hayd.length < memory.countMin! && j < cells.length && cells[j].blood) {
        hayd.add(j);
        j++;
      }
      trace.add(const RuleRef('H7-05a', 'إكمال العدد إلى المتيقن (م٢٢٣)'));
    }
  }

  /// اللطخات والدماء ضمن العشرة بعد الدم الأول، ما عدا المدى الأخير المتجاوز.
  void _attachSpotsWithinTen(List<DayCell> cells, List<BloodRun> runs, Set<int> hayd, BloodRun primary, List<RuleRef> trace) {
    var attached = false;
    for (final r in runs) {
      if (r.start <= primary.end) continue;
      if (r.crossesTen) break;
      if (r.start >= 10) break;
      if (r.length >= 3 && !r.allSpots) break; // دم ثانٍ مستقل: H8-01a يحكمه
      for (final c in r.cells) {
        if (c.index < 10) {
          hayd.add(c.index);
          attached = true;
        }
      }
    }
    if (attached) trace.add(const RuleRef('H3-05', 'ما ينزل أثناء العشرة ملحق بالحيض'));
  }

  /// واجد لاحق لا يفصله عن الحيض إلا نقاء يُلحق ضمن العشرة (ج م٥٧٥).
  void _attachWajidAfterGaps(List<DayCell> cells, Set<int> hayd, int tenEnd) {
    var last = hayd.reduce((a, b) => a > b ? a : b);
    for (var i = last + 1; i < tenEnd && i < cells.length; i++) {
      final c = cells[i];
      if (!c.blood) continue;
      if (!c.wajid) break;
      hayd.add(i);
      last = i;
    }
  }

  /// لا مدى يتجاوز العشرة متصلًا، وما بعدها لطخات أو دم أقل من ثلاثة أيام (ليس دمًا ثانيًا).
  static bool _onlySpotsAfterTen(List<BloodRun> runs) =>
      !runs.any((r) => r.crossesTen) && !runs.any((r) => r.start >= 10 && r.length >= 3 && !r.allSpots);

  bool _timeAllowed(BloodRun w, List<int> knownTimeDays, (int, int)? window) {
    if (knownTimeDays.isNotEmpty && !knownTimeDays.every(w.contains)) return false;
    if (window != null && (w.end < window.$1 || w.start > window.$2)) return false;
    return true;
  }

  bool _betweenHayd(int i, Set<int> hayd, List<DayCell> cells) {
    var before = false;
    for (var k = i - 1; k >= 0; k--) {
      if (hayd.contains(k)) {
        before = true;
        break;
      }
      if (cells[k].blood) return false;
    }
    if (!before) return false;
    for (var k = i + 1; k < cells.length; k++) {
      if (hayd.contains(k)) return true;
      if (cells[k].blood) return false;
    }
    return false;
  }

  /// مدى = أيام دم متصلة متجانسة في كونها لطخات أو دمًا مستمرًا.
  static List<BloodRun> _runs(List<DayCell> cells) {
    final runs = <BloodRun>[];
    int? start;
    for (var i = 0; i <= cells.length; i++) {
      final blood = i < cells.length && cells[i].blood;
      final s = start;
      final breakHere = s != null && (!blood || cells[i].spots != cells[s].spots);
      if (breakHere) {
        runs.add(BloodRun(s, i - 1, cells.sublist(s, i)));
        start = null;
      }
      if (blood && start == null) start = i;
    }
    return runs;
  }

  static List<BloodRun> _wajidRuns(List<DayCell> cells) {
    final runs = <BloodRun>[];
    int? start;
    for (var i = 0; i <= cells.length; i++) {
      final w = i < cells.length && cells[i].wajid;
      if (w && start == null) start = i;
      if (!w && start != null) {
        runs.add(BloodRun(start, i - 1, cells.sublist(start, i)));
        start = null;
      }
    }
    return runs;
  }

  /// لون واحد: لا يجتمع واجد وغير واجد في أيام الدم.
  static bool _homogeneous(List<DayCell> cells) {
    final blood = cells.where((c) => c.blood);
    final anyW = blood.any((c) => c.wajid);
    final anyNot = blood.any((c) => !c.wajid);
    return !(anyW && anyNot);
  }
}

class _CoreResult {
  _CoreResult(this.hayd, this.trace, {this.pendingInput, this.classification = 'fatwa', this.monthlyCount, this.monthStart = 0});
  final Set<int> hayd;
  final List<RuleRef> trace;
  final String? pendingInput;
  final String classification;

  /// لمستمرة الدم: العدد الذي يُعاد كل شهر وبداية الشهر (H7-06).
  final int? monthlyCount;
  final int monthStart;
}

class _Picked {
  const _Picked(this.count, this.classification, {this.pending});
  final int? count;
  final String classification;
  final String? pending;
}
