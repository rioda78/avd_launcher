import 'dart:io';

import 'package:path/path.dart' as p;

const kGpuModes = ['auto', 'host', 'swiftshader_indirect'];

const kFallbackDeviceProfiles = [
  'pixel',
  'pixel_6',
  'pixel_7',
  'pixel_8',
  'pixel_9',
  'pixel_10_pro_fold',
  'medium_phone',
  'Nexus 5',
];

class IniEntry {
  IniEntry({required this.raw, this.key, this.value});

  String raw;
  String? key;
  String? value;
}

class IniDocument {
  IniDocument(this.entries, {this.newline = '\n'});

  final List<IniEntry> entries;
  final String newline;

  factory IniDocument.parse(String content) {
    final newline = content.contains('\r\n') ? '\r\n' : '\n';
    var body = content;
    if (body.endsWith('\r\n')) {
      body = body.substring(0, body.length - 2);
    } else if (body.endsWith('\n')) {
      body = body.substring(0, body.length - 1);
    }
    final lines = body.split(RegExp(r'\r?\n'));
    final entries = <IniEntry>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith(';')) {
        entries.add(IniEntry(raw: line));
        continue;
      }
      final index = line.indexOf('=');
      if (index <= 0) {
        entries.add(IniEntry(raw: line));
        continue;
      }
      entries.add(
        IniEntry(
          raw: line,
          key: line.substring(0, index).trim(),
          value: line.substring(index + 1).trim(),
        ),
      );
    }
    return IniDocument(entries, newline: newline);
  }

  String? get(String key) {
    for (final entry in entries.reversed) {
      if (entry.key == key) return entry.value;
    }
    return null;
  }

  void set(String key, String value) {
    for (final entry in entries) {
      if (entry.key == key) {
        entry.value = value;
        entry.raw = '$key=$value';
        return;
      }
    }
    entries.add(IniEntry(raw: '$key=$value', key: key, value: value));
  }

  String encode() {
    if (entries.isEmpty) return '';
    return '${entries.map((entry) => entry.raw).join(newline)}$newline';
  }
}

class SystemImage {
  const SystemImage({
    required this.api,
    required this.tag,
    required this.abi,
  });

  final String api;
  final String tag;
  final String abi;

  String get relativeDir => p.join('system-images', api, tag, abi);
  String get relativeDirWindows => 'system-images\\$api\\$tag\\$abi\\';
  String get packageId => 'system-images;$api;$tag;$abi';
  String get label => '$api · $tag · $abi';

  static SystemImage? tryParseSysdir(String sysdir) {
    var value = sysdir.trim().replaceAll('/', '\\');
    while (value.endsWith('\\')) {
      value = value.substring(0, value.length - 1);
    }
    final parts = value.split('\\').where((part) => part.isNotEmpty).toList();
    final start = parts.indexOf('system-images');
    if (start >= 0 && parts.length >= start + 4) {
      return SystemImage(
        api: parts[start + 1],
        tag: parts[start + 2],
        abi: parts[start + 3],
      );
    }
    if (parts.length == 3 && !parts.first.toLowerCase().contains('system-images')) {
      // already api/tag/abi
      return SystemImage(api: parts[0], tag: parts[1], abi: parts[2]);
    }
    if (parts.length == 4 && parts.first == 'system-images') {
      return SystemImage(api: parts[1], tag: parts[2], abi: parts[3]);
    }
    return null;
  }

  static SystemImage? tryParsePackageId(String packageId) {
    final parts = packageId.trim().split(';');
    if (parts.length == 4 && parts[0] == 'system-images') {
      return SystemImage(api: parts[1], tag: parts[2], abi: parts[3]);
    }
    return null;
  }
}

class AvdConfigValidation {
  const AvdConfigValidation({
    this.ramError,
    this.storageError,
    this.gpuError,
    this.coresError,
    this.imageError,
    this.nameError,
  });

  final String? ramError;
  final String? storageError;
  final String? gpuError;
  final String? coresError;
  final String? imageError;
  final String? nameError;

  bool get hasError =>
      ramError != null ||
      storageError != null ||
      gpuError != null ||
      coresError != null ||
      imageError != null ||
      nameError != null;

  String? get firstError =>
      nameError ?? imageError ?? ramError ?? storageError ?? gpuError ?? coresError;
}

