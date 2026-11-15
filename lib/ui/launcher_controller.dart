import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/adb_device.dart';
import '../services/avd_config.dart';
import '../services/avd_service.dart';
import '../services/launch_watch.dart';
import '../services/emulator_diagnostics.dart';
import '../services/sdk_installer.dart';
import '../services/sdk_locator.dart';
import '../services/settings_store.dart';

class LauncherController extends ChangeNotifier {
  LauncherController({
    required this.settingsStore,
    required this.service,
    SdkLocator? locator,
    SdkInstaller? sdkInstaller,
    Map<String, String>? environment,
  })  : locator = locator ??
            SdkLocator(
              pathExists: (path) => File(path).existsSync(),
              environment: environment ?? Platform.environment,
              localAppData: (environment ?? Platform.environment)['LOCALAPPDATA'],
            ),
        sdkInstaller = sdkInstaller ?? SdkInstaller();

  final SettingsStore settingsStore;
  final AvdService service;
  final SdkLocator locator;
  final SdkInstaller sdkInstaller;

  AppSettings settings = const AppSettings();
  SdkLocation sdk = const SdkLocation(root: '', source: '');
  List<String> avds = const [];
  Map<String, AvdSummary> avdSummaries = const {};
  List<String> orphanedAvds = const [];
  List<AdbDevice> devices = const [];
  String? selectedAvd;
  bool coldBoot = false;
  bool wipeData = false;
  bool noAudio = false;
  String gpuLaunchMode = 'default';
  bool loading = false;
  bool starting = false;
  bool stopping = false;
  bool editing = false;
  bool creating = false;
  bool deleting = false;
  bool installingApk = false;
  bool installingSdk = false;
  bool initialized = false;
  String? lastEmulatorLogPath;
  int? lastEmulatorPid;
  String emulatorLogContent = '';
  final List<String> activityLogs = <String>[];
  String? _statusMessage;
  String? _errorMessage;
  Timer? _refreshTimer;

  String? get statusMessage => _statusMessage;
  set statusMessage(String? value) {
    final changed = value != _statusMessage;
    _statusMessage = value;
    if (changed && value != null && value.trim().isNotEmpty) {
      addActivityLog('[INFO] $value');
    }
  }

  String? get errorMessage => _errorMessage;
  set errorMessage(String? value) {
    final changed = value != _errorMessage;
    _errorMessage = value;
    if (changed && value != null && value.trim().isNotEmpty) {
      addActivityLog('[ERROR] $value');
    }
  }

