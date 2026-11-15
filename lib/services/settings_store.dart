import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'settings_path_resolver.dart';

class AppSettings {
  const AppSettings({
    this.sdkPathOverride,
    this.lastSelectedAvd,
    this.coldBoot = false,
    this.noAudio = false,
    this.gpuLaunchMode = 'default',
  });

  final String? sdkPathOverride;
  final String? lastSelectedAvd;
  final bool coldBoot;
  final bool noAudio;
  final String gpuLaunchMode;

  String? get trimmedOverride {
    final value = sdkPathOverride?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? get trimmedLastAvd {
    final value = lastSelectedAvd?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  AppSettings copyWith({
    String? sdkPathOverride,
    bool clearOverride = false,
    String? lastSelectedAvd,
    bool clearLastSelectedAvd = false,
    bool? coldBoot,
    bool? noAudio,
    String? gpuLaunchMode,
  }) {
    return AppSettings(
      sdkPathOverride:
          clearOverride ? null : (sdkPathOverride ?? this.sdkPathOverride),
      lastSelectedAvd: clearLastSelectedAvd
          ? null
          : (lastSelectedAvd ?? this.lastSelectedAvd),
      coldBoot: coldBoot ?? this.coldBoot,
      noAudio: noAudio ?? this.noAudio,
      gpuLaunchMode: gpuLaunchMode ?? this.gpuLaunchMode,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    final value = trimmedOverride;
    if (value != null) {
      map['sdkPathOverride'] = value;
    }
    final lastAvd = trimmedLastAvd;
    if (lastAvd != null) {
      map['lastSelectedAvd'] = lastAvd;
    }
    if (coldBoot) {
      map['coldBoot'] = true;
    }
    if (noAudio) {
      map['noAudio'] = true;
    }
    if (gpuLaunchMode.isNotEmpty && gpuLaunchMode != 'default') {
      map['gpuLaunchMode'] = gpuLaunchMode;
    }
    return map;
  }

  factory AppSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AppSettings();
    final rawOverride = json['sdkPathOverride'];
    final rawLastAvd = json['lastSelectedAvd'];
    final rawColdBoot = json['coldBoot'];
    final rawNoAudio = json['noAudio'];
    final rawGpuMode = json['gpuLaunchMode'];
    const allowedGpu = {'default', 'auto', 'host', 'swiftshader_indirect'};
    final gpu = (rawGpuMode is String && allowedGpu.contains(rawGpuMode))
        ? rawGpuMode
        : 'default';
    return AppSettings(
      sdkPathOverride: rawOverride is String ? rawOverride : null,
      lastSelectedAvd: rawLastAvd is String ? rawLastAvd : null,
      coldBoot: rawColdBoot is bool ? rawColdBoot : false,
      noAudio: rawNoAudio is bool ? rawNoAudio : false,
      gpuLaunchMode: gpu,
    );
  }
}

class SettingsException implements Exception {
  SettingsException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SettingsStore {
  SettingsStore({
    String? filePath,
    SettingsPathResolver? resolver,
    this._applicationSupportDirectory,
    this._executableDirectory,
    this._environment,
  })  : _fixedPath = filePath,
        _resolverOverride = resolver;

  final String? _fixedPath;
  final SettingsPathResolver? _resolverOverride;
  final Future<String?> Function()? _applicationSupportDirectory;
  final String? _executableDirectory;
  final Map<String, String>? _environment;

  SettingsPathResolver? _resolver;
  ResolvedSettingsPath? _resolved;

  /// Last path used for load or save, if known.
  String? get filePath => _fixedPath ?? _resolved?.filePath;

  String? get locationLabel => _resolved?.label;

  Future<AppSettings> load() async {
    final path = await _pathForLoad();
    if (path == null) {
      return const AppSettings();
    }
    final file = File(path);
    if (!await file.exists()) {
      return const AppSettings();
    }
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return const AppSettings();
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return AppSettings.fromJson(decoded);
      }
      if (decoded is Map) {
        return AppSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
      return const AppSettings();
    } on FormatException {
      return const AppSettings();
    } on FileSystemException {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    final resolved = await _pathForSave();
    final file = File(resolved.filePath);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(settings.toJson())}\n');
  }

  Future<String?> _pathForLoad() async {
    if (_fixedPath != null) {
      return _fixedPath;
    }
    final resolver = await _ensureResolver();
    final existing = resolver.existingLoadPath();
    if (existing != null) {
      _resolved = existing;
      return existing.filePath;
    }
    final writable = await resolver.firstWritable();
    if (writable != null) {
      _resolved = writable;
    }
    return writable?.filePath;
  }

  Future<ResolvedSettingsPath> _pathForSave() async {
    if (_fixedPath != null) {
      return ResolvedSettingsPath(
        directory: p.dirname(_fixedPath),
        filePath: _fixedPath,
        label: 'path tetap',
      );
    }
    final resolver = await _ensureResolver();
    final writable = await resolver.firstWritable();
    if (writable == null) {
      final tried = resolver.writeDirectories.join('; ');
      throw SettingsException(
        'Tidak ada lokasi yang dapat ditulisi untuk menyimpan pengaturan. '
        'Lokasi yang dicoba: $tried',
      );
    }
    _resolved = writable;
    return writable;
  }

  Future<SettingsPathResolver> _ensureResolver() async {
    if (_resolverOverride != null) {
      return _resolverOverride;
    }
    return _resolver ??= await _buildDefaultResolver();
  }

  Future<SettingsPathResolver> _buildDefaultResolver() async {
    final env = _environment ?? Platform.environment;
    final support = await _resolveApplicationSupportDirectory();
    final appData = env['APPDATA']?.trim();
    final localAppData = env['LOCALAPPDATA']?.trim();
    final exeDir = (_executableDirectory ?? p.dirname(Platform.resolvedExecutable)).trim();

    final write = <SettingsCandidate>[
      if (support != null && support.isNotEmpty)
        SettingsCandidate(support, 'direktori dukungan aplikasi'),
      if (localAppData != null && localAppData.isNotEmpty)
        SettingsCandidate(p.join(localAppData, 'AVD Launcher'), r'%LOCALAPPDATA%\AVD Launcher'),
      if (exeDir.isNotEmpty) SettingsCandidate(exeDir, 'folder aplikasi (portabel)'),
    ];
    final load = <SettingsCandidate>[
      if (support != null && support.isNotEmpty)
        SettingsCandidate(support, 'direktori dukungan aplikasi'),
      if (appData != null && appData.isNotEmpty)
        SettingsCandidate(p.join(appData, 'AVD Launcher'), r'%APPDATA%\AVD Launcher'),
      ...write,
    ];
    return SettingsPathResolver(
      writeCandidates: write,
      loadCandidates: load,
      canWriteDirectory: canCreateAndWriteDirectory,
      fileExists: (path) => File(path).existsSync(),
    );
  }

  Future<String?> _resolveApplicationSupportDirectory() async {
    final custom = _applicationSupportDirectory;
    if (custom != null) {
      return custom();
    }
    try {
      return (await getApplicationSupportDirectory()).path;
    } catch (_) {
      return null;
    }
  }
}

Future<bool> canCreateAndWriteDirectory(String directory) async {
  try {
    final dir = Directory(directory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final probe = File(p.join(directory, '.avd_launcher_write_test'));
    await probe.writeAsString('ok', flush: true);
    if (await probe.exists()) {
      await probe.delete();
    }
    return true;
  } on FileSystemException {
    return false;
  } on IOException {
    return false;
  }
}
