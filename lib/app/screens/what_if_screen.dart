import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../fiqh/fiqh.dart';
import '../labels.dart';
import '../providers.dart';

/// «ماذا لو؟» (`docs/SPEC.md` §١١ ٥): قائمة المجاهيل الحالية؛ لكل مجهول بدائل
/// جوابه وأثر كل بديل في الحكم، بلا حفظ. الإجابة الفعلية من شاشة السؤال.
class WhatIfScreen extends ConsumerWidget {
  const WhatIfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(whatIfProvider);
    final now = ref.watch(nowProvider);
    final base = ref.watch(todayIntervalProvider)?.state ?? DayState.tahir;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ماذا لو؟')),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا مجاهيل تؤثر في الحكم الآن.', style: TextStyle(fontSize: 18)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('الحكم الآن: ${Labels.state(base)}', style: theme.textTheme.titleMedium?.copyWith(color: Labels.stateColor(base))),
                const SizedBox(height: 4),
                Text('كل بديل يُجرَّب على نسخة من بياناتك ولا يُحفظ؛ لتثبيت جواب ارجعي إلى السؤال.', style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                for (final item in items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.text, style: theme.textTheme.titleMedium),
                          Text('القاعدة: ${item.rule.id}', style: theme.textTheme.labelSmall),
                          const SizedBox(height: 8),
                          for (final v in item.variants) _VariantTile(variant: v, now: now, base: base),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  const _VariantTile({required this.variant, required this.now, required this.base});
  final WhatIfVariant variant;
  final DateTime now;
  final DayState base;

  @override
  Widget build(BuildContext context) {
    final s = variant.stateAt(now) ?? DayState.tahir;
    final changed = variant.changesAnything;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(changed ? Labels.stateIcon(s) : Icons.remove, color: changed ? Labels.stateColor(s) : null),
      title: Text('لو: ${variant.label}'),
      subtitle: Text(
        !changed
            ? 'لا يتغير الحكم'
            : s == base
            ? 'الآن ${Labels.state(s)}؛ يتغير في ${variant.diffs.length == 1 ? 'مدة' : 'مدد'}: ${_diffs()}'
            : 'الآن ${Labels.state(s)} بدل ${Labels.state(base)}',
        style: TextStyle(color: changed ? Labels.stateColor(s) : null),
      ),
    );
  }

  String _diffs() =>
      variant.diffs.take(3).map((d) => '${Labels.dateTime(d.from)}${d.to == null ? '' : ' – ${Labels.dateTime(d.to!)}'}: ${Labels.state(d.variant)} بدل ${Labels.state(d.base)}').join('؛ ');
}
