import 'package:flutter/material.dart';

/// ما تريد المرأة أن تعرفه (`docs/UX.md` §٢.١): يحدد ما يُسأل وما يُبرَز.
enum AskIntent {
  isHayd,
  stopped,
  overflow,
  nifas,
  istihadha,
  qada;

  String get title => switch (this) {
        AskIntent.isHayd => 'نزل دم، هل هو حيض؟',
        AskIntent.stopped => 'انقطع الدم، أغتسل وأصلي؟',
        AskIntent.overflow => 'الدم طال أو اضطرب، أي الأيام حيض؟',
        AskIntent.nifas => 'بعد ولادة أو سقط',
        AskIntent.istihadha => 'استحاضة: ماذا أفعل قبل الصلاة؟',
        AskIntent.qada => 'ما عليّ من قضاء؟',
      };

  String get subtitle => switch (this) {
        AskIntent.isHayd => 'لوّني أيام الدم على التقويم ويخبرك التطبيق بحكمها',
        AskIntent.stopped => 'لوّني أيام الدم إلى يوم الانقطاع',
        AskIntent.overflow => 'لوّني كل الأيام، والصفات إن تذكرتِها',
        AskIntent.nifas => 'حددي يوم الولادة ثم أيام الدم',
        AskIntent.istihadha => 'اختبار القطنة ثم وظيفة الصلاة القادمة',
        AskIntent.qada => 'الصلوات والصيام الواجب قضاؤها مما لوّنتِه',
      };

  IconData get icon => switch (this) {
        AskIntent.isHayd => Icons.water_drop_outlined,
        AskIntent.stopped => Icons.check_circle_outline,
        AskIntent.overflow => Icons.calendar_view_month_outlined,
        AskIntent.nifas => Icons.child_care_outlined,
        AskIntent.istihadha => Icons.science_outlined,
        AskIntent.qada => Icons.replay_outlined,
      };

  /// التوجيه أعلى التقويم.
  String get hint => switch (this) {
        AskIntent.isHayd => 'انقري كل يوم رأيتِ فيه الدم. إن كان مستمرًّا فلوّني إلى اليوم.',
        AskIntent.stopped => 'لوّني أيام الدم حتى آخر يوم رأيتِه فيه، ثم انقري «احسبي».',
        AskIntent.overflow => 'لوّني كل أيام الدم، ولوّني الأشهر السابقة إن تذكرتِها فتُعرف عادتك.',
        AskIntent.nifas => 'لوّني أيام الدم بعد الولادة.',
        AskIntent.istihadha => 'لوّني أيام الدم الجاري، ثم اختبري القطنة من بطاقة الجواب.',
        AskIntent.qada => 'لوّني أيام الدم التي تركتِ فيها الصلاة أو الصوم.',
      };
}