String? validateAvdName(String name, {Iterable<String> existing = const []}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return 'Nama AVD tidak boleh kosong.';
  }
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9._-]*$').hasMatch(trimmed)) {
    return 'Nama harus diawali huruf, dan hanya boleh berisi huruf, angka, titik, garis bawah, atau tanda minus.';
  }
  if (trimmed.length > 64) {
    return 'Nama AVD terlalu panjang (maksimum 64 karakter).';
  }
  for (final current in existing) {
    if (current.toLowerCase() == trimmed.toLowerCase()) {
      return 'Nama "$trimmed" sudah dipakai.';
    }
  }
  return null;
}

String? validateRamSize(String value) {
  final trimmed = value.trim();
  final parsed = int.tryParse(trimmed);
  if (parsed == null) {
    return 'RAM harus berupa angka dalam MB, misalnya 2048.';
  }
  if (parsed < 256 || parsed > 32768) {
    return 'RAM harus antara 256 dan 32768 MB.';
  }
  return null;
}

String? validateStorageSize(String value) {
  final trimmed = value.trim();
  final match = RegExp(r'^([0-9]+)([KMGkmg])?$').firstMatch(trimmed);
  if (match == null) {
    return 'Penyimpanan internal harus seperti 2048, 8192M, atau 10G.';
  }
  final amount = int.parse(match.group(1)!);
  final unit = (match.group(2) ?? 'M').toUpperCase();
  var megabytes = amount;
  switch (unit) {
    case 'K':
      megabytes = amount / 1024 < 1 ? 0 : (amount / 1024).floor();
      break;
    case 'G':
      megabytes = amount * 1024;
      break;
    default:
      megabytes = amount;
  }
  if (megabytes < 64 || megabytes > 65536) {
    return 'Penyimpanan internal harus antara 64 MB dan 64 G.';
  }
  return null;
}

String? validateGpuMode(String value) {
  final trimmed = value.trim();
  if (!kGpuModes.contains(trimmed)) {
    return 'Mode GPU harus auto, host, atau swiftshader_indirect.';
  }
  return null;
}

String? validateCpuCores(String value) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null) {
    return 'Jumlah inti CPU harus berupa angka, misalnya 4.';
  }
  if (parsed < 1 || parsed > 16) {
    return 'Jumlah inti CPU harus antara 1 dan 16.';
  }
  return null;
}

AvdConfigValidation validateAvdConfig({
  String? name,
  Iterable<String> existingNames = const [],
  required String ramSize,
  required String storageSize,
  required String gpuMode,
  String? cpuCores,
  String? imageSysdir,
  bool requireImage = true,
  bool Function(String sysdir)? imageExists,
}) {
  String? imageError;
  if (requireImage) {
    final sysdir = (imageSysdir ?? '').trim();
    if (sysdir.isEmpty) {
      imageError = 'Pilih system image yang sudah terpasang.';
    } else if (imageExists != null && !imageExists(sysdir)) {
      imageError = 'System image tidak ditemukan di SDK:\n$sysdir';
    }
  }
  return AvdConfigValidation(
    nameError: name == null ? null : validateAvdName(name, existing: existingNames),
    ramError: validateRamSize(ramSize),
    storageError: validateStorageSize(storageSize),
    gpuError: validateGpuMode(gpuMode),
    coresError: cpuCores == null ? null : validateCpuCores(cpuCores),
    imageError: imageError,
  );
}

String normalizeStorageSize(String value) {
  final trimmed = value.trim();
  final match = RegExp(r'^([0-9]+)([KMGkmg])?$').firstMatch(trimmed);
  if (match == null) return trimmed;
  final amount = match.group(1)!;
  final unit = match.group(2);
  if (unit == null) return '${amount}M';
  return '$amount${unit.toUpperCase()}';
}

List<SystemImage> listInstalledSystemImages(
  String sdkRoot, {
  bool Function(String path)? hasSystemImage,
}) {
  final check = hasSystemImage ??
      (path) => File(p.join(path, 'system.img')).existsSync();
  final root = Directory(p.join(sdkRoot, 'system-images'));
  if (!root.existsSync()) return const [];

  final images = <SystemImage>[];
  for (final apiDir in _listDirs(root)) {
    for (final tagDir in _listDirs(apiDir)) {
      for (final abiDir in _listDirs(tagDir)) {
        if (check(abiDir.path)) {
          images.add(
            SystemImage(
              api: p.basename(apiDir.path),
              tag: p.basename(tagDir.path),
              abi: p.basename(abiDir.path),
            ),
          );
        }
      }
    }
  }
  images.sort((a, b) => a.label.compareTo(b.label));
  return images;
}

