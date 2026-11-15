import 'package:flutter/material.dart';

import 'app.dart';
import 'services/avd_service.dart';
import 'services/settings_store.dart';
import 'ui/launcher_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = LauncherController(
    settingsStore: SettingsStore(),
    service: AvdService(),
  );
  controller.initialize();
  runApp(AvdLauncherApp(controller: controller));
}
