import '../model/day_state.dart';
import '../model/events.dart';
import '../model/habit_state.dart';
import '../model/rule_ref.dart';
import '../time/fiqh_time.dart';
import 'hayd_engine.dart';
import 'istihadha.dart';

/// تنبيه مرتبط بلحظة (غسل، قضاء، صلاة الآن…).
class Alert {
  const Alert(this.at, this.rule, this.text, {this.classification = 'fatwa'});
  final DateTime at;
  final RuleRef rule;
  final String text;
  final String classification;

  @override
  String toString() => '$at ${rule.id}: $text';
}

/// ما يجب قضاؤه (H9-08، H9-14).
class QadaLedger {
  const QadaLedger({this.prayerDays = const [], this.fastDays = const [], this.fastDaysIhtiyat = const []});

  /// أيام تُقضى صلواتها: عوملت حيضًا فتركت الصلاة ثم تبين أنها ليست بحيض.
  final List<DateTime> prayerDays;

  /// أيام رمضان التي لم تُصم لحيض أو نفاس: قضاؤها واجب.
  final List<DateTime> fastDays;

  /// أيام الجمع (النقاء المتخلل) في رمضان: قضاء الصوم احتياطًا.
  final List<DateTime> fastDaysIhtiyat;

  bool get isEmpty => prayerDays.isEmpty && fastDays.isEmpty && fastDaysIhtiyat.isEmpty;
}

/// الوظائف والمحرمات والمباحات لكل حالة، والتنبيهات عند المعالم، وسجل القضاء (H9).
class DutiesResolver {
  const DutiesResolver(this.time, {this.wuduAndPrayer = const Duration(minutes: 20), this.tayammumAndPrayer = const Duration(minutes: 7), this.ghuslAndRakaa = const Duration(minutes: 25), this.tayammumAndRakaa = const Duration(minutes: 5)});

  final FiqhTime time;

  /// افتراضات مدد الطهارة والصلاة (H9-11) لتقدير القضاء والصلاة آخر الوقت.
  final Duration wuduAndPrayer;
  final Duration tayammumAndPrayer;
  final Duration ghuslAndRakaa;
  final Duration tayammumAndRakaa;

  // ================================================================ الوظائف بحسب الحالة

  List<Duty> forState(DayState state, {IstihadhaFlow flow = IstihadhaFlow.continuous}) => switch (state) {
        DayState.hayd => [..._haydProhibitions(), ..._haydPermissions(), ..._haydAfter()],
        DayState.nifas => [..._haydProhibitions(nifas: true), ..._haydPermissions(), ..._haydAfter(nifas: true)],
        DayState.jam3 => [
            const Duty('الجمع بين أحكام الطاهرة والحائض: الغسل احتياطًا ثم الصلاة والصوم', RuleRef('H3-02'), classification: 'ihtiyat_wujubi'),
            ..._haydProhibitions(),
            const Duty('الطلاق في النقاء المتخلل محل إشكال', RuleRef('H9-06b'), classification: 'ishkal', kind: DutyKind.alert),
          ],
        DayState.jam3N => [
            const Duty('الجمع بين أعمال الطاهرة وتروك النفساء', RuleRef('N1-04'), classification: 'ihtiyat_wujubi'),
            ..._haydProhibitions(nifas: true),
          ],
        DayState.jam3M => [
            const Duty('الجمع بين تروك الحائض وأعمال المستحاضة حتى تتم الثلاثة أو ينقطع', RuleRef('H5-02b'), classification: 'ihtiyat_wujubi'),
            ...const IstihadhaDuties().forLevel(null),
            ..._haydProhibitions(),
          ],
        DayState.jam3NM => [
            const Duty('الجمع بين تروك النفساء وأعمال المستحاضة إلى تمام العشرة', RuleRef('N2-03'), classification: 'ihtiyat_wujubi'),
            ...const IstihadhaDuties().forLevel(null),
            ..._haydProhibitions(nifas: true),
          ],
        DayState.istU => const IstihadhaDuties().forLevel(null),
        DayState.istQ => const IstihadhaDuties().forLevel(IstihadhaLevel.qalila),
        DayState.istM => const IstihadhaDuties().forLevel(IstihadhaLevel.mutawassita),
        DayState.istK => const IstihadhaDuties().forLevel(IstihadhaLevel.kathira, flow: flow),
        DayState.tahir => const [Duty('وظيفة الطاهرة', RuleRef('H3-03'), kind: DutyKind.permission)],
        DayState.ghayr => const [Duty('ليس من الدماء الثلاثة: تتوضئين وتصلين', RuleRef('H2-02'))],
        DayState.pending => const [Duty('لا يُحكم قبل الجواب عن المدخل المطلوب', RuleRef('H5-05'), kind: DutyKind.alert)],
      };