  void addActivityLog(String entry) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    activityLogs.add('[$hh:$mm:$ss] $entry');
    if (activityLogs.length > 500) {
      activityLogs.removeRange(0, activityLogs.length - 500);
    }
  }

  void clearActivityLogs() {
    activityLogs.clear();
    notifyListeners();
  }

  String? get activeEmulatorLogPath {
    if (lastEmulatorLogPath != null && lastEmulatorLogPath!.isNotEmpty) {
      return lastEmulatorLogPath;
    }
    final name = selectedAvd;
    final dir = _logDirectory;
    if (name != null && name.isNotEmpty && dir != null && dir.isNotEmpty) {
      final candidate = p.join(dir, 'emulator-${sanitizeForFileName(name)}.log');
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }
    return null;
  }

  Future<void> refreshEmulatorLogContent({bool notify = true}) async {
    final path = activeEmulatorLogPath;
    if (path == null || path.isEmpty) {
      if (emulatorLogContent.isNotEmpty) {
        emulatorLogContent = '';
        if (notify) notifyListeners();
      }
      return;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (emulatorLogContent.isNotEmpty) {
          emulatorLogContent = '';
          if (notify) notifyListeners();
        }
        return;
      }
      final text = await file.readAsString();
      if (text != emulatorLogContent) {
        emulatorLogContent = text;
        if (notify) notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> clearEmulatorLog() async {
    final path = activeEmulatorLogPath;
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.writeAsString('');
      }
      emulatorLogContent = '';
      notifyListeners();
    } catch (_) {}
  }

  String? get sdkOverrideText => settings.trimmedOverride;

  String? get settingsFilePath => settingsStore.filePath;

  String? get settingsLocationLabel => settingsStore.locationLabel;

  bool get canStart =>
      sdk.isUsable &&
      selectedAvd != null &&
      selectedAvd!.isNotEmpty &&
      !starting &&
      !loading &&
      !deleting;

  bool get canEditSelected =>
      sdk.isUsable &&
      selectedAvd != null &&
      selectedAvd!.isNotEmpty &&
      !starting &&
      !loading &&
      !editing &&
      !creating &&
      !deleting;

  bool get canDeleteSelected =>
      sdk.isUsable &&
      selectedAvd != null &&
      selectedAvd!.isNotEmpty &&
      !starting &&
      !loading &&
      !editing &&
      !creating &&
      !deleting;

  bool get canCreateAvd =>
      sdk.isUsable && !loading && !creating && !editing && !deleting;

  Future<void> initialize() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      settings = await settingsStore.load();
      coldBoot = settings.coldBoot;
      noAudio = settings.noAudio;
      gpuLaunchMode = settings.gpuLaunchMode;
      selectedAvd = settings.trimmedLastAvd;
    } catch (error) {
      errorMessage = 'Gagal membaca pengaturan: $error';
    }
    _resolveSdk();
    initialized = true;
    if (sdk.isUsable) {
      await refresh(showLoading: false);
    } else {
      loading = false;
      notifyListeners();
    }
    _startPeriodicRefresh();
  }

  void _resolveSdk() {
    sdk = locator.resolve(override: settings.trimmedOverride);
    if (!sdk.isUsable) {
      avds = const [];
      avdSummaries = const {};
      orphanedAvds = const [];
      devices = const [];
      if (sdk.issues.isNotEmpty) {
        errorMessage = sdk.errorMessage;
      }
    }
  }

  Future<void> refresh({
    bool showLoading = true,
    bool preserveStatus = false,
    bool includeAvdList = true,
  }) async {
    if (showLoading) {
      loading = true;
      if (!preserveStatus) {
        errorMessage = null;
        statusMessage = null;
      }
      notifyListeners();
    }
    _resolveSdk();
    if (!sdk.isUsable) {
      loading = false;
      notifyListeners();
      return;
    }

    String? avdError;
    String? adbError;
    var nextAvds = avds;
    var nextDevices = <AdbDevice>[];

    if (includeAvdList || avds.isEmpty) {
      try {
        nextAvds = await service.listAvds(sdk.emulatorPath!);
      } catch (error) {
        avdError = error.toString();
      }
    }
    try {
      nextDevices = await service.listDevices(sdk.adbPath!);
    } catch (error) {
      adbError = error.toString();
    }

    avds = nextAvds;
    devices = nextDevices;
    if (includeAvdList || avdSummaries.isEmpty) {
      _refreshSummariesAndOrphans();
    }

    if (selectedAvd != null && !avds.contains(selectedAvd)) {
      selectedAvd = null;
    }
    if (selectedAvd == null && avds.isNotEmpty) {
      final preferred = settings.trimmedLastAvd;
      if (preferred != null && avds.contains(preferred)) {
        selectedAvd = preferred;
      } else if (avds.length == 1) {
        selectedAvd = avds.first;
      }
    }

    final parts = <String>[
      ?avdError,
      ?adbError,
    ];
    if (!preserveStatus) {
      errorMessage = parts.isEmpty ? null : parts.join('\n');
    }
    await refreshEmulatorLogContent(notify: false);
    loading = false;
    notifyListeners();
  }

  void _refreshSummariesAndOrphans() {
    final home = _avdHome;
    if (home == null || home.isEmpty || sdk.root.isEmpty) {
      avdSummaries = const {};
      orphanedAvds = const [];
      return;
    }
    final nextSummaries = <String, AvdSummary>{};
    for (final name in avds) {
      final summary = service.summarizeAvd(
        avdName: name,
        avdHome: home,
        sdkRoot: sdk.root,
      );
      if (summary != null) {
        nextSummaries[name] = summary;
      }
    }
    avdSummaries = nextSummaries;
    orphanedAvds = service.findOrphanedAvdDirectories(
      avdHome: home,
      knownAvds: avds,
    );
  }

  void selectAvd(String? name) {
    selectedAvd = name;
    unawaited(refreshEmulatorLogContent(notify: false));
    notifyListeners();
    _savePreferencesQuietly();
  }

  void setColdBoot(bool value) {
    coldBoot = value;
    notifyListeners();
    _savePreferencesQuietly();
  }

  void setWipeData(bool value) {
    wipeData = value;
    notifyListeners();
  }

  void setNoAudio(bool value) {
    noAudio = value;
    notifyListeners();
    _savePreferencesQuietly();
  }

  void setGpuLaunchMode(String value) {
    gpuLaunchMode = value;
    notifyListeners();
    _savePreferencesQuietly();
  }

  void _savePreferencesQuietly() {
    settings = settings.copyWith(
      lastSelectedAvd: selectedAvd,
      clearLastSelectedAvd: selectedAvd == null || selectedAvd!.isEmpty,
      coldBoot: coldBoot,
      noAudio: noAudio,
      gpuLaunchMode: gpuLaunchMode,
    );
    unawaited(
      settingsStore.save(settings).catchError((_) {}),
    );
  }

  Future<void> setManualSdkPath(String? path) async {
    settings = settings.copyWith(sdkPathOverride: path, clearOverride: path == null || path.trim().isEmpty);
    try {
      await settingsStore.save(settings);
    } catch (error) {
      errorMessage = 'Gagal menyimpan pengaturan: $error';
      notifyListeners();
      return;
    }
    errorMessage = null;
    final savedPath = settingsStore.filePath;
    if (settings.trimmedOverride == null) {
      statusMessage = savedPath == null
          ? 'Menggunakan deteksi otomatis lokasi SDK.'
          : 'Deteksi otomatis. Pengaturan disimpan di: $savedPath';
    } else {
      statusMessage = savedPath == null
          ? 'Lokasi SDK disimpan.'
          : 'Lokasi SDK disimpan di: $savedPath';
    }
    await refresh();
  }

  Future<void> useAutomaticSdk() async {
    await setManualSdkPath(null);
  }

  String get defaultSdkInstallRoot {
    if (sdk.root.isNotEmpty) return sdk.root;
    final manual = sdkOverrideText;
    if (manual != null && manual.isNotEmpty) return manual;
    return SdkInstaller.defaultTargetRoot(Platform.environment);
  }

  Future<void> downloadAndInstallSdk({
    required SdkSetupConfig config,
    required void Function(String message) onProgress,
  }) async {
    installingSdk = true;
    errorMessage = null;
    statusMessage = 'Mengunduh dan memasang Android SDK…';
    notifyListeners();
    try {
      await sdkInstaller.installSdk(
        config: config,
        onProgress: (msg) {
          statusMessage = msg;
          onProgress(msg);
          notifyListeners();
        },
      );
      await setManualSdkPath(config.targetRoot.trim());
      statusMessage =
          'Android SDK beserta komponennya berhasil dipasang di ${config.targetRoot.trim()}.';
      notifyListeners();
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
      rethrow;
    } finally {
      installingSdk = false;
      notifyListeners();
    }
  }


  bool get canKillHungProcesses =>
      sdk.isUsable &&
      selectedAvd != null &&
      selectedAvd!.isNotEmpty &&
      !starting &&
      !loading &&
      !stopping &&
      !editing &&
      !creating &&
      !deleting;

  bool hasIncompleteQuickbootForSelected() {
    final name = selectedAvd;
    final home = _avdHome;
    if (name == null || name.isEmpty || home == null || home.isEmpty) {
      return false;
    }
    try {
      return service.hasIncompleteQuickbootSnapshot(avdName: name, avdHome: home);
    } catch (_) {
      return false;
    }
  }

  Future<void> killHungProcessesForSelected() async {
    final name = selectedAvd;
    if (name == null || name.isEmpty) {
      errorMessage = 'Pilih satu virtual device terlebih dahulu.';
      notifyListeners();
      return;
    }
    stopping = true;
    errorMessage = null;
    statusMessage = 'Menghentikan proses macet untuk $name…';
    notifyListeners();
    try {
      final killed = await service.killHungProcessesForAvd(name);
      await Future<void>.delayed(const Duration(seconds: 1));
      String? backup;
      final home = _avdHome;
      if (home != null && home.isNotEmpty) {
        final directory = resolveAvdDirectory(
          avdName: name,
          avdHome: home,
          readFileIfExists: (path) {
            final file = File(path);
            return file.existsSync() ? file.readAsStringSync() : null;
          },
        );
        backup = service.backupAndCleanupStaleLocks(directory);
      }
      if (killed.isEmpty) {
        statusMessage = 'Tidak ada proses macet untuk "$name".';
      } else {
        statusMessage =
            'Proses macet dihentikan (PID ${killed.join(', ')}).'
            '${backup == null ? '' : ' Cadangan lock: $backup'} '
            'Jika Mulai masih macet, aktifkan Boot dingin. Snapshot tidak dihapus.';
      }
      await refresh(showLoading: false, preserveStatus: true, includeAvdList: false);
    } catch (error) {
      errorMessage = 'Gagal menghentikan proses macet: $error';
      statusMessage = null;
    } finally {
      stopping = false;
      notifyListeners();
    }
  }

  Future<void> startSelected({bool? coldBootOverride}) async {
    if (!canStart) {
      if (!sdk.isUsable) {
        errorMessage = sdk.errorMessage.isNotEmpty
            ? sdk.errorMessage
            : 'Android SDK atau emulator.exe tidak ditemukan.';
      } else if (selectedAvd == null) {
        errorMessage = 'Pilih satu virtual device terlebih dahulu.';
      }
      notifyListeners();
      return;
    }

    starting = true;
    errorMessage = null;
    lastEmulatorLogPath = null;
    lastEmulatorPid = null;
    final targetAvd = selectedAvd!;
    if (isAvdRunningByName(targetAvd, checkDiskLock: false)) {
      errorMessage =
          'AVD "$targetAvd" sudah berjalan di ADB. Hentikan terlebih dahulu sebelum menyalakan ulang.';
      starting = false;
      notifyListeners();
      return;
    }
    try {
      final hung = await service.listHungProcessesForAvd(targetAvd);
      if (hung.isNotEmpty) {
        errorMessage =
            'Ada ${hung.length} proses emulator macet untuk "$targetAvd" (tanpa jendela dan tanpa port adb). '
            'Tekan Hentikan proses macet, lalu coba Mulai lagi. '
            'Jika masih gagal, aktifkan Boot dingin — snapshot quickboot mungkin rusak (snapshot tidak dihapus).';
        starting = false;
        notifyListeners();
        return;
      }
    } catch (_) {
      // If process listing fails, continue and let startAvd try.
    }
    final previousEmulatorSerials = devices
        .where((device) => device.isEmulator)
        .map((device) => device.serial)
        .toSet();
    statusMessage = 'Menyalakan $targetAvd…';
    notifyListeners();
    try {
      final launch = await service.startAvd(
        emulatorPath: sdk.emulatorPath!,
        adbPath: sdk.adbPath ?? '',
        sdkRoot: sdk.root,
        avdName: targetAvd,
        avdHome: _avdHome,
        logDirectory: _logDirectory,
        options: LaunchOptions(
          coldBoot: coldBootOverride ?? coldBoot,
          wipeData: wipeData,
          noAudio: noAudio,
          gpuMode: gpuLaunchMode,
        ),
      );
      lastEmulatorPid = launch.pid;
      lastEmulatorLogPath = launch.logPath;
      await refreshEmulatorLogContent(notify: false);
      statusMessage = 'Menyalakan $targetAvd… (pid ${launch.pid})';
      notifyListeners();
      await _watchLaunch(
        launch,
        targetAvd: targetAvd,
        previousSerials: previousEmulatorSerials,
      );
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
      await refreshEmulatorLogContent(notify: false);
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  AdbDevice? _findTargetEmulator(
    String targetAvd,
    Set<String> previousSerials,
  ) {
    final emulators = devices.where((device) => device.isEmulator).toList();
    if (emulators.isEmpty) return null;
    final targetLower = targetAvd.toLowerCase();
    for (final emu in emulators) {
      if (emu.avdName != null && emu.avdName!.toLowerCase() == targetLower) {
        return emu;
      }
    }
    for (final emu in emulators) {
      if (!previousSerials.contains(emu.serial)) {
        return emu;
      }
    }
    if (previousSerials.isEmpty) {
      return emulators.first;
    }
    return null;
  }

  Future<void> _recoverAdbOnce(String reason) async {
    if (!sdk.hasAdb) return;
    statusMessage = reason;
    notifyListeners();
    try {
      await service.recoverAdbConnection(sdk.adbPath!);
    } catch (_) {}
  }

  Future<void> _watchLaunch(
    EmulatorLaunch launch, {
    required String targetAvd,
    required Set<String> previousSerials,
  }) async {
    const interval = Duration(seconds: 3);
    const limit = Duration(minutes: 2);
    final startedAt = DateTime.now();
    final deadline = startedAt.add(limit);
    var adbRetried = false;
    while (DateTime.now().isBefore(deadline)) {
      await refresh(
        showLoading: false,
        preserveStatus: true,
        includeAvdList: false,
      );
      final device = _findTargetEmulator(targetAvd, previousSerials);
      if (device != null) {
        var booted = false;
        try {
          booted = await service.isBootCompleted(
            adbPath: sdk.adbPath!,
            serial: device.serial,
          );
        } catch (_) {}
        if (booted) {
          statusMessage = '${device.displayTitle} online, sudah boot.';
          notifyListeners();
          return;
        }
        statusMessage = '${device.displayTitle} online, masih booting…';
        notifyListeners();
      } else {
        final alive = await service.isProcessRunning(launch.pid);
        if (!alive) {
          errorMessage =
              'Emulator berhenti sebelum tampil di adb.\nLog: ${launch.logPath}';
          statusMessage = null;
          notifyListeners();
          return;
        }
        final elapsed = DateTime.now().difference(startedAt);
        if (!adbRetried && elapsed >= const Duration(seconds: 15) && sdk.hasAdb) {
          adbRetried = true;
          await _recoverAdbOnce('Menyalakan $targetAvd… menyalakan ulang server ADB');
          continue;
        }
        statusMessage = 'Menyalakan $targetAvd… menunggu adb';
        notifyListeners();
      }
      await Future<void>.delayed(interval);
    }
    await refresh(
      showLoading: false,
      preserveStatus: true,
      includeAvdList: false,
    );
    var matched = _findTargetEmulator(targetAvd, previousSerials);
    if (matched == null && sdk.hasAdb) {
      if (!adbRetried) {
        adbRetried = true;
        await _recoverAdbOnce('Menyalakan ulang server ADB, lalu memeriksa emulator…');
      }
      await refresh(
        showLoading: false,
        preserveStatus: true,
        includeAvdList: false,
      );
      matched = _findTargetEmulator(targetAvd, previousSerials);
    }
    if (matched != null) {
      statusMessage =
          '${matched.displayTitle} terdeteksi di adb, tetapi boot belum selesai dalam 2 menit. Log: ${launch.logPath}';
      errorMessage = null;
      notifyListeners();
      return;
    }
    final alive = await service.isProcessRunning(launch.pid);
    var windowVisible = false;
    var adbPortOpen = false;
    try {
      windowVisible = await service.processTreeHasVisibleWindow(launch.pid);
    } catch (_) {}
    try {
      adbPortOpen = await service.isEmulatorAdbPortOpen();
    } catch (_) {}
    final assessment = assessAdbWatchTimeout(
      processAlive: alive,
      windowVisible: windowVisible,
      adbHasEmulator: false,
      adbPortOpen: adbPortOpen,
      logPath: launch.logPath,
    );
    errorMessage = assessment.errorMessage;
    statusMessage = assessment.statusMessage;
    notifyListeners();
  }

  String? get avdHome => _avdHome;

  String? get _avdHome {
    for (final entry in Platform.environment.entries) {
      if (entry.key.toUpperCase() == 'ANDROID_AVD_HOME') {
        final val = entry.value.trim();
        if (val.isNotEmpty) return val;
      }
    }
    final profile = Platform.environment['USERPROFILE']?.trim();
    if (profile != null && profile.isNotEmpty) {
      return p.join(profile, '.android', 'avd');
    }
    return null;
  }

  String? get _logDirectory {
    final path = settingsStore.filePath;
    if (path != null && path.isNotEmpty) {
      return p.dirname(path);
    }
    return null;
  }

  bool isAvdRunningByName(String name, {bool checkDiskLock = false}) {
    final lower = name.toLowerCase();
    for (final device in devices) {
      if (device.isEmulator &&
          device.avdName != null &&
          device.avdName!.toLowerCase() == lower) {
        return true;
      }
    }
    if (!checkDiskLock) return false;
    final home = _avdHome;
    if (home == null || home.isEmpty) return false;
    return service.isAvdRunning(avdName: name, avdHome: home);
  }

  bool isSelectedAvdRunning({bool checkDiskLock = true}) {
    final name = selectedAvd;
    if (name == null || name.isEmpty) return false;
    return isAvdRunningByName(name, checkDiskLock: checkDiskLock);
  }

  AvdConfigSnapshot loadSelectedConfig() {
    final name = selectedAvd;
    final home = _avdHome;
    if (name == null || name.isEmpty) {
      throw AvdException('Pilih satu virtual device terlebih dahulu.');
    }
    if (home == null || home.isEmpty) {
      throw AvdException('Lokasi folder AVD (ANDROID_AVD_HOME) tidak diketahui.');
    }
    return service.loadAvdConfig(
      avdName: name,
      avdHome: home,
      sdkRoot: sdk.root,
    );
  }

  Future<String> saveSelectedConfig({
    required String imageSysdir,
    required String ramSize,
    required String storageSize,
    required String gpuMode,
    required String cpuCores,
  }) async {
    editing = true;
    errorMessage = null;
    notifyListeners();
    try {
      final snapshot = loadSelectedConfig();
      final backup = service.saveAvdConfig(
        snapshot: snapshot,
        sdkRoot: sdk.root,
        imageSysdir: imageSysdir,
        ramSize: ramSize,
        storageSize: storageSize,
        gpuMode: gpuMode,
        cpuCores: cpuCores,
      );
      _refreshSummariesAndOrphans();
      statusMessage = 'Konfigurasi "${snapshot.avdName}" disimpan. Cadangan: $backup';
      return backup;
    } catch (error) {
      errorMessage = error.toString();
      rethrow;
    } finally {
      editing = false;
      notifyListeners();
    }
  }

  Future<List<SystemImage>> installedSystemImages() async {
    if (sdk.root.isEmpty) return const [];
    return service.installedSystemImages(sdk.root);
  }

  Future<List<String>> listDeviceProfiles() async {
    if (sdk.root.isEmpty) return List<String>.from(kFallbackDeviceProfiles);
    return service.listDeviceProfiles(sdkRoot: sdk.root);
  }

  String? get avdManagerPath =>
      sdk.root.isEmpty ? null : findAvdManagerPath(sdk.root);

  Future<void> createAvd({
    required String name,
    required String packageId,
    required String deviceId,
    required String ramSize,
    required String storageSize,
    required String gpuMode,
  }) async {
    creating = true;
    errorMessage = null;
    statusMessage = 'Membuat AVD $name…';
    notifyListeners();
    try {
      await service.createAvd(
        sdkRoot: sdk.root,
        name: name,
        packageId: packageId,
        deviceId: deviceId,
        ramSize: ramSize,
        storageSize: storageSize,
        gpuMode: gpuMode,
        avdHome: _avdHome,
        existingNames: avds,
      );
      selectedAvd = name.trim();
      _savePreferencesQuietly();
      statusMessage = 'AVD "$name" dibuat.';
      await refresh(showLoading: false, preserveStatus: true);
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
      rethrow;
    } finally {
      creating = false;
      notifyListeners();
    }
  }

  Future<void> deleteSelectedAvd() async {
    final name = selectedAvd;
    if (name == null || name.isEmpty) {
      errorMessage = 'Pilih satu virtual device terlebih dahulu.';
      notifyListeners();
      return;
    }
    if (isAvdRunningByName(name, checkDiskLock: true)) {
      errorMessage = 'AVD "$name" sedang berjalan. Hentikan emulator dulu sebelum menghapus.';
      notifyListeners();
      return;
    }
    deleting = true;
    errorMessage = null;
    statusMessage = 'Menghapus AVD "$name"…';
    notifyListeners();
    try {
      await service.deleteAvd(
        sdkRoot: sdk.root,
        name: name,
        avdHome: _avdHome,
      );
      selectedAvd = null;
      _savePreferencesQuietly();
      statusMessage = 'AVD "$name" dihapus.';
      await refresh(showLoading: false, preserveStatus: true);
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
    } finally {
      deleting = false;
      notifyListeners();
    }
  }

  Future<void> deleteAllOrphanedAvds() async {
    final home = _avdHome;
    if (home == null || home.isEmpty || orphanedAvds.isEmpty) return;
    deleting = true;
    errorMessage = null;
    final targets = List<String>.from(orphanedAvds);
    statusMessage = 'Membersihkan folder .avd yatim (${targets.join(', ')})…';
    notifyListeners();
    try {
      for (final name in targets) {
        await service.deleteOrphanedAvdDirectory(
          avdHome: home,
          baseName: name,
        );
      }
      statusMessage = 'Folder .avd yatim berhasil dibersihkan.';
      await refresh(showLoading: false, preserveStatus: true);
    } catch (error) {
      errorMessage = 'Gagal membersihkan folder .avd yatim: $error';
      statusMessage = null;
    } finally {
      deleting = false;
      notifyListeners();
    }
  }

  Future<void> installApkOnDevice(AdbDevice device, String apkPath) async {
    if (!sdk.hasAdb) {
      errorMessage = 'adb.exe tidak ditemukan.';
      notifyListeners();
      return;
    }
    installingApk = true;
    errorMessage = null;
    statusMessage = 'Memasang ${p.basename(apkPath)} ke ${device.displayTitle}…';
    notifyListeners();
    try {
      await service.installApk(
        adbPath: sdk.adbPath!,
        serial: device.serial,
        apkPath: apkPath,
      );
      statusMessage = 'APK "${p.basename(apkPath)}" terpasang di ${device.displayTitle}.';
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
    } finally {
      installingApk = false;
      notifyListeners();
    }
  }

  Future<void> restartAdb() async {
    if (!sdk.hasAdb) {
      errorMessage = 'adb.exe tidak ditemukan.';
      notifyListeners();
      return;
    }
    loading = true;
    errorMessage = null;
    statusMessage = 'Menyalakan ulang server ADB…';
    notifyListeners();
    try {
      await service.restartAdbServer(sdk.adbPath!);
      statusMessage = 'Server ADB dinyalakan ulang.';
      await refresh(showLoading: false, preserveStatus: true, includeAvdList: false);
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> openSelectedAvdFolder() async {
    final name = selectedAvd;
    final home = _avdHome;
    if (name == null || home == null || home.isEmpty) return;
    final dir = resolveAvdDirectory(
      avdName: name,
      avdHome: home,
      readFileIfExists: (path) {
        final f = File(path);
        return f.existsSync() ? f.readAsStringSync() : null;
      },
    );
    final target = Directory(dir).existsSync() ? dir : home;
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [target]);
    }
  }

  Future<void> openLastEmulatorLog() async {
    final logPath = activeEmulatorLogPath;
    if (logPath == null || logPath.isEmpty || !File(logPath).existsSync()) {
      return;
    }
    if (Platform.isWindows) {
      await Process.run('notepad.exe', [logPath]);
    }
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (loading ||
          starting ||
          stopping ||
          editing ||
          creating ||
          deleting ||
          installingApk ||
          installingSdk) {
        return;
      }
      unawaited(
        refresh(
          showLoading: false,
          preserveStatus: true,
          includeAvdList: false,
        ),
      );
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> stopDevice(AdbDevice device) async {
    if (!sdk.hasAdb) {
      errorMessage = 'adb.exe tidak ditemukan, sehingga emulator tidak dapat dihentikan dari sini.';
      notifyListeners();
      return;
    }
    stopping = true;
    errorMessage = null;
    statusMessage = 'Menghentikan ${device.displayTitle}…';
    notifyListeners();
    try {
      await service.stopEmulator(adbPath: sdk.adbPath!, serial: device.serial);
      statusMessage = '${device.displayTitle} dihentikan.';
      await Future<void>.delayed(const Duration(seconds: 1));
      await refresh(showLoading: false, preserveStatus: true, includeAvdList: false);
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
    } finally {
      stopping = false;
      notifyListeners();
    }
  }
}
