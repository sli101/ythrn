import '../fiqh/fiqh.dart';
import 'intent.dart';
import 'labels.dart';

/// بطاقة الجواب (`docs/UX.md` §٢.٤): جملة واحدة لسؤالها، والتصنيف، وما تفعله
/// الآن، وما تنتبه له. تُبنى من ناتج المحرك بلا حكم جديد.
class AnswerSummary {
  const AnswerSummary({
    required this.state,
    required this.headline,
    required this.classification,
    this.pendingQuestion,
    this.doNow = const [],
    this.watch = const [],
    this.counts = const {},
    this.interval,
    this.notHaydBloodDays = const [],
  });

  final DayState state;
  final String headline;
  final String classification;

  /// نص السؤال الذي ينتظره الحكم إن كان معلَّقًا.
  final String? pendingQuestion;

  /// ما تفعله الآن (الواجبات أولًا، ثلاثة كحد أقصى).
  final List<Duty> doNow;

  /// المعالم القادمة بنصها ولحظتها.
  final List<(DateTime, String)> watch;

  /// عدد الأيام لكل حالة في المدى الملوَّن (للتجاوز والنفاس والقضاء).
  final Map<DayState, int> counts;

  /// الفترة التي بُني عليها الجواب.
  final StateInterval? interval;

  /// أيام دم ملوَّنة حُكم بأنها ليست حيضًا ولا نفاسًا (إن تركت الصلاة فيها فعليها القضاء).
  final List<DateTime> notHaydBloodDays;

  static AnswerSummary build({
    required AskIntent intent,
    required EngineResult r,
    required FiqhTime time,
    required DateTime now,
    required List<FiqhEvent> events,
    required List<BloodDay> marks,
  }) {
    final clock = time.clock;
    final today = time.fiqhDayOf(now);
    final lastStart = events.whereType<BloodStart>().where((e) => !e.at.isAfter(now)).lastOrNull;
    final ongoing = r.segments.any((s) => s.end == null && !s.start.isAfter(now));

    // الفترة المرجعية: الآن إن كان الدم جاريًا أو لا دم؛ وإلا آخر لحظة دم.
    final lastBlood = r.segments.where((s) => !s.start.isAfter(now)).lastOrNull;
    final refAt = (intent == AskIntent.isHayd && !ongoing && lastBlood?.end != null) ? lastBlood!.end!.subtract(const Duration(minutes: 1)) : now;
    final iv = r.at(refAt) ?? r.at(now);
    final state = iv?.state ?? DayState.tahir;

    final counts = <DayState, int>{};
    final notHayd = <DateTime>[];
    if (marks.isNotEmpty) {
      final from = marks.map((m) => m.day).reduce((a, b) => a.isBefore(b) ? a : b);
      final markedDays = {for (final m in marks) m.day};
      for (final e in BloodCalendar.dayStates(r, clock, from: from, to: today).entries) {
        final s = e.value;
        if (s != null && s != DayState.tahir) counts[s] = (counts[s] ?? 0) + 1;
        if (s != null && markedDays.contains(e.key) && (s.isIstihadha || s == DayState.ghayr)) notHayd.add(e.key);
      }
    }

    final pendingQ = iv?.pendingInput != null && QuestionCatalog.has(iv!.pendingInput!) ? QuestionCatalog.byId(iv.pendingInput!).text : null;

    final headline = _headline(intent, state, ongoing: ongoing, counts: counts, qada: r.qada, pending: pendingQ, notHayd: notHayd.length);

    // في الحيض والنفاس ما يهمها الآن التروك؛ وفي الطهر والاستحاضة الواجبات.
    final duties = DutiesResolver(time).forState(state);
    final doNow = (state.isBloodRuling
            ? [...duties.where((d) => d.kind == DutyKind.prohibition), ...duties.where((d) => d.kind == DutyKind.obligation)]
            : [...duties.where((d) => d.kind == DutyKind.obligation), ...duties.where((d) => d.kind == DutyKind.prohibition)])
        .take(3)
        .toList();

    final watch = <(DateTime, String)>[];
    if (lastStart != null && ongoing) {
      final three = time.threeDaysCompleteAt(lastStart.at).value;
      final ten = time.tenDaysEndAt(lastStart.at).value;
      if (three.isAfter(now)) watch.add((three, 'تمام الثلاثة: إن انقطع قبلها فليس بحيض'));
      if (ten.isAfter(now)) watch.add((ten, 'تمام العشرة: ما زاد عليها استحاضة'));
    }
    for (final a in r.alerts.where((a) => a.at.isAfter(now)).take(3)) {
      watch.add((a.at, a.text));
    }
    watch.sort((a, b) => a.$1.compareTo(b.$1));

    return AnswerSummary(
      state: state,
      headline: headline,
      classification: iv?.classification ?? 'fatwa',
      pendingQuestion: pendingQ,
      doNow: doNow,
      watch: watch.take(3).toList(),
      counts: counts,
      interval: iv,
      notHaydBloodDays: notHayd,
    );
  }

