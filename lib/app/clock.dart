import 'package:adhan/adhan.dart';

import '../data/app_settings.dart';
import '../fiqh/fiqh.dart';

/// مواقيت يدوية: دقائق من منتصف الليل لكل يوم (الإدخال اليدوي الكامل، T-01).
class ManualDayClock extends DayClock {
  const ManualDayClock({required this.fajrMinutes, required this.maghribMinutes});

  final int fajrMinutes;
  final int maghribMinutes;

  static DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  DateTime fajr(DateTime date) => _midnight(date).add(Duration(minutes: fajrMinutes));

  /// بلا حساب فلكي: الطلوع بعد الفجر بساعة ونصف تقريبًا، والزوال منتصف النهار.
  @override
  DateTime sunrise(DateTime date) => fajr(date).add(const Duration(minutes: 90));

  @override
  DateTime dhuhr(DateTime date) {
    final s = sunrise(date);
    final m = maghrib(date);
    return s.add(Duration(minutes: m.difference(s).inMinutes ~/ 2));
  }

  @override
  DateTime maghrib(DateTime date) => _midnight(date).add(Duration(minutes: maghribMinutes));
}

/// مواقيت محسوبة بالطريقة الشيعية (`PLAN.md` §٢.٢): الفجر الصادق بزاوية ١٧٫٧°
/// والمغرب بذهاب الحمرة المشرقية (٤٫٥° بعد الغروب)، مع ضبط يدوي بالدقائق.
class AdhanDayClock extends DayClock {
  AdhanDayClock({required double latitude, required double longitude, this.fajrAdjustMinutes = 0, this.maghribAdjustMinutes = 0}) : _coordinates = Coordinates(latitude, longitude);

  final Coordinates _coordinates;
  final int fajrAdjustMinutes;
  final int maghribAdjustMinutes;

  static final CalculationParameters _params = CalculationMethod.tehran.getParameters();

  PrayerTimes _times(DateTime date) => PrayerTimes(_coordinates, DateComponents(date.year, date.month, date.day), _params);

  @override
  DateTime fajr(DateTime date) => _times(date).fajr.add(Duration(minutes: fajrAdjustMinutes));

  @override
  DateTime sunrise(DateTime date) => _times(date).sunrise;

  @override
  DateTime dhuhr(DateTime date) => _times(date).dhuhr;

  @override
  DateTime maghrib(DateTime date) => _times(date).maghrib.add(Duration(minutes: maghribAdjustMinutes));
}

/// الساعة من الإعدادات: الموقع إن وُجد، وإلا اليدوي، وإلا افتراضي مع تنبيه في الواجهة.
DayClock clockFromSettings(AppSettings s) {
  if (s.hasLocation) {
    return AdhanDayClock(latitude: s.latitude!, longitude: s.longitude!, fajrAdjustMinutes: s.fajrAdjustMinutes, maghribAdjustMinutes: s.maghribAdjustMinutes);
  }
  return ManualDayClock(fajrMinutes: s.manualFajrMinutes ?? 4 * 60 + 30, maghribMinutes: s.manualMaghribMinutes ?? 18 * 60 + 30);
}
