import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/adb_device.dart';
import 'emulator_diagnostics.dart';
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

class EmulatorLaunch {
  const EmulatorLaunch({required this.pid, required this.logPath});

  final int pid;
  final String logPath;
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

  Future<bool> isBootCompleted({
    required String adbPath,
    required String serial,
  }) async {
    final result = await runner.run(
      adbPath,
      ['-s', serial, 'shell', 'getprop', 'sys.boot_completed'],
      timeout: const Duration(seconds: 15),
    );
    if (result.exitCode != 0) return false;
    return parseBootCompleted(result.stdout);
  }

  Future<EmulatorLaunch> startAvd({
    required String emulatorPath,
    required String sdkRoot,
    required String avdName,
    String? avdHome,
    String? logDirectory,
    LaunchOptions options = const LaunchOptions(),
    Duration earlyExitWindow = const Duration(seconds: 3),
  }) async {
    final name = avdName.trim();
    if (name.isEmpty) {
      throw AvdException('Pilih satu virtual device terlebih dahulu.');
    }
    final resolvedAvdHome = (avdHome ?? '').trim();
    if (resolvedAvdHome.isNotEmpty) {
      _assertSystemImagePresent(
        sdkRoot: sdkRoot,
        avdName: name,
        avdHome: resolvedAvdHome,
      );
    }

    final logDir = (logDirectory ?? p.dirname(emulatorPath)).trim();
    final logPath = p.join(logDir, 'emulator-${sanitizeForFileName(name)}.log');
    final logFile = File(logPath);
    await logFile.parent.create(recursive: true);
    final sink = logFile.openWrite();
    var logHeader = 'AVD: $name\n'
        'Waktu: ${DateTime.now().toIso8601String()}\n'
        'Perintah: $emulatorPath ${options.toArgs(name).join(' ')}\n'
        'ANDROID_SDK_ROOT=$sdkRoot\n'
        'ANDROID_HOME=$sdkRoot\n'
        'ANDROID_AVD_HOME=${resolvedAvdHome.isEmpty ? '(tidak disetel)' : resolvedAvdHome}\n'
        '---\n';
    sink.write(logHeader);

    final environment = <String, String>{
      'ANDROID_SDK_ROOT': sdkRoot,
      'ANDROID_HOME': sdkRoot,
      if (resolvedAvdHome.isNotEmpty) 'ANDROID_AVD_HOME': resolvedAvdHome,
    };

    late final SpawnedProcess spawned;
    try {
      spawned = await runner.startDetachedWithStdio(
        emulatorPath,
        options.toArgs(name),
        workingDirectory: p.dirname(emulatorPath),
        environment: environment,
      );
    } on ProcessException catch (error) {
      await sink.flush();
      await sink.close();
      throw AvdException(
        'Gagal menjalankan emulator untuk "$name".\n${error.message}',
      );
    }

    sink.writeln('PID: ${spawned.pid}');
    final decoder = const Utf8Decoder(allowMalformed: true);
    void writeLog(List<int> data) {
      sink.write(decoder.convert(data));
      unawaited(sink.flush());
    }
    spawned.stdout.listen(writeLog, onError: (_) {});
    spawned.stderr.listen(writeLog, onError: (_) {});

    await Future<void>.delayed(earlyExitWindow);
    final stillRunning = await runner.isProcessRunning(spawned.pid);
    await sink.flush();
    if (!stillRunning) {
      await sink.close();
      final log = await _readLog(logPath);
      final extracted = extractEmulatorFailure(log);
      throw AvdException(
        'Emulator untuk "$name" berhenti sebelum tampil di adb.'
        '${extracted == null ? '' : '\n$extracted'}\n'
        'Log: $logPath',
      );
    }

    unawaited(sink.flush());
    return EmulatorLaunch(pid: spawned.pid, logPath: logPath);
  }

  void _assertSystemImagePresent({
    required String sdkRoot,
    required String avdName,
    required String avdHome,
  }) {
    final missing = missingSystemImagePath(
      sdkRoot: sdkRoot,
      avdName: avdName,
      avdHome: avdHome,
      directoryExists: (path) => Directory(path).existsSync(),
      readFileIfExists: (path) {
        final file = File(path);
        if (!file.existsSync()) return null;
        try {
          return file.readAsStringSync();
        } on FileSystemException {
          return null;
        }
      },
    );
    if (missing != null) {
      throw AvdException(
        'System image untuk "$avdName" tidak ditemukan:\n'
        '$missing\n'
        'Pasang image tersebut di SDK, atau pilih AVD lain yang imagenya sudah ada.',
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

  Future<bool> isProcessRunning(int pid) => runner.isProcessRunning(pid);

  Future<String> _readLog(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return '';
      return await file.readAsString();
    } on FileSystemException {
      return '';
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
