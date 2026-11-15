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

class AvdSummary {
  const AvdSummary({
    required this.name,
    this.api = '',
    this.tag = '',
    this.abi = '',
    this.ramSize = '',
    this.storageSize = '',
    this.gpuMode = '',
    this.imageMissing = false,
  });

  final String name;
  final String api;
  final String tag;
  final String abi;
  final String ramSize;
  final String storageSize;
  final String gpuMode;
  final bool imageMissing;

  String get subtitle {
    final parts = <String>[
      if (api.isNotEmpty) api,
      if (tag.isNotEmpty) tag,
      if (abi.isNotEmpty) abi,
      if (ramSize.isNotEmpty) 'RAM $ramSize MB',
      if (storageSize.isNotEmpty) 'Storage $storageSize',
    ];
    return parts.join(' · ');
  }
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

  Future<List<AdbDevice>> listDevices(
    String adbPath, {
    bool resolveAvdNames = true,
  }) async {
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
    if (!resolveAvdNames) {
      return devices;
    }
    final resolved = <AdbDevice>[];
    for (final device in devices) {
      if (device.isEmulator &&
          (device.state == 'device' || device.state == 'offline')) {
        final name = await resolveEmulatorAvdName(
          adbPath: adbPath,
          serial: device.serial,
        );
        resolved.add(device.copyWith(avdName: name));
      } else {
        resolved.add(device);
      }
    }
    return resolved;
  }

