class SdkLocation {
  const SdkLocation({
    required this.root,
    required this.source,
    this.emulatorPath,
    this.adbPath,
    this.issues = const [],
    this.candidatesChecked = const [],
  });

  final String root;
  final String source;
  final String? emulatorPath;
  final String? adbPath;
  final List<String> issues;
  final List<String> candidatesChecked;

  bool get hasEmulator => emulatorPath != null && emulatorPath!.isNotEmpty;

  bool get hasAdb => adbPath != null && adbPath!.isNotEmpty;

  bool get isUsable => hasEmulator && hasAdb;

  String get errorMessage {
    if (issues.isEmpty) return '';
    return issues.join('\n');
  }
}

class SdkCandidate {
  const SdkCandidate(this.path, this.source);

  final String path;
  final String source;
}

/// Resolves the Android SDK root and the emulator/adb executables.
///
/// [pathExists] is injected so the candidate logic can be unit-tested
/// without touching the real disk.
class SdkLocator {
  SdkLocator({
    required this.pathExists,
    Map<String, String>? environment,
    this.localAppData,
  }) : environment = environment ?? const {};

  final bool Function(String path) pathExists;
  final Map<String, String> environment;
  final String? localAppData;

  SdkLocation resolve({String? override}) {
    final candidates = <SdkCandidate>[];
    final trimmedOverride = override?.trim();
    final hasOverride = trimmedOverride != null && trimmedOverride.isNotEmpty;

    if (hasOverride) {
      candidates.add(SdkCandidate(trimmedOverride, 'pengaturan manual'));
    } else {
      _addEnv(candidates, 'ANDROID_HOME');
      _addEnv(candidates, 'ANDROID_SDK_ROOT');
      final lad = localAppData?.trim();
      if (lad != null && lad.isNotEmpty) {
        candidates.add(
          SdkCandidate(
            joinPath(lad, 'Android', 'Sdk'),
            r'%LOCALAPPDATA%\Android\Sdk',
          ),
        );
      }
    }

    final checked = <String>[];
    final seen = <String>{};

    for (final candidate in candidates) {
      final root = normalizePath(candidate.path);
      if (root.isEmpty) continue;
      final key = root.toLowerCase();
      if (!seen.add(key)) continue;
      checked.add('$root  (${candidate.source})');

      final emulator = joinPath(root, 'emulator', 'emulator.exe');
      if (!pathExists(emulator)) {
        continue;
      }
      final adb = joinPath(root, 'platform-tools', 'adb.exe');
      final adbExists = pathExists(adb);
      return SdkLocation(
        root: root,
        source: candidate.source,
        emulatorPath: emulator,
        adbPath: adbExists ? adb : null,
        issues: adbExists
            ? const []
            : [
                'emulator.exe ditemukan, tetapi adb.exe tidak ada di:',
                adb,
                'Pasang Platform-Tools di SDK, atau pilih folder SDK yang lengkap.',
              ],
        candidatesChecked: checked,
      );
    }

    if (hasOverride) {
      final root = normalizePath(trimmedOverride);
      final expected = joinPath(root, 'emulator', 'emulator.exe');
      return SdkLocation(
        root: root,
        source: 'pengaturan manual',
        issues: [
          'Android SDK tidak valid pada lokasi yang dipilih.',
          'File yang dicari: $expected',
          'Pilih folder SDK yang berisi emulator\\emulator.exe, atau gunakan deteksi otomatis.',
        ],
        candidatesChecked: checked,
      );
    }

    return SdkLocation(
      root: '',
      source: '',
      issues: [
        'Android SDK atau emulator.exe tidak ditemukan.',
        if (checked.isNotEmpty) 'Lokasi yang diperiksa:',
        ...checked,
        'Setel ANDROID_HOME / ANDROID_SDK_ROOT, atau pilih folder SDK secara manual.',
      ],
      candidatesChecked: checked,
    );
  }

  void _addEnv(List<SdkCandidate> candidates, String name) {
    final value = environment[name]?.trim();
    if (value != null && value.isNotEmpty) {
      candidates.add(SdkCandidate(value, name));
    }
  }
}

String joinPath(String first, String second, [String? third]) {
  var result = _joinTwo(first, second);
  if (third != null) {
    result = _joinTwo(result, third);
  }
  return result;
}

String _joinTwo(String a, String b) {
  if (a.isEmpty) return normalizePath(b);
  if (b.isEmpty) return normalizePath(a);
  final sep = _separatorOf(a);
  var left = a;
  while (left.endsWith('\\') || left.endsWith('/')) {
    left = left.substring(0, left.length - 1);
  }
  var right = b;
  while (right.startsWith('\\') || right.startsWith('/')) {
    right = right.substring(1);
  }
  return '$left$sep$right';
}

String _separatorOf(String path) {
  if (path.contains('\\')) return '\\';
  if (path.contains('/')) return '/';
  return '\\';
}

String normalizePath(String path) {
  var value = path.trim();
  if (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1).trim();
  }
  while (value.length > 3 && (value.endsWith('\\') || value.endsWith('/'))) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}
