import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/db/app_database.dart';
import 'data/drift_fiqh_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  final database = AppDatabase();
  runApp(
    ProviderScope(
      overrides: [storeProvider.overrideWithValue(DriftFiqhStore(database))],
      child: const YthrnApp(),
    ),
  );
}
