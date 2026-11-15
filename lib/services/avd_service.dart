import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/adb_device.dart';
import 'avd_config.dart';
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
    this.gpuMode,
  });

  final bool coldBoot;
  final bool wipeData;
  final bool noAudio;

  /// When set to auto, host, or swiftshader_indirect, passed as `-gpu`.
  /// Null or empty means the AVD's config.ini value is used.
  final String? gpuMode;

  List<String> toArgs(String avdName) {
    final args = <String>['-avd', avdName];
    if (coldBoot) args.add('-no-snapshot-load');
    if (wipeData) args.add('-wipe-data');
    if (noAudio) args.add('-no-audio');
    final gpu = gpuMode?.trim();
    if (gpu != null && gpu.isNotEmpty && gpu != 'default') {
      args.addAll(['-gpu', gpu]);
    }
    return args;
  }
}

class EmulatorLaunch {
  const EmulatorLaunch({required this.pid, required this.logPath});

  final int pid;
  final String logPath;
}

class AvdConfigSnapshot {
  const AvdConfigSnapshot({
    required this.avdName,
    required this.avdDirectory,
    required this.configPath,
    required this.document,
    required this.installedImages,
    required this.currentImageMissing,
  });

  final String avdName;
  final String avdDirectory;
  final String configPath;
  final IniDocument document;
  final List<SystemImage> installedImages;
  final bool currentImageMissing;

  String get imageSysdir => document.get('image.sysdir.1') ?? '';
  String get ramSize => document.get('hw.ramSize') ?? '2048';
  String get storageSize => document.get('disk.dataPartition.size') ?? '6G';
  String get gpuMode => document.get('hw.gpu.mode') ?? 'auto';
  String get cpuCores => document.get('hw.cpu.ncore') ?? '4';
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
    final environment = <String, String>{
      'ANDROID_SDK_ROOT': sdkRoot,
      'ANDROID_HOME': sdkRoot,
      if (resolvedAvdHome.isNotEmpty) 'ANDROID_AVD_HOME': resolvedAvdHome,
    };
    final args = options.toArgs(name);
    final header = 'AVD: $name\n'
        'Waktu: ${DateTime.now().toIso8601String()}\n'
        'Perintah: $emulatorPath ${args.join(' ')}\n'
        'Direktori kerja: ${p.dirname(emulatorPath)}\n'
        'ANDROID_SDK_ROOT=$sdkRoot\n'
        'ANDROID_HOME=$sdkRoot\n'
        'ANDROID_AVD_HOME=${resolvedAvdHome.isEmpty ? '(tidak disetel)' : resolvedAvdHome}\n'
        '---\n';
    await logFile.writeAsString(header);

    late final int pid;
    try {
      pid = await runner.startDetachedHidden(
        emulatorPath,
        args,
        workingDirectory: p.dirname(emulatorPath),
        environment: environment,
        logPath: logPath,
      );
    } on ProcessException catch (error) {
      throw AvdException(
        'Gagal menjalankan emulator untuk "$name".\n${error.message}',
      );
    }

    await logFile.writeAsString('PID: $pid\n', mode: FileMode.append);

    await Future<void>.delayed(earlyExitWindow);
    final stillRunning = await runner.isProcessRunning(pid);
    if (!stillRunning) {
      final log = await _readLog(logPath);
      final extracted = extractEmulatorFailure(log);
      throw AvdException(
        'Emulator untuk "$name" berhenti sebelum tampil di adb.'
        '${extracted == null ? '' : '\n$extracted'}\n'
        'Log: $logPath',
      );
    }

    return EmulatorLaunch(pid: pid, logPath: logPath);
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
        'Pasang image tersebut di SDK, atau pilih AVD lain yang imagenya sudah ada.\n'
        'Contoh: ${sdkmanagerInstallCommand(missing)}',
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

  bool isAvdRunning({required String avdName, required String avdHome}) {
    final directory = resolveAvdDirectory(
      avdName: avdName,
      avdHome: avdHome,
      readFileIfExists: _readIfExists,
    );
    return isAvdLockHeld(directory);
  }

