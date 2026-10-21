import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../fiqh/fiqh.dart';
import '../answer.dart';
import '../intent.dart';
import '../labels.dart';
import '../providers.dart';
import '../widgets/month_grid.dart';
import 'event_entry.dart';
import 'question_screen.dart';
import 'what_if_screen.dart';
import 'why_screen.dart';

/// التقويم (`docs/UX.md` §٢.٢–٢.٤): تلوين أيام الدم بالنقر، ومدى بالنقر المطوّل
/// ثم النقر، وورقة تفاصيل اليوم بنقرة ثانية؛ الأيام بلون حكمها بعد الحساب،
/// وبطاقة الجواب لسؤالها تحت الشهر.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.intent, this.embedded = false});

  /// سؤالها إن جاءت من شاشة «اسألي»؛ `null` = التبويب العام.
  final AskIntent? intent;

  /// داخل الهيكل (بلا زر رجوع).
  final bool embedded;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late HijriDate _month = HijriDate.fromDate(DateTime.now()).monthStart;
  DateTime? _rangeStart;
  bool _computed = false;

  List<BloodDay> get _marks => ref.read(appStateProvider).value?.marks ?? const [];

  Future<void> _onTap(DateTime day) async {
    final notifier = ref.read(appStateProvider.notifier);
    if (_rangeStart != null) {
      await notifier.markRange(_rangeStart!, day);
      setState(() => _rangeStart = null);
      return;
    }
    final existing = _marks.where((m) => m.day == day).firstOrNull;
    if (existing == null) {
      await notifier.toggleDay(day);
    } else {
      await _showDaySheet(existing);
    }
  }

  void _onLongPress(DateTime day) {
    setState(() => _rangeStart = day);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('انقري آخر يوم من المدى'), duration: Duration(seconds: 3)));
  }

  Future<void> _showDaySheet(BloodDay d) async {
    final runs = BloodCalendar.runs(_marks);
    final run = runs.firstWhere((r) => r.any((x) => x.day == d.day));
    final isFirst = run.first.day == d.day;
    final isLast = run.last.day == d.day;
    final today = ref.read(todayProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DaySheet(day: d, isFirst: isFirst, isLast: isLast, isToday: d.day == today),
    );
  }

  /// «احسبي»: الساعة حيث تلزم، ثم الأسئلة، ثم الجواب.
  Future<void> _compute() async {
    final marks = _marks;
    if (marks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لوّني أيام الدم أولًا')));
      return;
    }
    while (mounted) {
      final s = ref.read(sessionProvider);
      if (s == null) return;
      final clock = ref.read(clockProvider);
      final stored = ref.read(appStateProvider).value?.events.map((e) => e.event).toList() ?? const <FiqhEvent>[];
      final machine = ref.read(machineProvider);
      final needs = BloodCalendar.precisionNeeds(
        _marks,
        clock,
        today: ref.read(todayProvider),
        now: s.now,
        evaluate: (cal) => machine.engine.evaluateProfile(s.profile, [...cal, ...stored], s.now),
      );
      if (needs.isEmpty) break;
      final need = needs.first;
      final day = _marks.firstWhere((m) => m.day == need.day);
      if (!mounted) return;
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(need.isStart ? BloodCalendar.startMoment(day, clock) : BloodCalendar.stopMoment(day, clock)),
        helpText: need.isStart ? 'متى بالضبط بدأ الدم يوم ${Labels.shortDate(need.day)}؟ (الحكم يختلف بالساعة)' : 'متى بالضبط انقطع الدم يوم ${Labels.shortDate(need.day)}؟ (الحكم يختلف بالساعة)',
      );
      if (t == null) break; // تركته: تبقى الافتراضات.
      final at = DateTime(need.day.year, need.day.month, need.day.day, t.hour, t.minute);
      // الانقطاع ليلًا بعد منتصف الليل يقع في اليوم التقويمي التالي قبل فجره.
      final fixed = !need.isStart && at.isBefore(clock.fajr(need.day)) ? HijriDate.nextDay(at).add(Duration(hours: at.hour, minutes: at.minute)) : at;
      await ref.read(appStateProvider.notifier).updateDay(need.isStart ? day.copyWith(startAt: fixed) : day.copyWith(stopAt: fixed));
    }
    if (!mounted) return;
    if (ref.read(nextQuestionProvider) != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QuestionScreen()));
    }
    if (mounted) setState(() => _computed = true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider).value;
    final marks = state?.marks ?? const <BloodDay>[];
    final r = ref.watch(resultProvider);
    final time = ref.watch(timeProvider);
    final now = ref.watch(nowProvider);
    final today = ref.watch(todayProvider);
    final intent = widget.intent;
    final theme = Theme.of(context);

    final marked = {for (final m in marks) m.day};
    final colors = <DateTime, Color>{};
    if (r != null && marks.isNotEmpty) {
      final from = marks.map((m) => m.day).reduce((a, b) => a.isBefore(b) ? a : b);
      for (final e in BloodCalendar.dayStates(r, time.clock, from: from, to: today).entries) {
        if (e.value != null && e.value != DayState.tahir) colors[e.key] = Labels.stateColor(e.value!);
      }
    }
    final showAnswer = intent != null && (_computed || marks.isNotEmpty) && r != null;
    final answer = showAnswer
        ? AnswerSummary.build(intent: intent, r: r, time: time, now: now, events: ref.watch(sessionProvider)?.events ?? const [], marks: marks)
        : null;
    final nextQ = ref.watch(nextQuestionProvider);

    return Scaffold(
      appBar: AppBar(title: Text(intent?.title ?? 'التقويم'), automaticallyImplyLeading: !widget.embedded),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          if (intent != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(intent.hint, style: theme.textTheme.bodyMedium)),
          Row(
            children: [
              IconButton(onPressed: () => setState(() => _month = _month.nextMonthStart), icon: const Icon(Icons.chevron_right), tooltip: 'الشهر التالي'),
              Expanded(
                child: Column(
                  children: [
                    Text('${_month.monthName} ${_month.year} هـ', style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                    Text('${Labels.monthYear(_month.toDate())} – ${Labels.monthYear(DateTime(_month.nextMonthStart.toDate().year, _month.nextMonthStart.toDate().month, _month.nextMonthStart.toDate().day - 1))}', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  ],
                ),
              ),
              IconButton(onPressed: () => setState(() => _month = _month.addDays(-1).monthStart), icon: const Icon(Icons.chevron_left), tooltip: 'الشهر السابق'),
            ],
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: MonthGrid(
                year: _month.year,
                month: _month.month,
                today: today,
                marked: marked,
                colors: colors,
                rangeStart: _rangeStart,
                maxDay: today,
                onTap: _onTap,
                onLongPress: _onLongPress,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (colors.isEmpty && marked.isNotEmpty) const _LegendDot(color: Color(0xFFB3261E), label: 'دم (لم يُحسب بعدُ)'),
              for (final s in colors.values.toSet().isEmpty ? const <DayState>[] : [DayState.hayd, DayState.istK, DayState.jam3, DayState.nifas, DayState.ghayr].where((s) => colors.values.contains(Labels.stateColor(s))))
                _LegendDot(color: Labels.stateColor(s), label: s == DayState.istK ? 'استحاضة' : s == DayState.jam3 ? 'جمع احتياطي' : Labels.state(s)),
            ],
          ),
          const SizedBox(height: 4),
          Text('نقرة تلوّن اليوم، ونقرة على يوم ملوَّن تفتح تفاصيله، ونقرة مطوّلة تبدأ مدى.', style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (intent != null)
            FilledButton.icon(
              onPressed: _compute,
              icon: const Icon(Icons.calculate_outlined),
              label: Text(nextQ != null && marks.isNotEmpty ? 'احسبي (بعد ${nextQ.isLadderStep ? 'سؤال' : 'سؤال أو أكثر'})' : 'احسبي'),
            ),
          if (answer != null && intent != null) _AnswerCard(answer: answer, intent: intent, hasQuestion: nextQ != null),
          if (intent == null && marks.isNotEmpty && r != null) _TodayCard(r: r),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [CircleAvatar(radius: 6, backgroundColor: color), const SizedBox(width: 4), Text(label, style: Theme.of(context).textTheme.labelSmall)],
      );
}

/// ورقة تفاصيل اليوم: الصفات، البدء ليلًا أو نهارًا (لأول يوم)، الانقطاع (لآخر يوم)، الحذف.
class _DaySheet extends ConsumerWidget {
  const _DaySheet({required this.day, required this.isFirst, required this.isLast, required this.isToday});
  final BloodDay day;
  final bool isFirst;
  final bool isLast;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(appStateProvider.notifier);
    final current = ref.watch(appStateProvider).value?.marks.where((m) => m.day == day.day).firstOrNull ?? day;
    final theme = Theme.of(context);
    Future<void> save(BloodDay d) => notifier.updateDay(d);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(16),
        children: [
          Text('${Labels.date(day.day)} · ${HijriDate.fromDate(day.day)}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Text('صفات الدم في هذا اليوم', style: theme.textTheme.labelLarge),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(label: const Text('لا أذكر'), selected: current.props == null && !current.spots, onSelected: (_) => save(current.copyWith(clearProps: true, spots: false))),
              ChoiceChip(label: const Text('أسود أو أحمر'), selected: current.props == BloodProps.wajid && !current.spots, onSelected: (_) => save(current.copyWith(props: BloodProps.wajid, spots: false))),
              ChoiceChip(label: const Text('أصفر أو فاتح'), selected: current.props == BloodProps.faqid && !current.spots, onSelected: (_) => save(current.copyWith(props: BloodProps.faqid, spots: false))),
              ChoiceChip(label: const Text('لطخات متقطعة'), selected: current.spots, onSelected: (_) => save(current.copyWith(spots: true))),
            ],
          ),
          if (isFirst) ...[
            const SizedBox(height: 12),
            Text('متى بدأ الدم؟', style: theme.textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('لا أذكر'), selected: current.startPart == null && current.startAt == null, onSelected: (_) => save(current.copyWith(clearStartPart: true, clearStartAt: true))),
                ChoiceChip(label: const Text('في النهار'), selected: current.startPart == DayPart.day && current.startAt == null, onSelected: (_) => save(current.copyWith(startPart: DayPart.day, clearStartAt: true))),
                ChoiceChip(label: const Text('في الليل'), selected: current.startPart == DayPart.night && current.startAt == null, onSelected: (_) => save(current.copyWith(startPart: DayPart.night, clearStartAt: true))),
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(current.startAt == null ? 'الساعة بالضبط' : Labels.time(current.startAt!)),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current.startAt ?? day.day.add(const Duration(hours: 8))));
                    if (t != null) await save(current.copyWith(startAt: DateTime(day.day.year, day.day.month, day.day.day, t.hour, t.minute)));
                  },
                ),
              ],
            ),
          ],
          if (isLast) ...[
            const SizedBox(height: 12),
            Text(isToday ? 'هل انقطع الدم اليوم؟' : 'متى انقطع الدم؟', style: theme.textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: Text(isToday ? 'ما زال مستمرًّا' : 'لا أذكر'), selected: current.stopPart == null && current.stopAt == null, onSelected: (_) => save(current.copyWith(clearStopPart: true, clearStopAt: true))),
                ChoiceChip(label: const Text('في النهار'), selected: current.stopPart == DayPart.day && current.stopAt == null, onSelected: (_) => save(current.copyWith(stopPart: DayPart.day, clearStopAt: true))),
                ChoiceChip(label: const Text('في الليل'), selected: current.stopPart == DayPart.night && current.stopAt == null, onSelected: (_) => save(current.copyWith(stopPart: DayPart.night, clearStopAt: true))),
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: Text(current.stopAt == null ? 'الساعة بالضبط' : Labels.time(current.stopAt!)),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current.stopAt ?? day.day.add(const Duration(hours: 15))));
                    if (t != null) await save(current.copyWith(stopAt: DateTime(day.day.year, day.day.month, day.day.day, t.hour, t.minute)));
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  await notifier.toggleDay(day.day);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('ليس يوم دم'),
              ),
              const Spacer(),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('تم')),
            ],
          ),
        ],
      ),
    );
  }
}

