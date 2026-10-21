
/// نموذج حالة اختبار ذهبية كما في `golden.schema.json`.
///
/// مستقل عن المحرك: يصف المدخلات والناتج المتوقع بصيغة بيانات فقط.
/// المرحلة ٢ تكتب المحوّل من هذا النموذج إلى مدخلات المحرك.
class GoldenCase {
  GoldenCase.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        group = json['group'] as String,
        title = json['title'] as String,
        source = json['source'] as String,
        subject = json['subject'] as String,
        rules = (json['rules'] as List<dynamic>? ?? const []).cast<String>(),
        profile = json['profile'] as Map<String, dynamic>,
        clock = json['clock'] as Map<String, dynamic>?,
        timeline = (json['timeline'] as List<dynamic>).cast<Map<String, dynamic>>(),
        answers = json['answers'] as Map<String, dynamic>? ?? const {},
        expected = (json['expected'] as List<dynamic>).cast<Map<String, dynamic>>(),
        notes = json['notes'] as String?,
        pendingOwner = json['pendingOwner'] as String?;

  final String id;
  final String group;
  final String title;
  final String source;
  final String subject;
  final List<String> rules;
  final Map<String, dynamic> profile;
  final Map<String, dynamic>? clock;
  final List<Map<String, dynamic>> timeline;
  final Map<String, dynamic> answers;
  final List<Map<String, dynamic>> expected;
  final String? notes;
  final String? pendingOwner;

  String get womanType => profile['womanType'] as String;

  /// آخر يوم مذكور في الخط الزمني أو التوقعات.
  int get lastDay {
    var last = 0;
    for (final item in [...timeline, ...expected]) {
      final days = item['days'] as String?;
      if (days != null) {
        last = last < dayRangeEnd(days) ? dayRangeEnd(days) : last;
      }
      final at = item['at'] as String?;
      if (at != null) {
        final d = instantDay(at);
        last = last < d ? d : last;
      }
    }
    return last;
  }

  static final _rangeRe = RegExp(r'^(\d{1,3})(?:-(\d{1,3}))?$');
  static final _instantRe =
      RegExp(r'^D(\d{1,3}) (fajr|maghrib|noon|(?:[01]\d|2[0-3]):[0-5]\d)$');

  static int dayRangeStart(String range) =>
      int.parse(_rangeRe.firstMatch(range)!.group(1)!);

  static int dayRangeEnd(String range) {
    final m = _rangeRe.firstMatch(range)!;
    return int.parse(m.group(2) ?? m.group(1)!);
  }

  static int instantDay(String instant) =>
      int.parse(_instantRe.firstMatch(instant)!.group(1)!);

  static bool isValidRange(String range) {
    final m = _rangeRe.firstMatch(range);
    if (m == null) return false;
    return dayRangeStart(range) <= dayRangeEnd(range);
  }

  static bool isValidInstant(String instant) => _instantRe.hasMatch(instant);
}

const goldenStates = {
  'HAYD', 'NIFAS', 'IST', 'IST_Q', 'IST_M', 'IST_K', 'IST_U', 'TAHIR',
  'JAM3', 'JAM3_M', 'JAM3_N', 'JAM3_NM', 'GHAYR', 'PENDING', 'NOT_HAYD',
};

const goldenWomanTypes = {
  'ANY', 'VW', 'V', 'W', 'MUB', 'MUD', 'NAS_T', 'NAS_C', 'NAS_B',
};