  List<Duty> _haydProhibitions({bool nifas = false}) {
    final five = nifas ? 'ihtiyat_wujubi' : 'fatwa';
    final fiveRule = nifas ? const RuleRef('N3-02') : const RuleRef('H9-02a');
    return [
      const Duty('لا تصح الصلاة ولا الصوم ولا الاعتكاف ولا الطواف الواجب', RuleRef('H9-01a'), kind: DutyKind.prohibition),
      const Duty('الطواف المندوب', RuleRef('H9-01b'), classification: 'ihtiyat_wujubi', kind: DutyKind.prohibition),
      const Duty('مس كتابة القرآن واسم الله تعالى', RuleRef('H9-02a'), kind: DutyKind.prohibition),
      Duty('قراءة آيات السجدة من سور العزائم الأربع', fiveRule, classification: five, kind: DutyKind.prohibition),
      Duty('اللبث في المساجد ودخولها بغير اجتياز', fiveRule, classification: five, kind: DutyKind.prohibition),
      Duty('وضع شيء في المسجد ولو في حال الاجتياز أو من خارجه', nifas ? fiveRule : const RuleRef('H9-02b'), classification: 'ihtiyat_wujubi', kind: DutyKind.prohibition),
      Duty('دخول المسجد الحرام ومسجد النبي ولو اجتيازًا', fiveRule, classification: five, kind: DutyKind.prohibition),
      const Duty('دخول حجرة الضريح للمعصومين؛ ويجوز الصحن والأروقة', RuleRef('H9-02c'), classification: 'ihtiyat_wujubi', kind: DutyKind.prohibition),
      const Duty('الوطء في القُبُل حرام بلا كفارة', RuleRef('H9-04a'), kind: DutyKind.prohibition),
      const Duty('ترك إدخال بعض الحشفة', RuleRef('H9-04b'), classification: 'ihtiyat_wujubi', kind: DutyKind.prohibition),
      const Duty('ترك وطء الدُّبُر مع عدم الرضا؛ ومع الرضا مكروه كراهة شديدة', RuleRef('H9-04c'), classification: 'ihtiyat_wujubi', kind: DutyKind.prohibition),
      const Duty('الطلاق والظهار لا يصحان', RuleRef('H9-06a'), kind: DutyKind.prohibition),
      const Duty('غسل الجمعة قبل النقاء لا يصح', RuleRef('H9-09b'), classification: 'ihtiyat_wujubi', kind: DutyKind.prohibition),
    ];
  }

  List<Duty> _haydPermissions() => const [
        Duty('الاجتياز في سائر المساجد، وقراءة غير العزائم، والدعاء والذكر والزيارة وحضور المجالس', RuleRef('H9-03'), kind: DutyKind.permission),
        Duty('الاستمتاع بغير الوطء جائز، ويُكره ما تحت المئزر', RuleRef('H9-04a'), kind: DutyKind.permission),
        Duty('يصح منها الوضوء وغسل الجنابة ومس الميت والأغسال المندوبة', RuleRef('H9-09a'), kind: DutyKind.permission),
        Duty('يستحب التحشي والوضوء وقت كل صلاة والجلوس في مصلاها ذاكرة لله', RuleRef('H9-10'), kind: DutyKind.permission),
      ];

  List<Duty> _haydAfter({bool nifas = false}) => [
        const Duty('عند النقاء: غسل الحيض (ترتيبي أو ارتماسي) ويغني عن الوضوء', RuleRef('H9-07a')),
        const Duty('قضاء ما فات من صوم رمضان دون الصلاة', RuleRef('H9-08a')),
        const Duty('قضاء الصوم المنذور المعين', RuleRef('H9-08b'), classification: 'ihtiyat_wujubi'),
        const Duty('بعد النقاء وقبل الغسل: الوطء جائز مع غسل الفرج قبله؛ ومس المصحف والعزائم حرام حتى الغسل؛ والمكث في المسجد يُترك', RuleRef('H9-04d'), classification: 'ihtiyat_wujubi', kind: DutyKind.alert),
        if (nifas) const Duty('النفساء بحكم الحائض في الاستبراء والاستظهار', RuleRef('N3-01'), kind: DutyKind.alert),
      ];

  // ================================================================ التنبيهات وسجل القضاء

