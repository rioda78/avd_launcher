import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'services/avd_service.dart';
import 'services/settings_store.dart';
import 'ui/launcher_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SettingsStore();
  if (args.contains('--write-settings-probe')) {
    await _runSettingsProbe(store);
    return;
  }
  final controller = LauncherController(
    settingsStore: store,
    service: AvdService(),
  );
  controller.initialize();
  runApp(AvdLauncherApp(controller: controller));
}

Future<void> _runSettingsProbe(SettingsStore store) async {
  final report = File(
    p.join(p.dirname(Platform.resolvedExecutable), 'settings-probe-result.txt'),
  );
  try {
    final settings = await store.load();
    await store.save(settings);
    final path = store.filePath ?? '';
    await report.writeAsString('SETTINGS_PATH=$path\nSTATUS=OK\n');
    exit(0);
  } catch (error) {
    try {
      await report.writeAsString('STATUS=FAIL\nERROR=$error\n');
    } catch (_) {}
    stderr.writeln(error);
    exit(1);
  }
}
