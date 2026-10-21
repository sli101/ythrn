/// إعدادات التطبيق المحلية (T-01): الموقع للمواقيت المحسوبة بالطريقة الشيعية،
/// أو إدخال يدوي للفجر والمغرب، مع ضبط بالدقائق.
class AppSettings {
  const AppSettings({
    this.latitude,
    this.longitude,
    this.placeName,
    this.fajrAdjustMinutes = 0,
    this.maghribAdjustMinutes = 0,
    this.manualFajrMinutes,
    this.manualMaghribMinutes,
  });

  final double? latitude;
  final double? longitude;
  final String? placeName;

  /// ضبط يدوي بالدقائق على المواقيت المحسوبة لمن تتبع تقويم بلدها.
  final int fajrAdjustMinutes;
  final int maghribAdjustMinutes;

  /// إدخال يدوي كامل: دقائق من منتصف الليل. يُستعمل إذا لم يُحدَّد موقع.
  final int? manualFajrMinutes;
  final int? manualMaghribMinutes;

  bool get hasLocation => latitude != null && longitude != null;
  bool get hasManualTimes => manualFajrMinutes != null && manualMaghribMinutes != null;

  /// هل ضُبطت المواقيت بأي طريقة؟ وإلا تُعرض القيم الافتراضية مع تنبيه.
  bool get isConfigured => hasLocation || hasManualTimes;

  AppSettings copyWith({
    double? latitude,
    double? longitude,
    bool clearLocation = false,
    String? placeName,
    int? fajrAdjustMinutes,
    int? maghribAdjustMinutes,
    int? manualFajrMinutes,
    int? manualMaghribMinutes,
  }) =>
      AppSettings(
        latitude: clearLocation ? null : (latitude ?? this.latitude),
        longitude: clearLocation ? null : (longitude ?? this.longitude),
        placeName: clearLocation ? null : (placeName ?? this.placeName),
        fajrAdjustMinutes: fajrAdjustMinutes ?? this.fajrAdjustMinutes,
        maghribAdjustMinutes: maghribAdjustMinutes ?? this.maghribAdjustMinutes,
        manualFajrMinutes: manualFajrMinutes ?? this.manualFajrMinutes,
        manualMaghribMinutes: manualMaghribMinutes ?? this.manualMaghribMinutes,
      );

  Map<String, Object?> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'placeName': placeName,
        'fajrAdjustMinutes': fajrAdjustMinutes,
        'maghribAdjustMinutes': maghribAdjustMinutes,
        'manualFajrMinutes': manualFajrMinutes,
        'manualMaghribMinutes': manualMaghribMinutes,
      };

  static AppSettings fromJson(Map<String, Object?> j) => AppSettings(
        latitude: (j['latitude'] as num?)?.toDouble(),
        longitude: (j['longitude'] as num?)?.toDouble(),
        placeName: j['placeName'] as String?,
        fajrAdjustMinutes: (j['fajrAdjustMinutes'] as num?)?.toInt() ?? 0,
        maghribAdjustMinutes: (j['maghribAdjustMinutes'] as num?)?.toInt() ?? 0,
        manualFajrMinutes: (j['manualFajrMinutes'] as num?)?.toInt(),
        manualMaghribMinutes: (j['manualMaghribMinutes'] as num?)?.toInt(),
      );
}
