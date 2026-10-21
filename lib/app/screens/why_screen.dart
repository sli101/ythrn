import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../fiqh/fiqh.dart';
import '../labels.dart';
import '../providers.dart';
import '../rules_repository.dart';

/// «لماذا؟» (`docs/SPEC.md` §١١ ٤): سلسلة القواعد التي أنتجت حكم الفترة بنصوصها
/// ومصادرها. لا حكم بلا أثر.
class WhyScreen extends ConsumerWidget {
  const WhyScreen({super.key, required this.interval});
  final StateInterval interval;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(rulesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('لماذا؟')),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('تعذّر تحميل القواعد: $e')),
        data: (repo) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${Labels.state(interval.state)} · ${Labels.classification(interval.classification)}', style: Theme.of(context).textTheme.titleLarge),
            Text('من ${Labels.dateTime(interval.from)}${interval.to == null ? '' : ' إلى ${Labels.dateTime(interval.to!)}'}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            for (final (i, ref) in interval.trace.indexed) _RuleTile(index: i + 1, ref: ref, info: repo.byId(ref.id), repo: repo),
          ],
        ),
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.index, required this.ref, required this.info, required this.repo});
  final int index;
  final RuleRef ref;
  final RuleInfo? info;
  final RulesRepository repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(child: Text('$index')),
        title: Text(info?.title ?? ref.id),
        subtitle: Text([ref.id, if (ref.note != null) ref.note!, if (info != null) Labels.classification(info!.classification)].join(' · ')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (info == null)
            const Text('القاعدة غير موجودة في ملف القواعد.')
          else ...[
            SelectableText(info!.text, style: theme.textTheme.bodyMedium),
            if (info!.sources.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('المصادر', style: theme.textTheme.labelLarge),
              for (final s in info!.sources)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SelectableText('${repo.sourceName(s.src)} ${s.issue}${s.url == null ? '' : '\n${s.url}'}', style: theme.textTheme.bodySmall),
                ),
            ],
          ],
        ],
      ),
    );
  }
}
