import 'dart:convert';
import 'dart:io';

import 'package:ythrn/fiqh/golden/golden_case.dart';

export 'package:ythrn/fiqh/golden/golden_case.dart';

/// يحمّل كل ملفات الحالات من `test/fiqh/golden/cases/` (النموذج في `lib/fiqh/golden/`).
List<GoldenCase> loadGoldenCases({String dir = 'test/fiqh/golden/cases'}) {
  final files = Directory(dir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final file in files)
      for (final item in jsonDecode(file.readAsStringSync()) as List<dynamic>)
        GoldenCase.fromJson(item as Map<String, dynamic>),
  ];
}
