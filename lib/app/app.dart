import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'screens/home_shell.dart';

/// جذر التطبيق: عربية فقط، RTL، ومؤقت يحدّث «الآن» كل دقيقة حتى تُعاد
/// المعالم (الفجر والمغرب وتمام الثلاثة والعشرة) آليًّا (`docs/SPEC.md` §٥.٢).
class YthrnApp extends ConsumerStatefulWidget {
  const YthrnApp({super.key});

  @override
  ConsumerState<YthrnApp> createState() => _YthrnAppState();
}

class _YthrnAppState extends ConsumerState<YthrnApp> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) => ref.read(nowProvider.notifier).state = DateTime.now());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'يطهرن',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomeShell(),
    );
  }
}
