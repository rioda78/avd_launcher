import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/adb_device.dart';
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
  bool loading = false;
  bool starting = false;
  bool stopping = false;
  String? statusMessage;
  String? errorMessage;
  bool initialized = false;

  String? get sdkOverrideText => settings.trimmedOverride;

  bool get canStart =>
      sdk.isUsable &&
      selectedAvd != null &&
      selectedAvd!.isNotEmpty &&
      !starting &&
      !loading;

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

  Future<void> refresh({bool showLoading = true}) async {
    if (showLoading) {
      loading = true;
      errorMessage = null;
      statusMessage = null;
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
    errorMessage = parts.isEmpty ? null : parts.join('\n');
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
    statusMessage = settings.trimmedOverride == null
        ? 'Menggunakan deteksi otomatis lokasi SDK.'
        : 'Lokasi SDK disimpan.';
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
    statusMessage = 'Menjalankan ${selectedAvd!}…';
    notifyListeners();
    try {
      await service.startAvd(
        emulatorPath: sdk.emulatorPath!,
        sdkRoot: sdk.root,
        avdName: selectedAvd!,
        options: LaunchOptions(
          coldBoot: coldBoot,
          wipeData: wipeData,
          noAudio: noAudio,
        ),
      );
      statusMessage =
          'Perintah mulai untuk "${selectedAvd!}" sudah dikirim. Emulator tetap berjalan jika jendela ini ditutup.';
      await Future<void>.delayed(const Duration(seconds: 3));
      await refresh(showLoading: false);
    } catch (error) {
      errorMessage = error.toString();
      statusMessage = null;
    } finally {
      starting = false;
      notifyListeners();
    }
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