List<Directory> _listDirs(Directory parent) {
  try {
    return parent
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
  } on FileSystemException {
    return const [];
  }
}

String sdkmanagerInstallCommand(String packageOrSysdir) {
  final image = SystemImage.tryParsePackageId(packageOrSysdir) ??
      SystemImage.tryParseSysdir(packageOrSysdir);
  final id = image?.packageId ?? packageOrSysdir.trim();
  return 'sdkmanager "$id"';
}

String backupConfigPath(String configPath, DateTime timestamp) {
  final dir = p.dirname(configPath);
  final stamp =
      '${timestamp.year.toString().padLeft(4, '0')}'
      '${timestamp.month.toString().padLeft(2, '0')}'
      '${timestamp.day.toString().padLeft(2, '0')}-'
      '${timestamp.hour.toString().padLeft(2, '0')}'
      '${timestamp.minute.toString().padLeft(2, '0')}'
      '${timestamp.second.toString().padLeft(2, '0')}';
  return p.join(dir, 'config.ini.bak-$stamp');
}

bool isFileLockHeld(String path) {
  final file = File(path);
  if (!file.existsSync()) return false;
  if (Platform.isWindows) {
    try {
      // On Windows, Android Emulator opens its .lock files without FILE_SHARE_DELETE.
      // Attempting to delete an unlocked stale .lock file succeeds and cleans it up;
      // if locked by a running emulator, deleteSync throws a FileSystemException
      // (sharing violation) without creating or touching the file.
      file.deleteSync();
      return false;
    } on FileSystemException {
      return true;
    }
  }
  RandomAccessFile? handle;
  try {
    handle = file.openSync(mode: FileMode.writeOnlyAppend);
    handle.lockSync(FileLock.exclusive);
    handle.unlockSync();
    return false;
  } on FileSystemException {
    return true;
  } finally {
    try {
      handle?.closeSync();
    } catch (_) {}
  }
}

bool isAvdLockHeld(String avdDirectory) {
  // Check hardware-qemu.ini.lock first; only check multiinstance.lock if needed,
  // and never create files that do not exist.
  const names = ['hardware-qemu.ini.lock', 'multiinstance.lock'];
  var locked = false;
  for (final name in names) {
    if (isFileLockHeld(p.join(avdDirectory, name))) {
      locked = true;
    }
  }
  return locked;
}

String findAvdManagerPath(String sdkRoot) {
  final candidates = <String>[
    p.join(sdkRoot, 'cmdline-tools', 'latest', 'bin', 'avdmanager.bat'),
    p.join(sdkRoot, 'cmdline-tools', 'latest', 'bin', 'avdmanager'),
    p.join(sdkRoot, 'tools', 'bin', 'avdmanager.bat'),
    p.join(sdkRoot, 'tools', 'bin', 'avdmanager'),
  ];
  final toolsDir = Directory(p.join(sdkRoot, 'cmdline-tools'));
  if (toolsDir.existsSync()) {
    try {
      for (final entity in toolsDir.listSync()) {
        if (entity is Directory) {
          candidates.add(p.join(entity.path, 'bin', 'avdmanager.bat'));
          candidates.add(p.join(entity.path, 'bin', 'avdmanager'));
        }
      }
    } on FileSystemException {
      // ignore unreadable trees
    }
  }
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return '';
}

String avdManagerMissingMessage(String sdkRoot) {
  final expected = p.join(sdkRoot, 'cmdline-tools', 'latest', 'bin', 'avdmanager.bat');
  return 'avdmanager tidak ditemukan.\n'
      'Pasang Android SDK Command-line Tools, misalnya lewat Android Studio '
      '(SDK Manager → SDK Tools → Android SDK Command-line Tools), atau:\n'
      'sdkmanager "cmdline-tools;latest"\n'
      'Lalu pastikan berkas ini ada:\n'
      '$expected';
}

List<String> parseDeviceList(String output) {
  final names = <String>[];
  final seen = <String>{};
  for (final raw in output.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    if (lower.contains('error') ||
        lower.contains('usage:') ||
        lower.startsWith('available') ||
        lower.startsWith('id ') ||
        lower.startsWith('---') ||
        lower.startsWith('loading')) {
      continue;
    }
    if (line.contains('=')) continue;
    if (seen.add(line.toLowerCase())) {
      names.add(line);
    }
  }
  return names;
}
