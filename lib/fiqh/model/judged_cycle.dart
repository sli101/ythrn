/// حيضة أُغلق حكمها (`docs/SPEC.md` §٣.٣). تدخل في تاريخ آلة العادة.
class JudgedCycle {
  const JudgedCycle({
    required this.start,
    required this.end,
    required this.bloodDays,
  });

  /// أول خروج للدم المحكوم بحيضيته.
  final DateTime start;

  /// النقاء التام الذي أُغلقت به الحيضة.
  final DateTime end;

  /// أيام الدم الفعلية (كسريًّا بالتلفيق)؛ الليلة الأولى والأخيرة لا تدخلان (ج م٥٤٠).
  final double bloodDays;

  @override
  String toString() => 'JudgedCycle($start → $end, $bloodDays يوم)';
}
