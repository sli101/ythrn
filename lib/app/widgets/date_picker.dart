import 'package:flutter/material.dart';

import '../../fiqh/fiqh.dart';
import '../labels.dart';

/// منتقي تاريخ بالتقويمين: هجري (حسابي، `HijriDate`) أو ميلادي (منتقي النظام).
/// يعيد منتصف ليل اليوم الميلادي الموافق.
Future<DateTime?> pickDate(BuildContext context, {required DateTime initial, required DateTime first, required DateTime last, bool hijriFirst = true}) => showDialog<DateTime>(
  context: context,
  builder: (_) => _DatePickerDialog(initial: initial, first: first, last: last, hijri: hijriFirst),
);

class _DatePickerDialog extends StatefulWidget {
  const _DatePickerDialog({required this.initial, required this.first, required this.last, required this.hijri});
  final DateTime initial;
  final DateTime first;
  final DateTime last;
  final bool hijri;

  @override
  State<_DatePickerDialog> createState() => _DatePickerDialogState();
}

class _DatePickerDialogState extends State<_DatePickerDialog> {
  late bool _hijri = widget.hijri;
  late HijriDate _h = HijriDate.fromDate(widget.initial);
  late DateTime _g = DateTime(widget.initial.year, widget.initial.month, widget.initial.day);

  DateTime get _value => _hijri ? _h.toDate() : _g;
  bool get _inRange => !_value.isBefore(DateTime(widget.first.year, widget.first.month, widget.first.day)) && !_value.isAfter(widget.last);

  void _setHijri(int? y, int? m, int? d) {
    final year = y ?? _h.year;
    final month = m ?? _h.month;
    var day = d ?? _h.day;
    final max = HijriDate.daysInMonth(year, month);
    if (day > max) day = max;
    setState(() => _h = HijriDate(year, month, day));
  }

  @override
  Widget build(BuildContext context) {
    final hFirst = HijriDate.fromDate(widget.first);
    final hLast = HijriDate.fromDate(widget.last);
    return AlertDialog(
      title: SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('هجري')),
          ButtonSegment(value: false, label: Text('ميلادي')),
        ],
        selected: {_hijri},
        onSelectionChanged: (s) => setState(() {
          // الانتقال يحافظ على اليوم نفسه.
          if (s.first) {
            _h = HijriDate.fromDate(_g);
          } else {
            _g = _h.toDate();
          }
          _hijri = s.first;
        }),
      ),
      content: _hijri
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('hijriDay'),
                        initialValue: _h.day,
                        decoration: const InputDecoration(labelText: 'اليوم'),
                        items: [for (var d = 1; d <= HijriDate.daysInMonth(_h.year, _h.month); d++) DropdownMenuItem(value: d, child: Text('$d'))],
                        onChanged: (v) => _setHijri(null, null, v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<int>(
                        key: const ValueKey('hijriMonth'),
                        initialValue: _h.month,
                        decoration: const InputDecoration(labelText: 'الشهر'),
                        items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(HijriDate.monthNames[m - 1]))],
                        onChanged: (v) => _setHijri(null, v, null),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  key: const ValueKey('hijriYear'),
                  initialValue: _h.year.clamp(hFirst.year, hLast.year),
                  decoration: const InputDecoration(labelText: 'السنة الهجرية'),
                  items: [for (var y = hLast.year; y >= hFirst.year; y--) DropdownMenuItem(value: y, child: Text('$y هـ'))],
                  onChanged: (v) => _setHijri(v, null, null),
                ),
                const SizedBox(height: 12),
                Text('الموافق ${Labels.date(_value)}', style: Theme.of(context).textTheme.bodySmall),
                const Text('التقويم حسابي؛ قد يختلف عن الرؤية بيوم.', style: TextStyle(fontSize: 11)),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(context: context, initialDate: _g, firstDate: widget.first, lastDate: widget.last, locale: const Locale('ar'));
                    if (picked != null) setState(() => _g = picked);
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(Labels.date(_g)),
                ),
                const SizedBox(height: 8),
                Text('الموافق ${HijriDate.fromDate(_g)}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(onPressed: _inRange ? () => Navigator.pop(context, _value) : null, child: const Text('تأكيد')),
      ],
    );
  }
}