  AvdConfigSnapshot loadAvdConfig({
    required String avdName,
    required String avdHome,
    required String sdkRoot,
  }) {
    final directory = resolveAvdDirectory(
      avdName: avdName,
      avdHome: avdHome,
      readFileIfExists: _readIfExists,
    );
    final configPath = p.join(directory, 'config.ini');
    final content = _readIfExists(configPath);
    if (content == null) {
      throw AvdException('config.ini tidak ditemukan untuk "$avdName":\n$configPath');
    }
    final document = IniDocument.parse(content);
    final images = listInstalledSystemImages(sdkRoot);
    final current = document.get('image.sysdir.1') ?? '';
    final missing = current.isNotEmpty &&
        !Directory(p.normalize(p.join(sdkRoot, current))).existsSync();
    return AvdConfigSnapshot(
      avdName: avdName,
      avdDirectory: directory,
      configPath: configPath,
      document: document,
      installedImages: images,
      currentImageMissing: missing,
    );
  }

  String saveAvdConfig({
    required AvdConfigSnapshot snapshot,
    required String sdkRoot,
    required String imageSysdir,
    required String ramSize,
    required String storageSize,
    required String gpuMode,
    required String cpuCores,
    DateTime? now,
    bool Function(String path)? avdIsRunning,
  }) {
    final running = avdIsRunning ?? isAvdLockHeld;
    if (running(snapshot.avdDirectory)) {
      throw AvdException(
        'AVD "${snapshot.avdName}" sedang berjalan. Hentikan emulator dulu sebelum mengedit.',
      );
    }
    final image = imageSysdir.trim();
    final normalizedImage = image.endsWith('\\') || image.endsWith('/')
        ? image
        : '${image.replaceAll('/', '\\')}\\';
    final ram = ramSize.trim();
    final storage = normalizeStorageSize(storageSize);
    final gpu = gpuMode.trim();
    final cores = cpuCores.trim();
    final validation = validateAvdConfig(
      ramSize: ram,
      storageSize: storage,
      gpuMode: gpu,
      cpuCores: cores,
      imageSysdir: normalizedImage,
      imageExists: (sysdir) =>
          Directory(p.normalize(p.join(sdkRoot, sysdir))).existsSync(),
    );
    if (validation.hasError) {
      throw AvdException(validation.firstError!);
    }

    final document = IniDocument.parse(File(snapshot.configPath).readAsStringSync());
    document.set('image.sysdir.1', normalizedImage);
    document.set('hw.ramSize', ram);
    document.set('disk.dataPartition.size', storage);
    document.set('hw.gpu.mode', gpu);
    document.set('hw.gpu.enabled', gpu == 'off' ? 'no' : 'yes');
    document.set('hw.cpu.ncore', cores);

    final backupPath = backupConfigPath(snapshot.configPath, now ?? DateTime.now());
    File(snapshot.configPath).copySync(backupPath);
    File(snapshot.configPath).writeAsStringSync(document.encode());
    return backupPath;
  }

  List<SystemImage> installedSystemImages(String sdkRoot) =>
      listInstalledSystemImages(sdkRoot);

  Future<List<String>> listDeviceProfiles({
    required String sdkRoot,
    String? avdManagerPath,
  }) async {
    final path = (avdManagerPath ?? findAvdManagerPath(sdkRoot)).trim();
    if (path.isEmpty) {
      return List<String>.from(kFallbackDeviceProfiles);
    }
    final result = await runner.run(
      path,
      const ['list', 'device', '-c'],
      timeout: const Duration(seconds: 30),
      environment: {
        'ANDROID_SDK_ROOT': sdkRoot,
        'ANDROID_HOME': sdkRoot,
      },
      runInShell: Platform.isWindows && path.toLowerCase().endsWith('.bat'),
    );
    final names = parseDeviceList('${result.stdout}\n${result.stderr}');
    if (names.isEmpty) {
      return List<String>.from(kFallbackDeviceProfiles);
    }
    return names;
  }