  static String _headline(AskIntent intent, DayState s, {required bool ongoing, required Map<DayState, int> counts, required QadaLedger qada, String? pending, int notHayd = 0}) {
    if (s == DayState.pending) return 'الحكم ينتظر جوابك${pending == null ? '' : ': $pending'}';
    String n(int c, String one, String many) => c == 1 ? one : '$c $many';
    switch (intent) {
      case AskIntent.isHayd:
        return switch (s) {
          DayState.hayd => ongoing ? 'هذا الدم حيض؛ اتركي الصلاة والصوم حتى ينقطع' : 'الأيام التي لوّنتِها حيض',
          DayState.jam3M => 'لا يُعلم بعدُ أنه حيض؛ اجمعي بين أعمال المستحاضة وتروك الحائض حتى تتم الثلاثة',
          DayState.jam3 => 'نقاء متخلل: اجمعي بين الغسل والصلاة وتروك الحائض',
          DayState.ghayr => 'هذا ليس من الدماء الثلاثة؛ لا يمنع الصلاة',
          DayState.tahir => ongoing ? 'لا دم محكوم به الآن' : 'الأيام التي لوّنتِها ليست حيضًا',
          DayState.nifas => 'هذا الدم نفاس',
          _ when s.isIstihadha => 'هذا الدم استحاضة؛ صلّي بوظيفة المستحاضة',
          _ => Labels.state(s),
        };
      case AskIntent.stopped:
        return switch (s) {
          DayState.tahir => 'انتهى الحيض؛ اغتسلي غسل الحيض وصلّي',
          DayState.hayd => 'ما زلتِ في حكم الحيض؛ لا غسل بعدُ',
          DayState.jam3 => 'نقاء متخلل: اغتسلي وصلّي احتياطًا واتركي ما يحرم على الحائض',
          DayState.jam3M => 'لم تتم الثلاثة؛ إن لم يعد الدم فليس بحيض',
          _ when s.isIstihadha => 'هذا الدم استحاضة لا حيض؛ وظيفتك وظيفة المستحاضة',
          _ => Labels.state(s),
        };
      case AskIntent.overflow:
        final h = counts[DayState.hayd] ?? 0;
        final i = counts.entries.where((e) => e.key.isIstihadha).fold(0, (a, e) => a + e.value);
        final j = counts.entries.where((e) => e.key.isJam3).fold(0, (a, e) => a + e.value);
        if (h == 0 && i == 0 && j == 0) return 'لا أيام ملوَّنة بعدُ';
        final parts = [
          if (h > 0) n(h, 'يوم واحد حيض', 'أيام حيض'),
          if (i > 0) n(i, 'يوم واحد استحاضة', 'أيام استحاضة'),
          if (j > 0) n(j, 'يوم واحد جمع احتياطي', 'أيام جمع احتياطي'),
        ].join('، ');
        return i > 0 ? '$parts؛ أيام الاستحاضة تُصلّى، فإن تركتِ الصلاة فيها فاقضيها' : parts;
      case AskIntent.nifas:
        final nf = counts[DayState.nifas] ?? 0;
        return switch (s) {
          DayState.nifas => 'هذا الدم نفاس${nf > 0 ? ' ($nf ${nf == 1 ? 'يوم' : 'أيام'} حتى الآن)' : ''}',
          DayState.tahir => nf > 0 ? 'انتهى النفاس بعد $nf ${nf == 1 ? 'يوم' : 'أيام'}؛ اغتسلي غسل النفاس' : 'لا نفاس محكوم به؛ هل سُجّلت الولادة؟',
          DayState.jam3N || DayState.jam3NM => 'جمع احتياطي بين أعمال الطاهرة وتروك النفساء',
          _ when s.isIstihadha => 'ما بعد النفاس استحاضة',
          _ => Labels.state(s),
        };
      case AskIntent.istihadha:
        return switch (s) {
          DayState.istQ => 'استحاضة قليلة: وضوء لكل صلاة وتبديل القطنة',
          DayState.istM => 'استحاضة متوسطة: غسل للصبح ووضوء لكل صلاة',
          DayState.istK => 'استحاضة كثيرة: ثلاثة أغسال أو غسل لكل صلاة',
          DayState.istU => 'استحاضة؛ اختبري القطنة لتعرفي قسمها',
          DayState.hayd => 'هذا حيض لا استحاضة',
          DayState.tahir => 'لا دم محكوم به الآن',
          _ => Labels.state(s),
        };
      case AskIntent.qada:
        if (qada.isEmpty) {
          return notHayd == 0
              ? 'لا قضاء عليك مما لوّنتِه'
              : 'لا قضاء محسوب؛ لكن ${notHayd == 1 ? 'يومًا واحدًا' : '$notHayd أيام'} من الدم لم يكن حيضًا: إن تركتِ الصلاة فيه فاقضيها';
        }
        return [
          if (qada.prayerDays.isNotEmpty) 'صلوات ${qada.prayerDays.length} ${qada.prayerDays.length == 1 ? 'يوم' : 'أيام'}',
          if (qada.fastDays.isNotEmpty) 'صيام ${qada.fastDays.length} ${qada.fastDays.length == 1 ? 'يوم' : 'أيام'}',
          if (qada.fastDaysIhtiyat.isNotEmpty) 'صيام ${qada.fastDaysIhtiyat.length} احتياطًا',
        ].join('، ');
    }
  }
}
