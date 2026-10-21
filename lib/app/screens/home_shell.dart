import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'ask_screen.dart';
import 'calendar_screen.dart';
import 'qada_screen.dart';
import 'settings_screen.dart';

/// الهيكل (`docs/UX.md` §٣): اسألي، التقويم، القضاء، الإعدادات. لا تهيئة
/// مسبقة؛ أسئلة الملف تُسأل حين تلزم.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appStateProvider);
    return state.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('تعذّر تحميل البيانات: $e'))),
      data: (_) => Scaffold(
        body: IndexedStack(
          index: _index,
          children: const [AskScreen(), CalendarScreen(embedded: true), QadaScreen(), SettingsScreen()],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.help_outline), selectedIcon: Icon(Icons.help), label: 'اسألي'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'التقويم'),
            NavigationDestination(icon: Icon(Icons.replay_outlined), selectedIcon: Icon(Icons.replay), label: 'القضاء'),
            NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
          ],
        ),
      ),
    );
  }
}
