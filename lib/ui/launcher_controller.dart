import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/adb_device.dart';
import '../services/avd_config.dart';
import '../services/avd_service.dart';
import '../services/sdk_locator.dart';
import '../services/settings_store.dart';

class LauncherController extends ChangeNotifier {
  LauncherController({
    required this.settingsStore,
    required this.service,
    SdkLocator? locator,
    Map<String, String>? environment,
  }) : locator = locator ??
            SdkLocator(
              pathExists: (path) => File(path).existsSync(),
              environment: environment ?? Platform.environment,
              localAppData: (environment ?? Platform.environment)['LOCALAPPDATA'],
            );

  final SettingsStore settingsStore;
  final AvdService service;
  final SdkLocator locator;

  AppSettings settings = const AppSettings();
  SdkLocation sdk = const SdkLocation(root: '', source: '');
  List<String> avds = const [];
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
  String? statusMessage;
  String? errorMessage;
  bool initialized = false;
  String? lastEmulatorLogPath;
  int? lastEmulatorPid;
  Timer? _refreshTimer;

  String? get sdkOverrideText => settings.trimmedOverride;

  String? get settingsFilePath => settingsStore.filePath;

  String? get settingsLocationLabel => settingsStore.locationLabel;

  bool get canStart =>
      sdk.isUsable &&
      selectedAvd != null &&
      selectedAvd!.isNotEmpty &&
      !starting &&
      !loading;

  bool get canEditSelected =>
      sdk.isUsable &&
      selectedAvd != null &&
      selectedAvd!.isNotEmpty &&
      !starting &&
      !loading &&
      !editing &&
      !creating;

  bool get canCreateAvd => sdk.isUsable && !loading && !creating && !editing;

  Future<void> initialize() async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      settings = await settingsStore.load();
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
      devices = const [];
      if (sdk.issues.isNotEmpty) {
        errorMessage = sdk.errorMessage;
      }
    }
  }

  Future<void> refresh({bool showLoading = true, bool preserveStatus = false}) async {
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
    var nextAvds = <String>[];
    var nextDevices = <AdbDevice>[];

    try {
      nextAvds = await service.listAvds(sdk.emulatorPath!);
    } catch (error) {
      avdError = error.toString();
    }
    try {
      nextDevices = await service.listDevices(sdk.adbPath!);
    } catch (error) {
      adbError = error.toString();
    }

    avds = nextAvds;
    devices = nextDevices;
    if (selectedAvd != null && !avds.contains(selectedAvd)) {
      selectedAvd = null;
    }
    if (selectedAvd == null && avds.length == 1) {
      selectedAvd = avds.first;
    }

    final parts = <String>[
      ?avdError,
      ?adbError,
    ];
    if (!preserveStatus) {
      errorMessage = parts.isEmpty ? null : parts.join('\n');
    }
    loading = false;
    notifyListeners();
  }

  void selectAvd(String? name) {
    selectedAvd = name;
    notifyListeners();
  }

  void setColdBoot(bool value) {
    coldBoot = value;
    notifyListeners();
  }

  void setWipeData(bool value) {
    wipeData = value;
    notifyListeners();
  }

  void setNoAudio(bool value) {
    noAudio = value;
    notifyListeners();
  }

  void setGpuLaunchMode(String value) {
    gpuLaunchMode = value;
    notifyListeners();
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

  Future<void> startSelected() async {
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
    statusMessage = 'Menyalakan ${selectedAvd!}…';
    notifyListeners();
    try {
      final launch = await service.startAvd(
        emulatorPath: sdk.emulatorPath!,
        sdkRoot: sdk.root,
        avdName: selectedAvd!,
        avdHome: _avdHome,
        logDirectory: _logDirectory,
        options: LaunchOptions(
          coldBoot: coldBoot,
          wipeData: wipeData,
          noAudio: noAudio,
          gpuMode: gpuLaunchMode,
        ),
      );
      lastEmulatorPid = launch.pid;
      lastEmulatorLogPath = launch.logPath;
      statusMessage = 'Menyalakan ${selectedAvd!}… (pid ${launch.pid})';
      notifyListeners();
      await _watchLaunch(launch);
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
    } finally {
      starting = false;
      notifyListeners();
    }
  }

  Future<void> _watchLaunch(EmulatorLaunch launch) async {
    const interval = Duration(seconds: 3);
    const limit = Duration(minutes: 2);
    final deadline = DateTime.now().add(limit);
    while (DateTime.now().isBefore(deadline)) {
      await refresh(showLoading: false, preserveStatus: true);
      final emulators = devices.where((device) => device.isEmulator).toList();
      if (emulators.isNotEmpty) {
        final device = emulators.first;
        var booted = false;
        try {
          booted = await service.isBootCompleted(
            adbPath: sdk.adbPath!,
            serial: device.serial,
          );
        } catch (_) {}
        if (booted) {
          statusMessage = '${device.serial} online, sudah boot.';
          notifyListeners();
          return;
        }
        statusMessage = '${device.serial} online, masih booting…';
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
        statusMessage = 'Menyalakan ${selectedAvd!}… menunggu adb';
        notifyListeners();
      }
      await Future<void>.delayed(interval);
    }
    await refresh(showLoading: false, preserveStatus: true);
    if (devices.any((device) => device.isEmulator)) {
      final device = devices.firstWhere((device) => device.isEmulator);
      statusMessage =
          '${device.serial} terdeteksi di adb, tetapi boot belum selesai dalam 2 menit. Log: ${launch.logPath}';
    } else {
      errorMessage =
          'Emulator belum tampil di adb setelah 2 menit.\nLog: ${launch.logPath}';
      statusMessage = null;
    }
    notifyListeners();
  }

  String? get avdHome => _avdHome;

  String? get _avdHome {
    final value = Platform.environment['ANDROID_AVD_HOME']?.trim();
    if (value != null && value.isNotEmpty) return value;
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

  bool isSelectedAvdRunning() {
    final name = selectedAvd;
    final home = _avdHome;
    if (name == null || home == null || home.isEmpty) return false;
    return service.isAvdRunning(avdName: name, avdHome: home);
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

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (loading || starting || stopping || editing || creating) return;
      unawaited(refresh(showLoading: false, preserveStatus: true));
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
    statusMessage = 'Menghentikan ${device.serial}…';
    notifyListeners();
    try {
      await service.stopEmulator(adbPath: sdk.adbPath!, serial: device.serial);
      statusMessage = '${device.serial} dihentikan.';
      await Future<void>.delayed(const Duration(seconds: 1));
      await refresh(showLoading: false);
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
    } finally {
      stopping = false;
      notifyListeners();
    }
  }
}