  /// يضيف إلى الناتج التنبيهات عند المعالم وسجل القضاء.
  EngineResult annotate(EngineResult r, List<FiqhEvent> events, HabitState habit, {List<(DateTime, DateTime)> ramadan = const []}) {
    final alerts = <Alert>[];
    final sorted = [...r.intervals]..sort((a, b) => a.from.compareTo(b.from));
    final ramadanNotes = events.whereType<RamadanNote>().toList();

    for (var k = 0; k < sorted.length; k++) {
      final iv = sorted[k];
      final next = k + 1 < sorted.length ? sorted[k + 1] : null;
      final prev = k > 0 ? sorted[k - 1] : null;

      // بدء الحيض/النفاس في أثناء وقت صلاة (H9-11).
      if (iv.state.isBloodRuling && (prev == null || !prev.state.isBloodRuling)) {
        alerts.addAll(_onsetAlerts(iv.from));
      }

      // انتهاء الحيض/النفاس (طهر بعد حكم دم).
      if ((iv.state == DayState.tahir || iv.state.isIstihadha) && prev != null && (prev.state == DayState.hayd || prev.state == DayState.nifas) && !iv.from.isBefore(prev.to ?? iv.from)) {
        final end = iv.from;
        alerts.add(Alert(end, const RuleRef('H9-07a'), prev.state == DayState.nifas ? 'اغتسلي غسل النفاس' : 'اغتسلي غسل الحيض'));
        alerts.add(Alert(end, const RuleRef('H9-04d'), 'قبل الغسل: الوطء جائز مع غسل الفرج قبله، ومس المصحف حرام، والمكث في المسجد يُترك احتياطًا', classification: 'ihtiyat_wujubi'));
        alerts.addAll(_endAlerts(end));
        // النقاء ليلًا في رمضان (H9-15).
        if (!time.isDaytime(end)) {
          final nextFajr = time.clock.fajr(time.fiqhDayOf(end).add(const Duration(days: 1)));
          final ramadanTomorrow = _isRamadan(nextFajr, ramadan) || ramadanNotes.any((n) => n.isRamadan && !n.at.isAfter(nextFajr) && n.at.isAfter(end.subtract(const Duration(days: 1))));
          if (ramadanTomorrow) {
            alerts.add(Alert(nextFajr, const RuleRef('H9-15'), 'اغتسلي قبل أذان الصبح، وإن ضاق الوقت فتيممي قبل الفجر؛ وإلا بطل صوم الغد'));
          }
        }
      }
      // مدخل معلَّق.
      if (iv.pendingInput != null && (prev == null || prev.pendingInput != iv.pendingInput)) {
        alerts.add(Alert(iv.from, iv.trace.isEmpty ? const RuleRef('H5-05') : iv.trace.last, 'مطلوب: ${iv.pendingInput}'));
      }
      if (next == null) break;
    }

    return EngineResult(
      intervals: r.intervals,
      segments: r.segments,
      unsupported: r.unsupported,
      judgedEnd: r.judgedEnd,
      notices: r.notices,
      alerts: alerts,
      qada: _qada(r, events, habit, ramadan),
    );
  }

  /// نافذة الصلاة التي تقع فيها اللحظة: (الاسم، البداية، النهاية).
  (String, DateTime, DateTime)? _prayerWindow(DateTime t) {
    final day = DateTime(t.year, t.month, t.day);
    final c = time.clock;
    for (final d in [day.subtract(const Duration(days: 1)), day]) {
      final windows = [
        ('الصبح', c.fajr(d), c.sunrise(d)),
        ('الظهرين', c.dhuhr(d), c.maghrib(d)),
        ('العشاءين', c.maghrib(d), c.midnight(d)),
      ];
      for (final w in windows) {
        if (!t.isBefore(w.$2) && t.isBefore(w.$3)) return w;
      }
    }
    return null;
  }

  List<Alert> _onsetAlerts(DateTime t) {
    final w = _prayerWindow(t);
    if (w == null) return const [];
    final elapsed = t.difference(w.$2);
    if (elapsed >= wuduAndPrayer) {
      return [Alert(t, const RuleRef('H9-11a'), 'إن لم تكوني صليت ${w.$1} فقضاؤها واجب (مضى من الوقت ما يسع الطهارة والصلاة)')];
    }
    if (elapsed >= tayammumAndPrayer) {
      return [Alert(t, const RuleRef('H9-11b'), 'إن لم تكوني صليت ${w.$1} فقضاؤها على الأحوط وجوبًا (أمكن التيمم)', classification: 'ihtiyat_wujubi')];
    }
    return const [];
  }