  Future<void> createAvd({
    required String sdkRoot,
    required String name,
    required String packageId,
    required String deviceId,
    required String ramSize,
    required String storageSize,
    required String gpuMode,
    String? avdHome,
    String? avdManagerPath,
    Iterable<String> existingNames = const [],
  }) async {
    final trimmedName = name.trim();
    final validation = validateAvdConfig(
      name: trimmedName,
      existingNames: existingNames,
      ramSize: ramSize,
      storageSize: storageSize,
      gpuMode: gpuMode,
      imageSysdir: packageId,
      requireImage: true,
      imageExists: (id) {
        final image = SystemImage.tryParsePackageId(id) ?? SystemImage.tryParseSysdir(id);
        if (image == null) return false;
        return Directory(p.join(sdkRoot, image.relativeDir)).existsSync();
      },
    );
    if (validation.hasError) {
      throw AvdException(validation.firstError!);
    }

    final manager = (avdManagerPath ?? findAvdManagerPath(sdkRoot)).trim();
    if (manager.isEmpty) {
      throw AvdException(avdManagerMissingMessage(sdkRoot));
    }

    final environment = <String, String>{
      'ANDROID_SDK_ROOT': sdkRoot,
      'ANDROID_HOME': sdkRoot,
      if (avdHome != null && avdHome.trim().isNotEmpty) 'ANDROID_AVD_HOME': avdHome.trim(),
    };
    final result = await runner.run(
      manager,
      [
        'create',
        'avd',
        '-n',
        trimmedName,
        '-k',
        packageId,
        '-d',
        deviceId,
      ],
      timeout: const Duration(seconds: 60),
      environment: environment,
      runInShell: Platform.isWindows && manager.toLowerCase().endsWith('.bat'),
      stdin: 'no\n',
    );
    if (result.exitCode != 0) {
      throw AvdException(
        'Gagal membuat AVD "$trimmedName" (kode ${result.exitCode}).'
        '${_detail(result)}',
      );
    }

    final home = (avdHome ?? '').trim().isNotEmpty
        ? avdHome!.trim()
        : p.join(Platform.environment['USERPROFILE'] ?? '', '.android', 'avd');
    final snapshot = loadAvdConfig(
      avdName: trimmedName,
      avdHome: home,
      sdkRoot: sdkRoot,
    );
    saveAvdConfig(
      snapshot: snapshot,
      sdkRoot: sdkRoot,
      imageSysdir: snapshot.imageSysdir.isNotEmpty
          ? snapshot.imageSysdir
          : (SystemImage.tryParsePackageId(packageId)?.relativeDirWindows ?? snapshot.imageSysdir),
      ramSize: ramSize,
      storageSize: storageSize,
      gpuMode: gpuMode,
      cpuCores: snapshot.cpuCores,
    );
  }

  Future<void> deleteAvd({
    required String sdkRoot,
    required String name,
    String? avdHome,
    String? avdManagerPath,
  }) async {
    final manager = (avdManagerPath ?? findAvdManagerPath(sdkRoot)).trim();
    if (manager.isEmpty) {
      throw AvdException(avdManagerMissingMessage(sdkRoot));
    }
    final result = await runner.run(
      manager,
      ['delete', 'avd', '-n', name],
      timeout: const Duration(seconds: 30),
      environment: {
        'ANDROID_SDK_ROOT': sdkRoot,
        'ANDROID_HOME': sdkRoot,
        if (avdHome != null && avdHome.trim().isNotEmpty) 'ANDROID_AVD_HOME': avdHome.trim(),
      },
      runInShell: Platform.isWindows && manager.toLowerCase().endsWith('.bat'),
    );
    if (result.exitCode != 0) {
      throw AvdException(
        'Gagal menghapus AVD "$name" (kode ${result.exitCode}).'
        '${_detail(result)}',
      );
    }
  }

  Future<String> _readLog(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return '';
      return await file.readAsString();
    } on FileSystemException {
      return '';
    }
  }

  String? _readIfExists(String path) {
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return file.readAsStringSync();
    } on FileSystemException {
      return null;
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
