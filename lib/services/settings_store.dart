import 'dart:convert';
import 'dart:io';

class AppSettings {
  const AppSettings({this.sdkPathOverride});

  final String? sdkPathOverride;

  String? get trimmedOverride {
    final value = sdkPathOverride?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  AppSettings copyWith({String? sdkPathOverride, bool clearOverride = false}) {
    return AppSettings(
      sdkPathOverride: clearOverride ? null : (sdkPathOverride ?? this.sdkPathOverride),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    final value = trimmedOverride;
    if (value != null) {
      map['sdkPathOverride'] = value;
    }
    return map;
  }

  factory AppSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AppSettings();
    final raw = json['sdkPathOverride'];
    return AppSettings(sdkPathOverride: raw is String ? raw : null);
  }
}

class SettingsStore {
  SettingsStore({String? filePath}) : filePath = filePath ?? defaultFilePath();

  final String filePath;

  static String defaultFilePath() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return '$appData\\AVD Launcher\\settings.json';
    }
    return '${Directory.current.path}\\settings.json';
  }

  Future<AppSettings> load() async {
    final file = File(filePath);
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
    final file = File(filePath);
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString('${encoder.convert(settings.toJson())}\n');
  }
}