  List<Alert> _endAlerts(DateTime t) {
    final w = _prayerWindow(t);
    if (w == null) return const [];
    final remaining = w.$3.difference(t);
    if (remaining >= ghuslAndRakaa) {
      return [Alert(t, const RuleRef('H9-11a'), 'بقي من وقت ${w.$1} ما يسع الغسل وركعة: صلي الآن')];
    }
    if (remaining >= tayammumAndRakaa) {
      return [Alert(t, const RuleRef('H9-11d'), 'ضاق الوقت عن الغسل: تيممي وصلي ${w.$1} الآن', classification: 'ihtiyat_wujubi')];
    }
    return const [];
  }

  bool _isRamadan(DateTime t, List<(DateTime, DateTime)> ranges) => ranges.any((r) => !t.isBefore(r.$1) && t.isBefore(r.$2));

  /// سجل القضاء (H9-14، H9-08، H9-12، H3-02).
  QadaLedger _qada(EngineResult r, List<FiqhEvent> events, HabitState habit, List<(DateTime, DateTime)> ramadan) {
    final prayerDays = <DateTime>{};
    final fastDays = <DateTime>{};
    final fastIhtiyat = <DateTime>{};
    final sorted = [...r.intervals]..sort((a, b) => a.from.compareTo(b.from));

    // الصلوات: أيام عوملت حيضًا ظاهرًا ثم انتهت استحاضة.
    for (final seg in r.segments) {
      final candidate = sorted.where((iv) => iv.covers(seg.start) || iv.from == seg.start).firstOrNull;
      if (candidate == null) continue;
      // من أخرجتها الأهلية (السن، الاستئصال) لم تُعامَل حيضًا قط فلا قضاء من هذا الباب (H1).
      if (candidate.state == DayState.ghayr || (candidate.state.isIstihadha && candidate.trace.any((t) => t.id.startsWith('H1-')))) continue;
      // النفاس من لحظته بلا ثلاثة؛ والحيض بالرؤية لذات الوقت، وإلا بعد تمام الثلاثة.
      final onsetHayd = candidate.state == DayState.nifas || candidate.trace.any((t) => t.id == 'H5-01' || (t.id == 'H5-02a' && t.note != null));
      final provisionalFrom = onsetHayd ? seg.start : time.threeDaysCompleteAt(seg.start).value;
      final limitDays = habit.type.hasCount && habit.count != null ? habit.count! : 10;
      final provisionalTo = DateTime(seg.start.year, seg.start.month, seg.start.day + limitDays, seg.start.hour, seg.start.minute);
      final segEnd = seg.end ?? provisionalTo;
      final to = segEnd.isBefore(provisionalTo) ? segEnd : provisionalTo;
      if (!to.isAfter(provisionalFrom)) continue;
      for (final iv in sorted) {
        if (!iv.state.isIstihadha) continue;
        final from = iv.from.isAfter(provisionalFrom) ? iv.from : provisionalFrom;
        final end = iv.to == null || iv.to!.isAfter(to) ? to : iv.to!;
        if (!end.isAfter(from)) continue;
        var day = time.fiqhDayOf(from);
        while (time.clock.fajr(day).isBefore(end)) {
          if (time.clock.fajr(day.add(const Duration(days: 1))).isAfter(from)) prayerDays.add(day);
          day = day.add(const Duration(days: 1));
        }
      }
    }
    // الصوم: أيام رمضان التي حُكم فيها بالحيض أو النفاس (الحيض بعد المغرب لا يبطل صوم اليوم H9-12)، والجمع احتياطًا.
    if (ramadan.isNotEmpty) {
      for (final iv in sorted) {
        if (!(iv.state == DayState.hayd || iv.state == DayState.nifas || iv.state == DayState.jam3 || iv.state == DayState.jam3N)) continue;
        var day = time.fiqhDayOf(iv.from);
        final end = iv.to ?? time.clock.fajr(day.add(const Duration(days: 1)));
        while (time.clock.fajr(day).isBefore(end)) {
          final fajr = time.clock.fajr(day);
          final maghrib = time.clock.maghrib(day);
          final coversDaytime = iv.from.isBefore(maghrib) && end.isAfter(fajr);
          if (coversDaytime && _isRamadan(fajr, ramadan)) {
            (iv.state == DayState.jam3 || iv.state == DayState.jam3N ? fastIhtiyat : fastDays).add(day);
          }
          day = day.add(const Duration(days: 1));
        }
      }
      // أيام القضاء الصلاتي في رمضان لم تُصم أيضًا (عوملت حيضًا).
      for (final day in prayerDays) {
        if (_isRamadan(time.clock.fajr(day), ramadan)) fastDays.add(day);
      }
    }
    return QadaLedger(
      prayerDays: prayerDays.toList()..sort(),
      fastDays: fastDays.toList()..sort(),
      fastDaysIhtiyat: fastIhtiyat.toList()..sort(),
    );
  }
}
