import '../models/adb_device.dart';

/// Parses stdout of `emulator -list-avds` into AVD names.
///
/// Empty lines and typical emulator log lines are ignored so a noisy
/// toolchain still yields a usable list.
List<String> parseAvdList(String output) {
  final names = <String>[];
  final seen = <String>{};
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (_isEmulatorLogLine(line)) continue;
    if (seen.add(line)) {
      names.add(line);
    }
  }
  return names;
}

bool _isEmulatorLogLine(String line) {
  final first = line.split(RegExp(r'\s+')).first.toUpperCase();
  const levels = {'INFO', 'WARNING', 'WARN', 'ERROR', 'DEBUG', 'VERBOSE', 'FATAL'};
  if (levels.contains(first)) return true;
  if (line.contains(' | ')) return true;
  return false;
}

/// Parses stdout of `adb devices` or `adb devices -l`.
List<AdbDevice> parseAdbDevices(String output) {
  final devices = <AdbDevice>[];
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('*')) continue;
    if (line.toLowerCase().startsWith('list of devices attached')) continue;
    if (line.toLowerCase().startsWith('adb:')) continue;

    final match = RegExp(r'^(\S+)\s+(\S+)(?:\s+(.*))?$').firstMatch(line);
    if (match == null) continue;

    final extras = <String, String>{};
    final rest = match.group(3);
    if (rest != null && rest.isNotEmpty) {
      for (final part in rest.split(RegExp(r'\s+'))) {
        final index = part.indexOf(':');
        if (index > 0) {
          extras[part.substring(0, index)] = part.substring(index + 1);
        }
      }
    }

    devices.add(
      AdbDevice(
        serial: match.group(1)!,
        state: match.group(2)!,
        extras: extras,
      ),
    );
  }
  return devices;
}
