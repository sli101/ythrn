import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../fiqh/fiqh.dart';
import '../intent.dart';
import '../labels.dart';
import '../providers.dart';
import 'calendar_screen.dart';
import 'event_entry.dart';
import 'qada_screen.dart';
import 'question_screen.dart';
import 'why_screen.dart';

/// الشاشة الأولى (`docs/UX.md` §٢.١): «ماذا تريدين أن تعرفي؟» ببطاقات بلغة
/// عادية؛ ولمن حسبت من قبل بطاقة «حالتي اليوم» فوقها بزرّي اليوم.
class AskScreen extends ConsumerWidget {
  const AskScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, AskIntent intent) async {
    if (intent == AskIntent.qada) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QadaScreen(standalone: true)));
      return;
    }
    if (intent == AskIntent.nifas) {
      final events = ref.read(appStateProvider).value?.events ?? const [];
      final hasBirth = events.any((e) => e.event is Birth || e.event is Miscarriage);
      if (!hasBirth) {
        final ok = await _birthOrMiscarriage(context, ref);
        if (!ok || !context.mounted) return;
      }
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CalendarScreen(intent: intent)));
  }

  Future<bool> _birthOrMiscarriage(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.child_care), title: const Text('ولادة'), onTap: () => Navigator.pop(ctx, 'birth')),
            ListTile(leading: const Icon(Icons.healing_outlined), title: const Text('سقط'), onTap: () => Navigator.pop(ctx, 'miscarriage')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return false;
    final before = ref.read(appStateProvider).value?.events.length ?? 0;
    if (choice == 'birth') {
      await recordBirth(context, ref);
    } else {
      await recordMiscarriage(context, ref);
    }
    return (ref.read(appStateProvider).value?.events.length ?? 0) > before;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appStateProvider).value;
    final hasData = state != null && (state.marks.isNotEmpty || state.events.isNotEmpty);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('يطهرن'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (hasData) const _TodayStatus(),
          Text('ماذا تريدين أن تعرفي؟', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final intent in AskIntent.values)
            Card(
              child: ListTile(
                leading: Icon(intent.icon, size: 28, color: theme.colorScheme.primary),
                title: Text(intent.title, style: theme.textTheme.titleMedium),
                subtitle: Text(intent.subtitle),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _open(context, ref, intent),
              ),
            ),
          const SizedBox(height: 12),
          Text('الأحكام على فتاوى السيد السيستاني، مع بدائل في موارد الاحتياط الوجوبي. لا نصائح صحية.', style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// «حالتي اليوم»: الحكم بلونه، والسؤال المعلَّق، وزرّا «نزل الدم اليوم» / «انقطع اليوم».
class _TodayStatus extends ConsumerWidget {
  const _TodayStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iv = ref.watch(todayIntervalProvider);
    final s = iv?.state ?? DayState.tahir;
    final color = Labels.stateColor(s);
    final q = ref.watch(nextQuestionProvider);
    final ongoing = ref.watch(bloodOngoingProvider);
    final today = ref.watch(todayProvider);
    final now = ref.watch(nowProvider);
    final theme = Theme.of(context);
    final notifier = ref.read(appStateProvider.notifier);
    return Card(
      color: color.withValues(alpha: 0.1),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Labels.stateIcon(s), color: color, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('حالتي اليوم: ${Labels.state(s)}', style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
                      Text('${Labels.date(now)} · ${HijriDate.fromDate(today)}', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                if (iv != null)
                  IconButton(icon: const Icon(Icons.menu_book_outlined), tooltip: 'لماذا؟', onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => WhyScreen(interval: iv)))),
              ],
            ),
            if (q != null)
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const QuestionScreen())),
                icon: const Icon(Icons.question_answer_outlined),
                label: Text(q.text, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            Wrap(
              spacing: 8,
              children: [
                if (!ongoing)
                  ActionChip(
                    avatar: const Icon(Icons.water_drop_outlined, size: 18),
                    label: const Text('نزل الدم اليوم'),
                    onPressed: () async {
                      await notifier.markRange(today, today);
                      ref.read(nowProvider.notifier).state = DateTime.now();
                    },
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('انقطع الدم اليوم'),
                    onPressed: () async {
                      final marks = ref.read(appStateProvider).value?.marks ?? const <BloodDay>[];
                      final todayMark = marks.where((m) => m.day == today).firstOrNull;
                      if (todayMark != null) {
                        await notifier.updateDay(todayMark.copyWith(stopAt: DateTime.now()));
                      } else {
                        // الدم الجاري من مدى سابق: نضيف اليوم بانقطاعه الآن.
                        await notifier.saveMarks([...marks, BloodDay(today, stopAt: DateTime.now())]);
                      }
                      ref.read(nowProvider.notifier).state = DateTime.now();
                    },
                  ),
                if (ongoing) ActionChip(avatar: const Icon(Icons.science_outlined, size: 18), label: const Text('نتيجة القطنة'), onPressed: () => recordKursuf(context, ref)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
