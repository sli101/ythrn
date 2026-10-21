import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/app_settings.dart';
import '../../data/backup.dart';
import '../cities.dart';
import '../clock.dart';
import '../labels.dart';
import '../../data/fiqh_store.dart';
import '../providers.dart';
import 'explorer_screen.dart';

/// الإعدادات (`docs/SPEC.md` §١١ ٧): الموقع (بالإذن أو باختيار المدينة أو
/// بالإحداثيات) والمواقيت والضبط اليدوي، والتصدير والاستيراد، وحذف كل البيانات.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _place = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    _place.dispose();
    super.dispose();
  }

  void _load(AppSettings s) {
    if (_loaded) return;
    _loaded = true;
    _lat.text = s.latitude?.toString() ?? '';
    _lng.text = s.longitude?.toString() ?? '';
    _place.text = s.placeName ?? '';
  }

  Future<void> _save(AppSettings current) async {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if ((lat == null) != (lng == null) || (lat != null && (lat.abs() > 90 || lng!.abs() > 180))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخلي خط العرض وخط الطول معًا بقيم صحيحة، أو اتركيهما فارغين')));
      return;
    }
    final next = lat == null ? current.copyWith(clearLocation: true) : current.copyWith(latitude: lat, longitude: lng, placeName: _place.text.trim().isEmpty ? null : _place.text.trim());
    await ref.read(appStateProvider.notifier).updateSettings(next);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حُفظت الإعدادات')));
  }

  /// الموقع بإذن الجهاز: لا يُرسل إلى أي خادم؛ يُحفظ محليًّا للمواقيت فقط.
  Future<void> _locate(AppSettings s) async {
    String? problem;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        problem = 'خدمة الموقع مغلقة في الجهاز';
      } else {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          problem = 'لم يُمنح إذن الموقع؛ اختاري المدينة أو أدخلي الإحداثيات';
        } else {
          final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.low));
          _lat.text = pos.latitude.toStringAsFixed(2);
          _lng.text = pos.longitude.toStringAsFixed(2);
          _place.text = 'موقعي';
          await ref.read(appStateProvider.notifier).updateSettings(s.copyWith(latitude: pos.latitude, longitude: pos.longitude, placeName: 'موقعي'));
        }
      }
    } catch (e) {
      problem = 'تعذّر تحديد الموقع';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem ?? 'حُفظ الموقع')));
  }

  Future<void> _pickCity(AppSettings s) async {
    final city = await showModalBottomSheet<City>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CityPicker(onPick: (c) => Navigator.pop(ctx, c)),
    );
    if (city == null) return;
    _lat.text = city.latitude.toString();
    _lng.text = city.longitude.toString();
    _place.text = city.label;
    await ref.read(appStateProvider.notifier).updateSettings(s.copyWith(latitude: city.latitude, longitude: city.longitude, placeName: city.label));
  }

  Future<void> _export() async {
    final state = ref.read(appStateProvider).value;
    if (state == null) return;
    final text = Backup.encode(state);
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('نسخة احتياطية'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('انسخي النص واحفظيه في مكان آمن؛ يُستورد من الزر المجاور. لا يُرسل إلى أي خادم.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('إغلاق')),
          FilledButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: text));
              if (d.mounted) Navigator.pop(d);
              messenger.showSnackBar(const SnackBar(content: Text('نُسخت النسخة الاحتياطية')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('نسخ'),
          ),
        ],
      ),
    );
  }

  Future<void> _import() async {
    final text = await showDialog<String>(context: context, builder: (_) => const _ImportDialog());
    if (text == null || text.trim().isEmpty || !mounted) return;
    final StoredState s;
    try {
      s = Backup.decode(text);
    } on FormatException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('استبدال البيانات الحالية؟'),
        content: Text('النسخة فيها ${s.events.length} حدثًا و${Labels.womanType(s.profile.habit.type)}. تُحذف البيانات الحالية كلها وتحل محلها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('استيراد')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(appStateProvider.notifier).importState(s);
    if (mounted) {
      _loaded = false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم الاستيراد')));
    }
  }

  Future<void> _pickManual(AppSettings s, {required bool fajr}) async {
    final initial = fajr ? (s.manualFajrMinutes ?? 270) : (s.manualMaghribMinutes ?? 1110);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (t == null) return;
    final m = t.hour * 60 + t.minute;
    await ref.read(appStateProvider.notifier).updateSettings(fajr ? s.copyWith(manualFajrMinutes: m) : s.copyWith(manualMaghribMinutes: m));
  }

  Future<void> _adjust(AppSettings s, {required bool fajr, required int delta}) =>
      ref.read(appStateProvider.notifier).updateSettings(fajr ? s.copyWith(fajrAdjustMinutes: s.fajrAdjustMinutes + delta) : s.copyWith(maghribAdjustMinutes: s.maghribAdjustMinutes + delta));

  Future<void> _clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('حذف كل البيانات؟'),
        content: const Text('تُحذف الأحداث والملف الشخصي والأجوبة من هذا الجهاز ولا يمكن استرجاعها. الإعدادات تبقى.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(d).colorScheme.error),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(appStateProvider.notifier).clearAll();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    _load(s);
    final clock = clockFromSettings(s);
    final today = DateTime.now();
    final profile = ref.watch(appStateProvider).value?.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('المواقيت', style: Theme.of(context).textTheme.titleMedium),
          const Text('اليوم الشرعي من الفجر الصادق إلى المغرب. بالموقع تُحسب بالطريقة الشيعية (الفجر ١٧٫٧° والمغرب بذهاب الحمرة)، وإلا تُدخل يدويًّا.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Text(
            'اليوم: الفجر ${Labels.time(clock.fajr(today))} · المغرب ${Labels.time(clock.maghrib(today))}${s.hasLocation
                ? ' (محسوبة)'
                : s.hasManualTimes
                ? ' (يدوية)'
                : ' (افتراضية: اضبطيها)'}',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              FilledButton.tonalIcon(onPressed: () => _locate(s), icon: const Icon(Icons.my_location), label: const Text('حدّدي موقعي')),
              FilledButton.tonalIcon(onPressed: () => _pickCity(s), icon: const Icon(Icons.location_city), label: const Text('اختيار المدينة')),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lat,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'خط العرض', hintText: 'مثل 33.31'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lng,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            decoration: const InputDecoration(labelText: 'خط الطول', hintText: 'مثل 44.37'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _place,
            decoration: const InputDecoration(labelText: 'اسم المكان (اختياري)'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => _save(s), child: const Text('حفظ الموقع')),
          if (s.hasLocation) ...[
            const SizedBox(height: 8),
            _AdjustRow(
              label: 'ضبط الفجر بالدقائق',
              value: s.fajrAdjustMinutes,
              onChange: (d) => _adjust(s, fajr: true, delta: d),
            ),
            _AdjustRow(
              label: 'ضبط المغرب بالدقائق',
              value: s.maghribAdjustMinutes,
              onChange: (d) => _adjust(s, fajr: false, delta: d),
            ),
          ],
          const Divider(height: 32),
          Text('إدخال يدوي (يُستعمل إذا لم يُحدَّد موقع)', style: Theme.of(context).textTheme.titleMedium),
          ListTile(
            leading: const Icon(Icons.wb_twilight),
            title: const Text('الفجر الصادق'),
            subtitle: Text(s.manualFajrMinutes == null ? 'غير محدد' : _hm(s.manualFajrMinutes!)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _pickManual(s, fajr: true),
          ),
          ListTile(
            leading: const Icon(Icons.nights_stay_outlined),
            title: const Text('المغرب'),
            subtitle: Text(s.manualMaghribMinutes == null ? 'غير محدد' : _hm(s.manualMaghribMinutes!)),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => _pickManual(s, fajr: false),
          ),
          const Divider(height: 32),
          if (profile != null) ...[
            Text('الملف', style: Theme.of(context).textTheme.titleMedium),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(Labels.womanType(profile.habit.type)),
              subtitle: Text(
                [
                  if (profile.habit.count != null) 'العدد ${profile.habit.count}',
                  if (profile.habit.anchorDate != null) 'آخر وقت ${Labels.shortDate(profile.habit.anchorDate!)}',
                  'الحيضات المحكوم بها ${profile.habit.history.length}',
                ].join(' · '),
              ),
            ),
            const Divider(height: 32),
          ],
          Text('النسخ الاحتياطي', style: Theme.of(context).textTheme.titleMedium),
          const Text('نسخة نصية من كل بياناتك تنسخينها وتحفظينها بنفسك، وتستوردينها على جهاز آخر.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.upload_outlined), label: const Text('تصدير')),
              OutlinedButton.icon(onPressed: _import, icon: const Icon(Icons.download_outlined), label: const Text('استيراد')),
            ],
          ),
          const Divider(height: 32),
          if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux) ...[
            Text('للمدقق', style: Theme.of(context).textTheme.titleMedium),
            ListTile(
              leading: const Icon(Icons.science_outlined),
              title: const Text('المستكشف'),
              subtitle: const Text('تشغيل حالة ذهبية على المحرك وعرض التقرير'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ExplorerScreen())),
            ),
            const Divider(height: 32),
          ],
          Text('الخصوصية', style: Theme.of(context).textTheme.titleMedium),
          const Text('كل البيانات على هذا الجهاز فقط؛ لا خادم ولا مزامنة.', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('حذف كل البيانات'),
          ),
        ],
      ),
    );
  }

  static String _hm(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// حوار لصق النسخة؛ يملك متحكم النص حتى لا يُتلف قبل انتهاء حركة الإغلاق.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('استيراد نسخة'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: _ctrl,
            maxLines: 8,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'ألصقي نص النسخة هنا'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(context, _ctrl.text), child: const Text('استيراد')),
        ],
      );
}

class _CityPicker extends StatefulWidget {
  const _CityPicker({required this.onPick});
  final ValueChanged<City> onPick;

  @override
  State<_CityPicker> createState() => _CityPickerState();
}

class _CityPickerState extends State<_CityPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = cities.where((c) => _q.isEmpty || c.name.contains(_q) || c.country.contains(_q)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحثي عن المدينة أو البلد'),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [for (final c in list) ListTile(title: Text(c.name), subtitle: Text(c.country), onTap: () => widget.onPick(c))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdjustRow extends StatelessWidget {
  const _AdjustRow({required this.label, required this.value, required this.onChange});
  final String label;
  final int value;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      IconButton(onPressed: () => onChange(-1), icon: const Icon(Icons.remove)),
      Text('${value >= 0 ? '+' : ''}$value'),
      IconButton(onPressed: () => onChange(1), icon: const Icon(Icons.add)),
    ],
  );
}
