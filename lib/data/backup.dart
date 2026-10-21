import 'dart:convert';

import '../fiqh/fiqh.dart';
import 'app_settings.dart';
import 'fiqh_store.dart';

/// ملف النسخ الاحتياطي المحلي (`docs/SPEC.md` §١١ ٧): JSON يحمل الملف والأحداث
/// بمعرّفاتها والمفاتيح المسوّاة والإعدادات. لا خادم (الخيار أ).
class Backup {
  const Backup._();

  static const format = 'ythrn-backup';
  static const version = 1;

  static String encode(StoredState s, {DateTime? exportedAt}) => const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
        'profile': FiqhCodec.encodeProfile(s.profile),
        'events': [
          for (final e in s.events) {'id': e.id, ...FiqhCodec.encodeEvent(e.event)},
        ],
        'settled': s.settled.toList()..sort(),
        'explained': s.explained.toList()..sort(),
        'settings': s.settings.toJson(),
        'marks': [for (final m in s.marks) m.toJson()],
      });

  /// يرمي [FormatException] برسالة عربية إذا لم يكن الملف نسخة احتياطية صالحة.
  static StoredState decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const FormatException('النص ليس JSON صالحًا');
    }
    if (raw is! Map || raw['format'] != format) throw const FormatException('الملف ليس نسخة احتياطية من «يطهرن»');
    final v = (raw['version'] as num?)?.toInt() ?? 0;
    if (v > version) throw FormatException('إصدار النسخة ($v) أحدث من هذا التطبيق');
    final j = raw.cast<String, Object?>();
    final events = <StoredEvent>[];
    for (final item in (j['events'] as List?) ?? const []) {
      final m = (item as Map).cast<String, Object?>();
      final id = m['id'] as String?;
      if (id == null || id.isEmpty) throw const FormatException('حدث بلا معرّف');
      events.add(StoredEvent(id, FiqhCodec.decodeEvent(m)));
    }
    return StoredState(
      profile: j['profile'] == null ? const FiqhProfile() : FiqhCodec.decodeProfile((j['profile'] as Map).cast<String, Object?>()),
      events: events,
      settled: ((j['settled'] as List?) ?? const []).cast<String>().toSet(),
      explained: ((j['explained'] as List?) ?? const []).cast<String>().toSet(),
      settings: j['settings'] == null ? const AppSettings() : AppSettings.fromJson((j['settings'] as Map).cast<String, Object?>()),
      marks: [for (final m in (j['marks'] as List?) ?? const []) BloodDay.fromJson((m as Map).cast<String, Object?>())],
    );
  }
}
