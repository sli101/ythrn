import 'dart:convert';

import 'package:flutter/services.dart';

/// مصدر نص القاعدة لشاشة «لماذا؟».
class RuleSource {
  const RuleSource({required this.src, required this.issue, this.url, this.quote});
  final String src;
  final String issue;
  final String? url;
  final String? quote;
}

/// قاعدة كما في `assets/fiqh/rules.json` بما تحتاجه الواجهة.
class RuleInfo {
  const RuleInfo({required this.id, required this.title, required this.text, required this.classification, required this.sources, this.effect});
  final String id;
  final String title;
  final String text;
  final String classification;
  final List<RuleSource> sources;
  final String? effect;
}

/// يحمّل القواعد من الأصول مرة واحدة ويعيدها بالمعرّف. القاعدة `H5-02a` تُطلب
/// بمعرّفها، وإن لم توجد فبمعرّف أصلها `H5-02`.
class RulesRepository {
  RulesRepository(this._rules, this._sourceNames);

  final Map<String, RuleInfo> _rules;
  final Map<String, String> _sourceNames;

  static Future<RulesRepository> load(AssetBundle bundle) async {
    final doc = jsonDecode(await bundle.loadString('assets/fiqh/rules.json')) as Map<String, dynamic>;
    final sources = <String, String>{};
    final srcDoc = doc['sources'];
    if (srcDoc is Map) {
      for (final e in srcDoc.entries) {
        final v = e.value;
        sources[e.key as String] = v is Map ? (v['name'] ?? v['title'] ?? e.key).toString() : v.toString();
      }
    } else if (srcDoc is List) {
      for (final v in srcDoc) {
        if (v is Map && v['code'] != null) sources[v['code'] as String] = (v['name'] ?? v['title'] ?? v['code']).toString();
      }
    }
    final rules = <String, RuleInfo>{};
    for (final r in doc['rules'] as List<dynamic>) {
      final m = r as Map<String, dynamic>;
      rules[m['id'] as String] = RuleInfo(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        text: m['text'] as String? ?? '',
        classification: m['classification'] as String? ?? 'unspecified',
        effect: m['effect'] as String?,
        sources: [
          for (final s in (m['sources'] as List<dynamic>? ?? const []))
            RuleSource(src: (s as Map)['src'].toString(), issue: s['issue'].toString(), url: s['url'] as String?, quote: s['quote'] as String?),
        ],
      );
    }
    return RulesRepository(rules, sources);
  }

  RuleInfo? byId(String id) => _rules[id] ?? _rules[id.replaceFirst(RegExp(r'[a-z]$'), '')];

  String sourceName(String code) => _sourceNames[code] ?? code;
}
