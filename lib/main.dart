import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sqflite/sqflite.dart' show databaseFactorySqflitePlugin;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show DatabaseFactory, databaseFactoryFfi, sqfliteFfiInit;

import 'data/store.dart';
import 'services/drive_sync.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows and Linux use the bundled SQLite through FFI; Android, iOS and macOS use the sqflite plugin.
  DatabaseFactory factory = databaseFactorySqflitePlugin;
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    factory = databaseFactoryFfi;
  }

  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final store = await AppStore.open(dbPath: p.join(dir.path, 'cuebill.sqlite'), factory: factory, filesDir: dir.path);
  Clock.start();

  // Google Drive: reconnect quietly and run the daily backup in the background; never blocks startup.
  final drive = DriveSync(store);
  unawaited(drive.start());

  runApp(CueBillApp(store: store, drive: drive));
}

class CueBillApp extends StatelessWidget {
  const CueBillApp({super.key, required this.store, this.drive});

  final AppStore store;

  /// Google Drive backups. Tests leave it out, which gives a "not set up" DriveSync.
  final DriveSync? drive;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        if (drive != null)
          ChangeNotifierProvider.value(value: drive!)
        else
          ChangeNotifierProvider(create: (_) => DriveSync(store, useDefaultAuth: false)),
        ChangeNotifierProvider(create: (_) => Nav()),
        ChangeNotifierProvider(create: (_) => ThemeController()),
      ],
      child: Consumer<ThemeController>(
        builder: (context, theme, _) => MaterialApp(
          title: 'CueBill',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: theme.value,
          home: const AppShell(),
        ),
      ),
    );
  }
}