/// بطاقة الجواب: الجملة، التصنيف، ما تفعله الآن، ما تنتبه له، وأزرار لماذا/ماذا لو/كل الأحكام.
class _AnswerCard extends ConsumerWidget {
  const _AnswerCard({required this.answer, required this.intent, required this.hasQuestion});
  final AnswerSummary answer;
  final AskIntent intent;
  final bool hasQuestion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = Labels.stateColor(answer.state);
    final iv = answer.interval;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Labels.stateIcon(answer.state), color: color, size: 32),
                const SizedBox(width: 12),
                Expanded(child: Text(answer.headline, style: theme.textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 4),
            Text('${Labels.state(answer.state)} · ${Labels.classification(answer.classification)}', style: theme.textTheme.bodySmall),
            if (hasQuestion)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QuestionScreen())),
                  icon: const Icon(Icons.question_answer_outlined),
                  label: const Text('سؤال يحتاج جوابك'),
                ),
              ),
            if (intent == AskIntent.istihadha)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonalIcon(onPressed: () => recordKursuf(context, ref), icon: const Icon(Icons.science_outlined), label: const Text('اختبري القطنة الآن')),
              ),
            if (answer.doNow.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('ماذا أفعل الآن', style: theme.textTheme.titleSmall),
              for (final d in answer.doNow)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(d.kind == DutyKind.prohibition ? Icons.block : Icons.task_alt, size: 20),
                  title: Text(d.text),
                  subtitle: d.classification == 'fatwa' ? null : Text(Labels.classification(d.classification)),
                ),
            ],
            if (answer.watch.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('ما أنتبه له', style: theme.textTheme.titleSmall),
              for (final (at, text) in answer.watch)
                ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: const Icon(Icons.notifications_active_outlined, size: 20), title: Text(text), subtitle: Text(Labels.dateTime(at))),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  onPressed: iv == null ? null : () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WhyScreen(interval: iv))),
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text('لماذا؟'),
                ),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WhatIfScreen())),
                  icon: const Icon(Icons.alt_route),
                  label: const Text('ماذا لو؟'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _showAllDuties(context, ref, answer.state),
                  icon: const Icon(Icons.list_alt),
                  label: const Text('كل الأحكام'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAllDuties(BuildContext context, WidgetRef ref, DayState state) {
    final duties = DutiesResolver(ref.read(timeProvider)).forState(state);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            Text('أحكام ${Labels.state(state)}', style: Theme.of(ctx).textTheme.titleLarge),
            for (final kind in DutyKind.values)
              if (duties.any((d) => d.kind == kind)) ...[
                const SizedBox(height: 8),
                Text(Labels.dutyKind(kind), style: Theme.of(ctx).textTheme.titleMedium),
                for (final d in duties.where((d) => d.kind == kind))
                  ListTile(dense: true, title: Text(d.text), subtitle: Text('${d.rule.id}${d.classification == 'fatwa' ? '' : ' · ${Labels.classification(d.classification)}'}')),
              ],
          ],
        ),
      ),
    );
  }
}

/// بطاقة «حكم اليوم» في تبويب التقويم العام.
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.r});
  final EngineResult r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iv = ref.watch(todayIntervalProvider);
    final s = iv?.state ?? DayState.tahir;
    final color = Labels.stateColor(s);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: color.withValues(alpha: 0.08),
      child: ListTile(
        leading: Icon(Labels.stateIcon(s), color: color),
        title: Text('اليوم: ${Labels.state(s)}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        subtitle: iv == null ? null : Text(Labels.classification(iv.classification)),
        trailing: iv == null ? null : IconButton(icon: const Icon(Icons.menu_book_outlined), tooltip: 'لماذا؟', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WhyScreen(interval: iv)))),
      ),
    );
  }
}
