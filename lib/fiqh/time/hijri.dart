import 'day_clock.dart';

/// تاريخ هجري قمري (التقويم الحسابي المدني: الأشهر ٣٠ و٢٩ بالتناوب، وذو الحجة
/// ٣٠ في السنوات الكبيسة ١١ من كل ٣٠ سنة). يخدم إدخال الميلاد (H1-01) ونصف
/// الشهر للناسية (H7-05)؛ الفرق عن الرؤية يوم أو يومان (`docs/fiqh/assumptions.md` ٥٥).
class HijriDate implements Comparable<HijriDate> {
  const HijriDate(this.year, this.month, this.day);

  final int year;
  final int month;
  final int day;

  static const monthNames = [
    'محرم',
    'صفر',
    'ربيع الأول',
    'ربيع الآخر',
    'جمادى الأولى',
    'جمادى الآخرة',
    'رجب',
    'شعبان',
    'رمضان',
    'شوال',
    'ذو القعدة',
    'ذو الحجة',
  ];

  String get monthName => monthNames[month - 1];

  /// أيام منذ ١ محرم ١ هـ (الموافق ١٩ تموز ٦٢٢ م بالتقويم الميلادي المسقط).
  /// الحساب بالتوقيت العالمي حتى لا تدخل إزاحات التوقيت التاريخية (المتصفح يطبّقها).
  static final DateTime _epoch = DateTime.utc(622, 7, 19);

  static bool isLeapYear(int y) => ((11 * y) + 14) % 30 < 11;

  static int daysInMonth(int y, int m) => m == 12 ? (isLeapYear(y) ? 30 : 29) : (m.isOdd ? 30 : 29);

  static int daysInYear(int y) => isLeapYear(y) ? 355 : 354;

  /// رقم اليوم منذ الحقبة (١ محرم ١ هـ = ٠).
  int get dayNumber => (year - 1) * 354 + (3 + 11 * year) ~/ 30 + ((month - 1) * 59 + 1) ~/ 2 + day - 1;

  /// من رقم اليوم منذ الحقبة.
  factory HijriDate.fromDayNumber(int n) {
    var y = ((30 * n + 10646) ~/ 10631);
    while (HijriDate(y, 1, 1).dayNumber > n) {
      y--;
    }
    while (HijriDate(y + 1, 1, 1).dayNumber <= n) {
      y++;
    }
    var m = 1;
    while (m < 12 && HijriDate(y, m + 1, 1).dayNumber <= n) {
      m++;
    }
    return HijriDate(y, m, n - HijriDate(y, m, 1).dayNumber + 1);
  }

  /// التاريخ الهجري لليوم التقويمي الميلادي (الوقت يُهمل).
  factory HijriDate.fromDate(DateTime d) {
    final day = DateTime.utc(d.year, d.month, d.day);
    return HijriDate.fromDayNumber(day.difference(_epoch).inDays);
  }

  /// منتصف ليل اليوم الميلادي الموافق.
  DateTime toDate() {
    final u = _epoch.add(Duration(days: dayNumber));
    return DateTime(u.year, u.month, u.day);
  }

  /// اليوم التالي لتاريخ يومي بلا أثر للتوقيت الصيفي.
  static DateTime nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

  HijriDate addDays(int n) => HijriDate.fromDayNumber(dayNumber + n);

  /// أول يوم من الشهر.
  HijriDate get monthStart => HijriDate(year, month, 1);

  /// أول يوم من الشهر التالي.
  HijriDate get nextMonthStart => month == 12 ? HijriDate(year + 1, 1, 1) : HijriDate(year, month + 1, 1);

  bool get isValid => year >= 1 && month >= 1 && month <= 12 && day >= 1 && day <= daysInMonth(year, month);

  @override
  int compareTo(HijriDate other) => dayNumber.compareTo(other.dayNumber);

  @override
  bool operator ==(Object other) => other is HijriDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => '$day $monthName $year هـ';
}

/// نافذة وقت الناسية التي تتذكر النصف الأول أو الثاني من الشهر الهجري (H7-05):
/// [من، إلى) بفجر اليوم في الشهر الذي يقع فيه [reference]. النصف الأول الأيام
/// ١–١٥، والثاني من ١٦ إلى آخر الشهر (`docs/fiqh/assumptions.md` ٥٦).
(DateTime, DateTime) nasiyaHalfMonthWindow(int halfMonth, DateTime reference, DayClock clock) {
  final h = HijriDate.fromDate(reference);
  final HijriDate from;
  final HijriDate to;
  if (halfMonth == 1) {
    from = h.monthStart;
    to = HijriDate(h.year, h.month, 16);
  } else {
    from = HijriDate(h.year, h.month, 16);
    to = h.nextMonthStart;
  }
  return (clock.fajr(from.toDate()), clock.fajr(to.toDate()));
}
