import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// «لا حكم بلا أثر»: كل `RuleRef('X')` في كود المحرك يجب أن يشير إلى قاعدة
/// موجودة في `assets/fiqh/rules.json` (لا في الملف المؤجَّل للاحتياط الاستحبابي).
void main() {
  test('كل إحالة قاعدة في lib/fiqh موجودة في rules.json', () {
    final doc = jsonDecode(File('assets/fiqh/rules.json').readAsStringSync()) as Map<String, dynamic>;
    final ids = <String>{
      for (final r in doc['rules'] as List<dynamic>) (r as Map<String, dynamic>)['id'] as String,
    };
    final bases = ids.map((i) => i.replaceFirst(RegExp(r'[a-z]$'), '')).toSet();

    final re = RegExp(r"RuleRef\('([A-Z0-9]+-\d{2}[a-z]?)'");
    final missing = <String>{};
    final found = <String>{};
    for (final f in Directory('lib/fiqh').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in re.allMatches(f.readAsStringSync())) {
        final id = m.group(1)!;
        found.add(id);
        if (!ids.contains(id) && !bases.contains(id)) missing.add('$id في ${f.path}');
      }
    }
    expect(found, isNotEmpty);
    expect(missing, isEmpty, reason: 'إحالات إلى قواعد غير موجودة أو مؤجَّلة');
  });
}