  Future<String?> resolveEmulatorAvdName({
    required String adbPath,
    required String serial,
  }) async {
    try {
      final emuResult = await runner.run(
        adbPath,
        ['-s', serial, 'emu', 'avd', 'name'],
        timeout: const Duration(seconds: 5),
      );
      if (emuResult.exitCode == 0) {
        final parsed = parseEmulatorAvdName(emuResult.stdout);
        if (parsed != null && parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}

    try {
      final propResult = await runner.run(
        adbPath,
        ['-s', serial, 'shell', 'getprop', 'ro.boot.qemu.avd_name'],
        timeout: const Duration(seconds: 5),
      );
      if (propResult.exitCode == 0) {
        final parsed = parseEmulatorAvdName(propResult.stdout);
        if (parsed != null && parsed.isNotEmpty) return parsed;
      }
    } catch (_) {}

    return null;
  }

  AvdSummary? summarizeAvd({
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
    if (content == null) return null;
    final document = IniDocument.parse(content);
    final sysdir = document.get('image.sysdir.1') ?? '';
    final image = SystemImage.tryParseSysdir(sysdir);
    final missing = sysdir.isNotEmpty &&
        !Directory(p.normalize(p.join(sdkRoot, sysdir))).existsSync();
    return AvdSummary(
      name: avdName,
      api: image?.api ?? '',
      tag: image?.tag ?? '',
      abi: image?.abi ?? '',
      ramSize: document.get('hw.ramSize') ?? '',
      storageSize: document.get('disk.dataPartition.size') ?? '',
      gpuMode: document.get('hw.gpu.mode') ?? '',
      imageMissing: missing,
    );
  }

  List<String> findOrphanedAvdDirectories({
    required String avdHome,
    required Iterable<String> knownAvds,
  }) {
    final homeDir = Directory(avdHome);
    if (!homeDir.existsSync()) return const [];
    final knownLower = knownAvds.map((e) => e.toLowerCase()).toSet();
    final orphaned = <String>[];
    try {
      for (final entity in homeDir.listSync()) {
        if (entity is Directory && entity.path.toLowerCase().endsWith('.avd')) {
          final base = p.basenameWithoutExtension(entity.path);
          final iniFile = File(p.join(avdHome, '$base.ini'));
          if (!iniFile.existsSync() && !knownLower.contains(base.toLowerCase())) {
            orphaned.add(base);
          }
        }
      }
    } on FileSystemException {
      return const [];
    }
    orphaned.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return orphaned;
  }

  Future<void> installApk({
    required String adbPath,
    required String serial,
    required String apkPath,
  }) async {
    final result = await runner.run(
      adbPath,
      ['-s', serial, 'install', '-r', apkPath],
      timeout: const Duration(minutes: 2),
    );
    if (result.exitCode != 0) {
      throw AvdException(
        'Gagal memasang APK pada $serial (kode ${result.exitCode}).'
        '${_detail(result)}',
      );
    }
  }

  Future<void> restartAdbServer(String adbPath) async {
    await runner.run(
      adbPath,
      const ['kill-server'],
      timeout: const Duration(seconds: 15),
    );
    final start = await runner.run(
      adbPath,
      const ['start-server'],
      timeout: const Duration(seconds: 20),
    );
    if (start.exitCode != 0) {
      throw AvdException(
        'Gagal menyalakan ulang server ADB (kode ${start.exitCode}).'
        '${_detail(start)}',
      );
    }
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
    required String adbPath,
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
      if (isAvdRunning(avdName: name, avdHome: resolvedAvdHome)) {
        throw AvdException(
          'AVD "$name" sedang berjalan atau terkunci oleh proses emulator lain. '
          'Hentikan terlebih dahulu sebelum menyalakan ulang.',
        );
      }
      cleanupStaleAvdFiles(
        avdName: name,
        avdHome: resolvedAvdHome,
      );
    }

    if (adbPath.trim().isNotEmpty) {
      try {
        await runner.run(
          adbPath,
          const ['start-server'],
          timeout: const Duration(seconds: 15),
        );
      } catch (_) {}
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

  /// Cleans up stale `.lock`, `bootcompleted.ini`, and `snapshot.trace` files
  /// or directories in the AVD directory if no running emulator holds the lock.
  void cleanupStaleAvdFiles({
    required String avdName,
    required String avdHome,
  }) {
    final directory = resolveAvdDirectory(
      avdName: avdName,
      avdHome: avdHome,
      readFileIfExists: _readIfExists,
    );
    if (isAvdLockHeld(directory)) {
      return;
    }
    const staleItems = [
      'hardware-qemu.ini.lock',
      'multiinstance.lock',
      'userdata-qemu.img.lock',
      'bootcompleted.ini',
      'snapshot.trace',
    ];
    for (final name in staleItems) {
      final itemPath = p.join(directory, name);
      final type = FileSystemEntity.typeSync(itemPath);
      if (type == FileSystemEntityType.file) {
        try {
          File(itemPath).deleteSync();
        } on FileSystemException {
          // ignore if locked or inaccessible
        }
      } else if (type == FileSystemEntityType.directory) {
        try {
          Directory(itemPath).deleteSync(recursive: true);
        } on FileSystemException {
          // ignore if locked or inaccessible
        }
      }
    }
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
    final trimmedName = name.trim();
    final trimmedHome = (avdHome ?? '').trim();
    if (trimmedHome.isNotEmpty) {
      if (isAvdRunning(avdName: trimmedName, avdHome: trimmedHome)) {
        throw AvdException(
          'AVD "$trimmedName" sedang berjalan. Hentikan emulator dulu sebelum menghapus.',
        );
      }
      cleanupStaleAvdFiles(avdName: trimmedName, avdHome: trimmedHome);
    }

    final manager = (avdManagerPath ?? findAvdManagerPath(sdkRoot)).trim();
    String? managerError;
    if (manager.isNotEmpty) {
      final result = await runner.run(
        manager,
        ['delete', 'avd', '-n', trimmedName],
        timeout: const Duration(seconds: 30),
        environment: {
          'ANDROID_SDK_ROOT': sdkRoot,
          'ANDROID_HOME': sdkRoot,
          if (trimmedHome.isNotEmpty) 'ANDROID_AVD_HOME': trimmedHome,
        },
        runInShell: Platform.isWindows && manager.toLowerCase().endsWith('.bat'),
      );
      if (result.exitCode != 0) {
        managerError =
            'Gagal menghapus AVD "$trimmedName" lewat avdmanager (kode ${result.exitCode}).'
            '${_detail(result)}';
      }
    }

    // Also remove the .ini file and .avd directory directly so broken/incomplete
    // AVDs that avdmanager does not recognize are still cleanly removed.
    if (trimmedHome.isNotEmpty) {
      final targetAvdDir = resolveAvdDirectory(
        avdName: trimmedName,
        avdHome: trimmedHome,
        readFileIfExists: _readIfExists,
      );
      final iniFile = File(p.join(trimmedHome, '$trimmedName.ini'));
      final avdDir = Directory(targetAvdDir);
      var removedDirectly = false;
      try {
        if (await iniFile.exists()) {
          await _forceDeleteFile(iniFile);
          removedDirectly = true;
        }
        if (await avdDir.exists()) {
          await _forceDeleteDirectory(avdDir);
          removedDirectly = true;
        }
      } on FileSystemException catch (error) {
        throw AvdException(
          'Gagal menghapus berkas AVD "$trimmedName":\n${error.message}',
        );
      }
      if (removedDirectly) {
        return;
      }
    }

    if (manager.isEmpty) {
      throw AvdException(avdManagerMissingMessage(sdkRoot));
    }
    if (managerError != null) {
      throw AvdException(managerError);
    }
  }

  Future<void> deleteOrphanedAvdDirectory({
    required String avdHome,
    required String baseName,
  }) async {
    final trimmedHome = avdHome.trim();
    final trimmedName = baseName.trim();
    if (trimmedHome.isEmpty || trimmedName.isEmpty) return;
    final dir = Directory(p.join(trimmedHome, '$trimmedName.avd'));
    if (await dir.exists()) {
      await _forceDeleteDirectory(dir);
    }
  }

  Future<void> _forceDeleteFile(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      if (Platform.isWindows) {
        await Process.run('attrib', ['-R', '-S', '-H', file.path]);
        await file.delete();
      } else {
        rethrow;
      }
    }
  }

  Future<void> _forceDeleteDirectory(Directory dir) async {
    try {
      await dir.delete(recursive: true);
    } on FileSystemException {
      if (Platform.isWindows) {
        // Android Emulator creates ReadOnly files (e.g. data\misc\pstore\pstore.bin)
        // which cause Dart's Directory.delete(recursive: true) to fail with errno 5.
        await Process.run(
          'attrib',
          ['-R', '-S', '-H', p.join(dir.path, '*'), '/S', '/D'],
        );
        await Process.run('attrib', ['-R', '-S', '-H', dir.path]);
        await Process.run('cmd.exe', ['/c', 'rmdir', '/S', '/Q', dir.path]);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } else {
        rethrow;
      }
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
