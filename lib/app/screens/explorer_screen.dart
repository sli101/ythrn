import 'dart:convert';

import 'package:flutter/material.dart';

import '../../fiqh/golden/golden_case.dart';
import '../../fiqh/golden/golden_runner.dart';
import '../../fiqh/golden/scenario.dart';
import '../labels.dart';

/// المستكشف (`docs/SPEC.md` §١١ ٨؛ ويب وسطح مكتب): حالة ذهبية بصيغة
/// `test/fiqh/golden/golden.schema.json` تُلصق كاملة فتُشغَّل على المحرك والآلة
/// ويُعرض التقرير (الفحوص، المعلَّق، وحالات الأيام). أداة المالك للتدقيق؛ لا تمسّ بيانات التطبيق.
class ExplorerScreen extends StatefulWidget {
  const ExplorerScreen({super.key});

  static const sample = '''[{
  "id": "G-X-001",
  "group": "unknown",
  "title": "مبتدئة ترى دمًا سبعة أيام",
  "source": "تجربة",
  "subject": "HAYD",
  "profile": {"womanType": "MUB"},
  "timeline": [{"days": "1-7", "blood": true}],
  "expected": [{"days": "1-7", "state": "HAYD"}, {"assert": "nextQuestion", "value": null}]
}]''';

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  final _text = TextEditingController(text: ExplorerScreen.sample);
  final List<(GoldenCase, GoldenReport)> _reports = [];
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _run() {
    setState(() {
      _reports.clear();
      _error = null;
      try {
        final raw = jsonDecode(_text.text);
        final list = raw is List ? raw : [raw];
        for (final item in list) {
          final c = GoldenCase.fromJson((item as Map).cast<String, dynamic>());
          _reports.add((c, runGoldenCase(c)));
        }
      } on FormatException catch (e) {
        _error = 'JSON غير صالح: ${e.message}';
      } catch (e) {
        _error = 'تعذّر تشغيل الحالة: $e';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('المستكشف')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('ألصقي حالة أو قائمة حالات بصيغة الاختبارات الذهبية (اليوم ١ = ٢٠٢٦/٠٣/٠١، الفجر ٤:٣٠ والمغرب ١٨:٣٠ ما لم يُحدَّد `clock`).', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          TextField(
            controller: _text,
            maxLines: 14,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'JSON'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(onPressed: _run, icon: const Icon(Icons.play_arrow), label: const Text('تشغيل')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          for (final (c, r) in _reports) _ReportCard(c: c, r: r),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.c, required this.r});
  final GoldenCase c;
  final GoldenReport r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = r.passed;
    final res = r.engineResult;
    final sc = r.scenario;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(ok ? Icons.check_circle : Icons.cancel, color: ok ? Colors.green : theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text('${c.id} — ${c.title}', style: theme.textTheme.titleMedium)),
              ],
            ),
            Text('${r.checks.where((x) => x.ok).length} ناجح · ${r.failures.length} فاشل · ${r.pending.length} معلَّق', style: theme.textTheme.bodySmall),
            for (final f in r.failures) Text('✗ ${f.name}: ${f.reason}', style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
            for (final p in r.pending) Text('⏳ $p', style: const TextStyle(fontSize: 12)),
            if (r.habit != null) Text('العادة: ${Labels.womanType(r.habit!.type)}${r.habit!.count == null ? '' : ' · العدد ${r.habit!.count}'}', style: theme.textTheme.bodySmall),
            if (res != null && sc != null) ...[
              const Divider(),
              Text('حالات الأيام', style: theme.textTheme.titleSmall),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (var d = 1; d <= c.lastDay; d++)
                    Builder(
                      builder: (_) {
                        final s = goldenDayState(sc, res, d);
                        return Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: s == null ? null : Labels.stateColor(s).withValues(alpha: 0.15),
                          label: Text('$d: ${s == null ? '—' : s.code}', style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('الفترات', style: theme.textTheme.titleSmall),
              for (final iv in res.intervals)
                Text(
                  '${_d(sc, iv.from)} → ${iv.to == null ? '…' : _d(sc, iv.to!)}: ${Labels.state(iv.state)} (${Labels.classification(iv.classification)}) ← ${iv.trace.map((t) => t.id).join('، ')}${iv.pendingInput == null ? '' : ' · ينتظر ${iv.pendingInput}'}',
                  style: const TextStyle(fontSize: 12),
                ),
              if (res.unsupported.isNotEmpty) Text('غير مغطى: ${res.unsupported.join('؛ ')}', style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }

  /// لحظة بصيغة «D٣ ٠٦:٠٠» نسبةً إلى يوم السيناريو الأول.
  String _d(Scenario sc, DateTime t) {
    final day = t.difference(Scenario.base).inDays + 1;
    return 'D$day ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
