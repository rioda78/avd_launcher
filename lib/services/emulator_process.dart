import 'dart:io';

import 'package:path/path.dart' as p;

/// An emulator.exe or qemu-system process discovered on the host.
class HostEmulatorProcess {
  const HostEmulatorProcess({
    required this.pid,
    required this.processName,
    required this.commandLine,
    this.avdName,
  });

  final int pid;
  final String processName;
  final String commandLine;
  final String? avdName;

  bool get isQemu => processName.toLowerCase().contains('qemu');
}

String? parseAvdNameFromCommandLine(String commandLine) {
  final match = RegExp(
    r'-avd(?:\s+|=)(?:"([^"]+)"|(\S+))',
    caseSensitive: false,
  ).firstMatch(commandLine);
  if (match == null) return null;
  final name = match.group(1) ?? match.group(2);
  if (name == null || name.isEmpty) return null;
  return name;
}

/// Parses lines of the form `pid|processName|commandLine`.
List<HostEmulatorProcess> parseHostEmulatorProcessLines(String output) {
  final items = <HostEmulatorProcess>[];
  final seen = <int>{};
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split('|');
    if (parts.length < 2) continue;
    final pid = int.tryParse(parts[0].trim());
    if (pid == null || pid <= 0 || !seen.add(pid)) continue;
    final name = parts[1].trim();
    final command = parts.length > 2 ? parts.sublist(2).join('|').trim() : '';
    items.add(
      HostEmulatorProcess(
        pid: pid,
        processName: name,
        commandLine: command,
        avdName: parseAvdNameFromCommandLine(command),
      ),
    );
  }
  return items;
}

List<HostEmulatorProcess> processesForAvd(
  Iterable<HostEmulatorProcess> processes,
  String avdName,
) {
  final lower = avdName.trim().toLowerCase();
  if (lower.isEmpty) return const [];
  return processes
      .where((proc) => (proc.avdName ?? '').toLowerCase() == lower)
      .toList();
}

/// True when the AVD's default_boot snapshot looks incomplete or dirty.
/// Does not inspect or delete the snapshot files; callers should suggest a cold boot.
bool isIncompleteQuickbootSnapshot({
  required bool dirtyFileExists,
  String dirtyContents = '',
  int? snapshotPbLength,
}) {
  if (dirtyFileExists) {
    final value = dirtyContents.trim().toLowerCase();
    if (value.isEmpty || value == '1' || value == 'true' || value == 'yes') {
      return true;
    }
  }
  if (snapshotPbLength != null && snapshotPbLength > 0 && snapshotPbLength < 64) {
    return true;
  }
  return false;
}

bool avdHasIncompleteQuickbootSnapshot(String avdDirectory) {
  final snapDir = p.join(avdDirectory, 'snapshots', 'default_boot');
  final dirty = File(p.join(snapDir, 'ram.img.dirty'));
  var dirtyExists = false;
  var dirtyContents = '';
  if (dirty.existsSync()) {
    dirtyExists = true;
    try {
      dirtyContents = dirty.readAsStringSync();
    } on FileSystemException {
      dirtyContents = '1';
    }
  }
  int? pbLength;
  final pb = File(p.join(snapDir, 'snapshot.pb'));
  if (pb.existsSync()) {
    try {
      pbLength = pb.lengthSync();
    } on FileSystemException {
      pbLength = null;
    }
  }
  return isIncompleteQuickbootSnapshot(
    dirtyFileExists: dirtyExists,
    dirtyContents: dirtyContents,
    snapshotPbLength: pbLength,
  );
}

String staleLockBackupDirectory(String avdDirectory, DateTime timestamp) {
  final stamp =
      '${timestamp.year.toString().padLeft(4, '0')}'
      '${timestamp.month.toString().padLeft(2, '0')}'
      '${timestamp.day.toString().padLeft(2, '0')}-'
      '${timestamp.hour.toString().padLeft(2, '0')}'
      '${timestamp.minute.toString().padLeft(2, '0')}'
      '${timestamp.second.toString().padLeft(2, '0')}';
  return p.join(avdDirectory, 'lock-backup-$stamp');
}

const kStaleLockNames = [
  'hardware-qemu.ini.lock',
  'multiinstance.lock',
  'userdata-qemu.img.lock',
];
