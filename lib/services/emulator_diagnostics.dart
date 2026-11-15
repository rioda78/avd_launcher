import 'package:path/path.dart' as p;

/// Reads a simple `key=value` line from an Android INI/config file.
String? parseIniValue(String content, String key) {
  for (final raw in content.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    final index = line.indexOf('=');
    if (index <= 0) continue;
    if (line.substring(0, index).trim() == key) {
      return line.substring(index + 1).trim();
    }
  }
  return null;
}

/// Resolves the `.avd` directory for [avdName] under [avdHome].
String resolveAvdDirectory({
  required String avdName,
  required String avdHome,
  String? Function(String path)? readFileIfExists,
}) {
  final read = readFileIfExists ?? (_) => null;
  final iniPath = p.join(avdHome, '$avdName.ini');
  final ini = read(iniPath);
  if (ini != null) {
    final path = parseIniValue(ini, 'path');
    if (path != null && path.isNotEmpty) {
      return path;
    }
  }
  return p.join(avdHome, '$avdName.avd');
}

/// Returns the absolute system-image path if it is missing, otherwise null.
String? missingSystemImagePath({
  required String sdkRoot,
  required String avdName,
  required String avdHome,
  required bool Function(String path) directoryExists,
  required String? Function(String path) readFileIfExists,
}) {
  final avdDir = resolveAvdDirectory(
    avdName: avdName,
    avdHome: avdHome,
    readFileIfExists: readFileIfExists,
  );
  final config = readFileIfExists(p.join(avdDir, 'config.ini'));
  if (config == null) {
    return null;
  }
  final relative = parseIniValue(config, 'image.sysdir.1');
  if (relative == null || relative.isEmpty) {
    return null;
  }
  final absolute = p.normalize(p.join(sdkRoot, relative));
  if (directoryExists(absolute)) {
    return null;
  }
  return absolute;
}

/// Pulls FATAL/PANIC lines and other useful failure hints from emulator output.
String? extractEmulatorFailure(String log) {
  final lines = log
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty) return null;

  final important = <String>[];
  for (final line in lines) {
    final upper = line.toUpperCase();
    if (upper.contains('FATAL') ||
        upper.contains('PANIC') ||
        upper.contains('BROKEN AVD') ||
        upper.contains('ACCESS IS DENIED') ||
        upper.contains('NOT A VALID DIRECTORY') ||
        upper.contains('HYPERVISOR') ||
        upper.contains('HAXM') ||
        upper.contains('WHPX') && (upper.contains('ERROR') || upper.contains('NOT') || upper.contains('FAIL'))) {
      important.add(line);
    }
  }
  if (important.isNotEmpty) {
    return important.join('\n');
  }
  return null;
}

/// Parses `adb shell getprop sys.boot_completed` output.
bool parseBootCompleted(String output) {
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line == '1') return true;
  }
  return false;
}

String sanitizeForFileName(String name) {
  return name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
}
