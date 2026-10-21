import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../labels.dart';
import '../providers.dart';

/// سجل القضاء (`docs/SPEC.md` §٥.٤، H9-08، H9-14): ما يجب قضاؤه مع سببه.
class QadaScreen extends ConsumerWidget {
  const QadaScreen({super.key, this.standalone = false});

  /// مفتوحة من «اسألي» (بزر رجوع وتوجيه إلى التقويم).
  final bool standalone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(resultProvider);
    final q = r?.qada;
    return Scaffold(
      appBar: AppBar(title: const Text('القضاء'), automaticallyImplyLeading: standalone),
      body: q == null || q.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا قضاء مما لوّنتِه. لوّني أيام الدم في التقويم، وأدخلي مدى رمضان إن كان فيها، ليُحسب ما يُقضى.', textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (q.prayerDays.isNotEmpty) ...[
                  Text('صلوات تُقضى', style: Theme.of(context).textTheme.titleMedium),
                  const Text('أيام عوملت حيضًا فتُركت الصلاة ثم تبين أنها ليست بحيض (H9-14).', style: TextStyle(fontSize: 12)),
                  for (final d in q.prayerDays) ListTile(dense: true, leading: const Icon(Icons.replay), title: Text(Labels.date(d))),
                ],
                if (q.fastDays.isNotEmpty) ...[
                  Text('صيام يُقضى', style: Theme.of(context).textTheme.titleMedium),
                  const Text('أيام رمضان التي لم تُصم لحيض أو نفاس (H9-08).', style: TextStyle(fontSize: 12)),
                  for (final d in q.fastDays) ListTile(dense: true, leading: const Icon(Icons.nightlight_outlined), title: Text(Labels.date(d))),
                ],
                if (q.fastDaysIhtiyat.isNotEmpty) ...[
                  Text('صيام يُقضى احتياطًا', style: Theme.of(context).textTheme.titleMedium),
                  const Text('أيام الجمع في رمضان: قضاء الصوم على الاحتياط (H3-02).', style: TextStyle(fontSize: 12)),
                  for (final d in q.fastDaysIhtiyat) ListTile(dense: true, leading: const Icon(Icons.nightlight_outlined), title: Text(Labels.date(d))),
                ],
              ],
            ),
    );
  }
}
