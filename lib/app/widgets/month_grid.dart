import 'package:flutter/material.dart';

import '../../fiqh/fiqh.dart';

/// شبكة شهر هجري (`docs/UX.md` §٢.٢): سبعة أعمدة من السبت، كل خلية برقم اليوم
/// الهجري والميلادي الصغير تحته. الأيام الملوَّنة دمًا، وحكمها بلونه إن حُسب،
/// واليوم الحالي بإطار. النقر والنقر المطوّل شأن الشاشة.
class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.year,
    required this.month,
    required this.today,
    required this.marked,
    required this.colors,
    required this.onTap,
    required this.onLongPress,
    this.rangeStart,
    this.maxDay,
  });

  final int year;
  final int month;
  final DateTime today;

  /// أيام الدم (منتصف ليل اليوم).
  final Set<DateTime> marked;

  /// لون حكم اليوم إن حُسب.
  final Map<DateTime, Color> colors;

  final ValueChanged<DateTime> onTap;
  final ValueChanged<DateTime> onLongPress;

  /// أول يوم في مدى جارٍ اختياره (نقر مطوّل) لإبرازه.
  final DateTime? rangeStart;

  /// آخر يوم يُقبل (لا مستقبل).
  final DateTime? maxDay;

  static const weekdays = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];

  @override
  Widget build(BuildContext context) {
    final first = HijriDate(year, month, 1).toDate();
    final days = HijriDate.daysInMonth(year, month);
    // عمود السبت = ٠. Dart: الاثنين ١ … الأحد ٧ → السبت ٦.
    final offset = first.weekday % 7; // السبت ٦→٦، الأحد ٧→٠… نعيد ترتيبها أدناه.
    final startCol = (offset + 1) % 7; // السبت → ٠
    final cells = <Widget>[];
    for (var i = 0; i < startCol; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= days; d++) {
      final date = DateTime(first.year, first.month, first.day + d - 1);
      cells.add(_Cell(
        hijriDay: d,
        date: date,
        isToday: date == today,
        marked: marked.contains(date),
        color: colors[date],
        isRangeStart: rangeStart == date,
        disabled: maxDay != null && date.isAfter(maxDay!),
        onTap: () => onTap(date),
        onLongPress: () => onLongPress(date),
      ));
    }
    while (cells.length % 7 != 0) {
      cells.add(const SizedBox.shrink());
    }
    return Column(
      children: [
        Row(
          children: [
            for (final w in weekdays) Expanded(child: Center(child: Text(w, style: Theme.of(context).textTheme.labelMedium))),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < cells.length ~/ 7; r++)
          Row(
            children: [for (var c = 0; c < 7; c++) Expanded(child: AspectRatio(aspectRatio: 1, child: cells[r * 7 + c]))],
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.hijriDay,
    required this.date,
    required this.isToday,
    required this.marked,
    required this.color,
    required this.isRangeStart,
    required this.disabled,
    required this.onTap,
    required this.onLongPress,
  });

  final int hijriDay;
  final DateTime date;
  final bool isToday;
  final bool marked;
  final Color? color;
  final bool isRangeStart;
  final bool disabled;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = color ?? (marked ? theme.colorScheme.error : null);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Semantics(
        label: '$hijriDay ${HijriDate.monthNames[HijriDate.fromDate(date).month - 1]}${marked ? '، دم' : ''}',
        button: true,
        child: InkWell(
          onTap: disabled ? null : onTap,
          onLongPress: disabled ? null : onLongPress,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: fill?.withValues(alpha: marked ? 0.85 : 0.25),
              borderRadius: BorderRadius.circular(8),
              border: isRangeStart
                  ? Border.all(color: theme.colorScheme.primary, width: 3)
                  : isToday
                      ? Border.all(color: theme.colorScheme.primary, width: 2)
                      : null,
            ),
            child: Opacity(
              opacity: disabled ? 0.35 : 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$hijriDay', style: theme.textTheme.titleMedium?.copyWith(color: marked && fill != null ? Colors.white : null, fontWeight: isToday ? FontWeight.bold : null)),
                  Text('${date.day}', style: theme.textTheme.labelSmall?.copyWith(color: marked && fill != null ? Colors.white70 : theme.colorScheme.outline)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
