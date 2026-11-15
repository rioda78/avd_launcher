import 'dart:io';
import 'package:path/path.dart' as p;

import '../models/adb_device.dart';
import 'output_parser.dart';
import 'process_runner.dart';

class AvdException implements Exception {
  AvdException(this.message);

  final String message;

  @override
  String toString() => message;
}

class LaunchOptions {
  const LaunchOptions({
    this.coldBoot = false,
    this.wipeData = false,
    this.noAudio = false,
  });

  final bool coldBoot;
  final bool wipeData;
  final bool noAudio;

  List<String> toArgs(String avdName) {
    final args = <String>['-avd', avdName];
    if (coldBoot) args.add('-no-snapshot-load');
    if (wipeData) args.add('-wipe-data');
    if (noAudio) args.add('-no-audio');
    return args;
  }
}

class AvdService {
  AvdService({ProcessRunner? runner}) : runner = runner ?? const RealProcessRunner();

  final ProcessRunner runner;

  Future<List<String>> listAvds(String emulatorPath) async {
    final result = await runner.run(
      emulatorPath,
      const ['-list-avds'],
      timeout: const Duration(seconds: 30),
    );
    final names = parseAvdList(result.stdout);
    if (names.isEmpty && result.exitCode != 0) {
      throw AvdException(
        'Gagal membaca daftar AVD (kode ${result.exitCode}).'
        '${_detail(result)}',
      );
    }
    return names;
  }

  Future<List<AdbDevice>> listDevices(String adbPath) async {
    final result = await runner.run(
      adbPath,
      const ['devices', '-l'],
      timeout: const Duration(seconds: 20),
    );
    final combined = [
      result.stdout,
      result.stderr,
    ].where((s) => s.trim().isNotEmpty).join('\n');
    final devices = parseAdbDevices(combined);
    if (devices.isEmpty && result.exitCode != 0) {
      throw AvdException(
        'Gagal membaca daftar perangkat adb (kode ${result.exitCode}).'
        '${_detail(result)}',
      );
    }
    return devices;
  }

  Future<void> startAvd({
    required String emulatorPath,
    required String sdkRoot,
    required String avdName,
    LaunchOptions options = const LaunchOptions(),
  }) async {
    final name = avdName.trim();
    if (name.isEmpty) {
      throw AvdException('Pilih satu virtual device terlebih dahulu.');
    }
    try {
      await runner.startDetached(
        emulatorPath,
        options.toArgs(name),
        workingDirectory: p.dirname(emulatorPath),
        environment: {
          'ANDROID_SDK_ROOT': sdkRoot,
          'ANDROID_HOME': sdkRoot,
        },
      );
    } on ProcessException catch (error) {
      throw AvdException(
        'Gagal menjalankan emulator untuk "$name".\n${error.message}',
      );
    }
  }

  Future<void> stopEmulator({
    required String adbPath,
    required String serial,
  }) async {
    if (!serial.startsWith('emulator-')) {
      throw AvdException(
        'Hanya emulator yang dapat dihentikan dari aplikasi ini ($serial).',
      );
    }
    final result = await runner.run(
      adbPath,
      ['-s', serial, 'emu', 'kill'],
      timeout: const Duration(seconds: 20),
    );
    if (result.exitCode != 0) {
      throw AvdException(
        'Gagal menghentikan $serial (kode ${result.exitCode}).'
        '${_detail(result)}',
      );
    }
  }

  String _detail(ProcessCommandResult result) {
    final text = result.stderr.trim().isNotEmpty
        ? result.stderr.trim()
        : result.stdout.trim();
    if (text.isEmpty) return '';
    return '\n$text';
  }
}
