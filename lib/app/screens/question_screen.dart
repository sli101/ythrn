import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../fiqh/fiqh.dart';
import '../labels.dart';
import '../providers.dart';
import '../widgets/date_picker.dart';

/// شاشة السؤال الواحد (`docs/SPEC.md` §٦): الجواب، و«لا أفهم السؤال»، و«لا أتذكر»،
/// و«لاحقًا». تتابع السلّم الجاري داخلها حتى يُطوى، ثم السؤال التالي حتى لا يبقى شيء.
class QuestionScreen extends ConsumerStatefulWidget {
  const QuestionScreen({super.key, this.onboarding = false});

  /// أسئلة التهيئة عند أول استخدام: لا زر رجوع، وعنوان مختلف.
  final bool onboarding;

  @override
  ConsumerState<QuestionScreen> createState() => _QuestionScreenState();
}

class _QuestionScreenState extends ConsumerState<QuestionScreen> {
  /// الجلسة الجارية حين يكون فيها سلّم؛ وإلا تُشتق من المزوّد.
  QuestionSession? _ladderSession;
  int? _number;
  DateTime? _date;

  QuestionSession? _session() => _ladderSession ?? ref.watch(sessionProvider);

  Future<void> _reply(QuestionSession s, Question q, Reply reply) async {
    final after = await ref.read(appStateProvider.notifier).answer(s, q, reply);
    if (!mounted) return;
    setState(() {
      _ladderSession = after.ladder == null ? null : after;
      _number = null;
      _date = null;
    });
    if (after.ladder == null && !widget.onboarding) {
      final next = ref.read(machineProvider).next(after.copyWith(now: DateTime.now()));
      if (next == null && Navigator.of(context).canPop()) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session();
    final q = s == null ? null : ref.read(machineProvider).next(s);
    return Scaffold(
      appBar: AppBar(title: Text(widget.onboarding ? 'التهيئة' : 'سؤال'), automaticallyImplyLeading: !widget.onboarding),
      body: q == null || s == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 48),
                    const SizedBox(height: 12),
                    const Text('لا أسئلة الآن', style: TextStyle(fontSize: 18)),
                    if (!widget.onboarding && Navigator.of(context).canPop()) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('رجوع')),
                  ],
                ),
              ),
            )
          : _QuestionBody(
              question: q,
              number: _number ?? q.defaultValue ?? q.min ?? 0,
              date: _date,
              onNumber: (v) => setState(() => _number = v),
              onDate: (v) => setState(() => _date = v),
              onReply: (r) => _reply(s, q, r),
            ),
    );
  }
}

class _QuestionBody extends StatelessWidget {
  const _QuestionBody({required this.question, required this.number, required this.date, required this.onNumber, required this.onDate, required this.onReply});

  final Question question;
  final int number;
  final DateTime? date;
  final ValueChanged<int> onNumber;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<Reply> onReply;

  @override
  Widget build(BuildContext context) {
    final q = question;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (q.isLadderStep)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('سؤال أبسط', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
          ),
        Text(q.text, style: theme.textTheme.titleLarge, textAlign: TextAlign.start),
        if (q.explained && q.explanation != null)
          Card(
            margin: const EdgeInsets.only(top: 12),
            child: Padding(padding: const EdgeInsets.all(12), child: Text(q.explanation!)),
          ),
        if (q.guidance != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(q.guidance!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
          ),
        const SizedBox(height: 20),
        ..._input(context),
        const SizedBox(height: 28),
        const Divider(),
        if (q.hasLadder || q.explanation != null) TextButton.icon(onPressed: () => onReply(Reply.dontUnderstand), icon: const Icon(Icons.help_outline), label: const Text('لا أفهم السؤال')),
        TextButton.icon(onPressed: () => onReply(Reply.dontRemember), icon: const Icon(Icons.psychology_alt_outlined), label: Text(q.dontRememberLabel)),
        if (!q.isLadderStep) TextButton.icon(onPressed: () => onReply(Reply.skip), icon: const Icon(Icons.schedule), label: const Text('لاحقًا')),
        const SizedBox(height: 8),
        Text('القاعدة: ${q.rule.id}', style: theme.textTheme.labelSmall),
      ],
    );
  }

  List<Widget> _input(BuildContext context) {
    final q = question;
    switch (q.kind) {
      case QuestionKind.yesNo:
        return [
          FilledButton(onPressed: () => onReply(const Reply.value(true)), child: const Text('نعم')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => onReply(const Reply.value(false)), child: const Text('لا')),
        ];
      case QuestionKind.choice:
        return [
          for (final o in q.options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton.tonal(
                onPressed: () => onReply(Reply.value(o.value)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(o.label, textAlign: TextAlign.center),
                ),
              ),
            ),
        ];
      case QuestionKind.number:
        final min = q.min ?? 0;
        final max = q.max ?? 10;
        final v = number.clamp(min, max);
        return [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(onPressed: v > min ? () => onNumber(v - 1) : null, icon: const Icon(Icons.remove)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text('$v', style: Theme.of(context).textTheme.displaySmall),
              ),
              IconButton.filledTonal(onPressed: v < max ? () => onNumber(v + 1) : null, icon: const Icon(Icons.add)),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => onReply(Reply.value(v)), child: const Text('تأكيد')),
        ];
      case QuestionKind.date:
        return [
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final picked = await pickDate(context, initial: date ?? now, first: DateTime(now.year - 80), last: now);
              if (picked != null) onDate(picked);
            },
            icon: const Icon(Icons.calendar_month),
            label: Text(date == null ? 'اختاري التاريخ' : '${Labels.date(date!)} · ${HijriDate.fromDate(date!)}'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: date == null ? null : () => onReply(Reply.value(date!)), child: const Text('تأكيد')),
        ];
    }
  }
}
