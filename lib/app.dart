import 'package:flutter/material.dart';

import 'ui/home_page.dart';
import 'ui/launcher_controller.dart';

class AvdLauncherApp extends StatefulWidget {
  const AvdLauncherApp({super.key, required this.controller});

  final LauncherController controller;

  @override
  State<AvdLauncherApp> createState() => _AvdLauncherAppState();
}

class _AvdLauncherAppState extends State<AvdLauncherApp> {
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AVD Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F7B6C)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F7B6C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: HomePage(controller: widget.controller),
    );
  }
}
