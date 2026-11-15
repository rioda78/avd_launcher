import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'avd_service.dart';

class SdkSetupConfig {
  const SdkSetupConfig({
    required this.targetRoot,
    this.installPlatformTools = true,
    this.installEmulator = true,
    this.installSystemImage = true,
    this.systemImagePackage =
        'system-images;android-35;google_apis_playstore;x86_64',
  });

  final String targetRoot;
  final bool installPlatformTools;
  final bool installEmulator;
  final bool installSystemImage;
  final String systemImagePackage;
}

class SdkInstaller {
  SdkInstaller({HttpClient Function()? httpClientFactory})
      : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final HttpClient Function() _httpClientFactory;

  static const String kCmdlineToolsWinUrl =
      'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip';

  static const List<String> kRecommendedSystemImages = <String>[
    'system-images;android-35;google_apis_playstore;x86_64',
    'system-images;android-34;google_apis_playstore;x86_64',
    'system-images;android-33;google_apis_playstore;x86_64',
  ];

  static String defaultTargetRoot(Map<String, String> environment) {
    final localAppData = environment['LOCALAPPDATA']?.trim();
    if (localAppData != null && localAppData.isNotEmpty) {
      return p.join(localAppData, 'Android', 'Sdk');
    }
    final userProfile = environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      return p.join(userProfile, 'AppData', 'Local', 'Android', 'Sdk');
    }
    return r'C:\Android\Sdk';
  }

  Future<void> installSdk({
    required SdkSetupConfig config,
    required void Function(String message) onProgress,
  }) async {
    final sdkRoot = config.targetRoot.trim();
    if (sdkRoot.isEmpty) {
      throw AvdException('Pilih folder tujuan instalasi Android SDK.');
    }

    final rootDir = Directory(sdkRoot);
    await rootDir.create(recursive: true);

    final sdkManagerPath = await _ensureCmdlineTools(
      sdkRoot: sdkRoot,
      onProgress: onProgress,
    );

    final javaHome = _detectJavaHome();
    final env = <String, String>{
      'ANDROID_SDK_ROOT': sdkRoot,
      'ANDROID_HOME': sdkRoot,
      if (javaHome != null && javaHome.isNotEmpty) 'JAVA_HOME': javaHome,
    };

    onProgress('Menyetujui lisensi Android SDK…');
    await _acceptLicenses(
      sdkManagerPath: sdkManagerPath,
      sdkRoot: sdkRoot,
      environment: env,
    );

    final packages = <String>[
      'cmdline-tools;latest',
      if (config.installPlatformTools) 'platform-tools',
      if (config.installEmulator) 'emulator',
      if (config.installSystemImage &&
          config.systemImagePackage.trim().isNotEmpty) ...[
        _platformForImage(config.systemImagePackage.trim()),
        config.systemImagePackage.trim(),
      ],
    ];

    for (final pkg in packages) {
      if (pkg.isEmpty) continue;
      onProgress('Memasang paket SDK: $pkg …');
      await _installPackage(
        sdkManagerPath: sdkManagerPath,
        sdkRoot: sdkRoot,
        packageId: pkg,
        environment: env,
        onProgress: onProgress,
      );
    }

    onProgress('Instalasi komponen Android SDK selesai.');
  }

  String _platformForImage(String systemImagePackage) {
    final parts = systemImagePackage.split(';');
    if (parts.length >= 2 && parts[1].startsWith('android-')) {
      return 'platforms;${parts[1]}';
    }
    return '';
  }

  Future<String> _ensureCmdlineTools({
    required String sdkRoot,
    required void Function(String message) onProgress,
  }) async {
    final existing = _findSdkManager(sdkRoot);
    if (existing != null) {
      onProgress('Command-line Tools sudah tersedia.');
      return existing;
    }

    final tempDir =
        await Directory.systemTemp.createTemp('avd_launcher_cmdline_');
    final zipPath = p.join(tempDir.path, 'commandlinetools.zip');
    final extractDir = p.join(tempDir.path, 'extracted');

    try {
      onProgress('Mengunduh Android Command-line Tools dari Google…');
      await _downloadFile(
        url: kCmdlineToolsWinUrl,
        destinationPath: zipPath,
        onProgress: onProgress,
      );

      onProgress('Mengekstrak Command-line Tools…');
      await Directory(extractDir).create(recursive: true);
      final extractResult = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$extractDir' -Force",
        ],
      );
      if (extractResult.exitCode != 0) {
        final tarResult = await Process.run(
          'tar.exe',
          ['-xf', zipPath, '-C', extractDir],
        );
        if (tarResult.exitCode != 0) {
          throw AvdException(
            'Gagal mengekstrak Command-line Tools:\n${extractResult.stderr}',
          );
        }
      }

      final extractedCmdline = Directory(p.join(extractDir, 'cmdline-tools'));
      final sourceDir =
          await extractedCmdline.exists() ? extractedCmdline : Directory(extractDir);
      final latestDir = Directory(p.join(sdkRoot, 'cmdline-tools', 'latest'));
      if (await latestDir.exists()) {
        await latestDir.delete(recursive: true);
      }
      await latestDir.parent.create(recursive: true);
      await _copyDirectory(sourceDir, latestDir);

      final installed = _findSdkManager(sdkRoot);
      if (installed == null) {
        throw AvdException(
          'sdkmanager.bat tidak ditemukan setelah mengekstrak Command-line Tools.',
        );
      }
      return installed;
    } finally {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  Future<void> _downloadFile({
    required String url,
    required String destinationPath,
    required void Function(String message) onProgress,
  }) async {
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != 200) {
        throw AvdException(
          'Gagal mengunduh Command-line Tools (HTTP ${response.statusCode}).',
        );
      }
      final total = response.contentLength;
      final file = File(destinationPath);
      final sink = file.openWrite();
      var received = 0;
      var lastReportedPercent = -1;
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final percent = ((received * 100) / total).floor();
          if (percent != lastReportedPercent && percent % 5 == 0) {
            lastReportedPercent = percent;
            final mb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
            onProgress(
              'Mengunduh Command-line Tools… $percent% ($mb / $totalMb MB)',
            );
          }
        }
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _acceptLicenses({
    required String sdkManagerPath,
    required String sdkRoot,
    required Map<String, String> environment,
  }) async {
    // Also pre-write standard license hashes so sdkmanager doesn't get stuck
    final licensesDir = Directory(p.join(sdkRoot, 'licenses'));
    await licensesDir.create(recursive: true);
    await File(p.join(licensesDir.path, 'android-sdk-license')).writeAsString(
      '\n8933bad161af4178b1185d1a37fbf41ea5269c55\n'
      'd56f5187479451eabf01fb78af6dfcb131a6481e\n'
      '24333f8a63b6825ea9c5514f83c2829b004d1fee\n'
      '85435445a95c234340d05367a999a69d7b46701c\n',
    );
    await File(p.join(licensesDir.path, 'android-sdk-preview-license'))
        .writeAsString(
      '\n84831b9409646a918e30573bab4c9c91346d8abd\n'
      '504667f4c0de7af1a06de9f4b1727b84351f2910\n',
    );

    try {
      final process = await Process.start(
        sdkManagerPath,
        ['--sdk_root=$sdkRoot', '--licenses'],
        environment: environment,
        includeParentEnvironment: true,
        runInShell: Platform.isWindows,
      );
      for (var i = 0; i < 30; i++) {
        process.stdin.writeln('y');
      }
      await process.stdin.close();
      await process.exitCode.timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          process.kill();
          return 0;
        },
      );
    } catch (_) {
      // Pre-written license files will still allow package installation.
    }
  }

  Future<void> _installPackage({
    required String sdkManagerPath,
    required String sdkRoot,
    required String packageId,
    required Map<String, String> environment,
    required void Function(String message) onProgress,
  }) async {
    final process = await Process.start(
      sdkManagerPath,
      ['--sdk_root=$sdkRoot', packageId],
      environment: environment,
      includeParentEnvironment: true,
      runInShell: Platform.isWindows,
    );
    for (var i = 0; i < 15; i++) {
      process.stdin.writeln('y');
    }
    await process.stdin.close();

    final stderrBuffer = StringBuffer();
    process.stdout
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        onProgress('[$packageId] $trimmed');
      }
    });
    process.stderr
        .transform(const SystemEncoding().decoder)
        .transform(const LineSplitter())
        .listen((line) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        stderrBuffer.writeln(trimmed);
      }
    });

    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      final err = stderrBuffer.toString().trim();
      throw AvdException(
        'Gagal memasang paket "$packageId" (kode $exitCode).'
        '${err.isEmpty ? '' : '\n$err'}',
      );
    }
  }

  String? _findSdkManager(String sdkRoot) {
    final candidates = <String>[
      p.join(sdkRoot, 'cmdline-tools', 'latest', 'bin', 'sdkmanager.bat'),
      p.join(sdkRoot, 'cmdline-tools', 'bin', 'sdkmanager.bat'),
      p.join(sdkRoot, 'tools', 'bin', 'sdkmanager.bat'),
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  String? _detectJavaHome() {
    final envJava = Platform.environment['JAVA_HOME']?.trim();
    if (envJava != null &&
        envJava.isNotEmpty &&
        File(p.join(envJava, 'bin', 'java.exe')).existsSync()) {
      return envJava;
    }
    const studioJbr = r'C:\Program Files\Android\Android Studio\jbr';
    if (File(p.join(studioJbr, 'bin', 'java.exe')).existsSync()) {
      return studioJbr;
    }
    for (final base in [
      r'C:\Program Files\Java',
      r'C:\Program Files\Eclipse Adoptium',
      r'C:\Program Files\Microsoft',
    ]) {
      final dir = Directory(base);
      if (!dir.existsSync()) continue;
      try {
        for (final sub in dir.listSync().whereType<Directory>()) {
          if (File(p.join(sub.path, 'bin', 'java.exe')).existsSync()) {
            return sub.path;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}
