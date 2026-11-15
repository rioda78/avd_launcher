import 'dart:io';

import 'package:avd_launcher/services/avd_config.dart';
import 'package:avd_launcher/services/windows_hidden_process.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('parse dan tulis config.ini menjaga kunci lain dan urutan', () {
    const original = '# hardware\n'
        'AvdId=Pixel_10_Pro_Fold\n'
        'hw.ramSize=2048\n'
        'hw.cpu.ncore=4\n'
        'disk.dataPartition.size=10G\n'
        'hw.gpu.enabled=yes\n'
        'hw.gpu.mode=auto\n'
        'image.sysdir.1=system-images\\android-37.2-beta3\\google_apis_playstore_ps16k\\x86_64\\\n'
        'PlayStore.enabled=true\n';
    final document = IniDocument.parse(original);
    expect(document.get('PlayStore.enabled'), 'true');
    expect(document.get('hw.ramSize'), '2048');
    document.set('hw.ramSize', '4096');
    document.set('hw.gpu.mode', 'swiftshader_indirect');
    document.set('disk.dataPartition.size', '16G');
    document.set('hw.cpu.ncore', '6');
    final encoded = document.encode();
    expect(encoded, contains('AvdId=Pixel_10_Pro_Fold'));
    expect(encoded, contains('PlayStore.enabled=true'));
    expect(encoded, contains('hw.ramSize=4096'));
    expect(encoded, contains('hw.gpu.mode=swiftshader_indirect'));
    expect(encoded, contains('disk.dataPartition.size=16G'));
    expect(encoded, contains('hw.cpu.ncore=6'));
    expect(encoded.indexOf('AvdId='), lessThan(encoded.indexOf('hw.ramSize=')));
    expect(encoded.indexOf('hw.ramSize='), lessThan(encoded.indexOf('PlayStore.enabled=')));
  });

  test('menambah kunci baru di akhir jika belum ada', () {
    final document = IniDocument.parse('AvdId=Test\n');
    document.set('hw.ramSize', '1024');
    expect(document.encode(), 'AvdId=Test\nhw.ramSize=1024\n');
  });

  test('validasi RAM, penyimpanan, GPU, inti, dan nama', () {
    expect(validateRamSize('2048'), isNull);
    expect(validateRamSize('100'), isNotNull);
    expect(validateRamSize('abc'), isNotNull);
    expect(validateStorageSize('10G'), isNull);
    expect(validateStorageSize('2048'), isNull);
    expect(validateStorageSize('8192M'), isNull);
    expect(validateStorageSize('1K'), isNotNull);
    expect(validateGpuMode('auto'), isNull);
    expect(validateGpuMode('host'), isNull);
    expect(validateGpuMode('swiftshader_indirect'), isNull);
    expect(validateGpuMode('guest'), isNotNull);
    expect(validateCpuCores('4'), isNull);
    expect(validateCpuCores('0'), isNotNull);
    expect(validateAvdName('Pixel_Test'), isNull);
    expect(validateAvdName('1bad'), isNotNull);
    expect(validateAvdName('Bad name'), isNotNull);
    expect(validateAvdName('Pixel_10_Pro_Fold', existing: ['Pixel_10_Pro_Fold']), isNotNull);
    expect(validateAvdName('pixel_10_pro_fold', existing: ['Pixel_10_Pro_Fold']), isNotNull);
  });

  test('package id dan sysdir image saling diterjemahkan', () {
    final fromDir = SystemImage.tryParseSysdir(
      r'system-images\android-37.2-beta3\google_apis_playstore_ps16k\x86_64\',
    );
    expect(fromDir, isNotNull);
    expect(fromDir!.packageId, 'system-images;android-37.2-beta3;google_apis_playstore_ps16k;x86_64');
    expect(fromDir.relativeDirWindows, r'system-images\android-37.2-beta3\google_apis_playstore_ps16k\x86_64\');

    final fromPkg = SystemImage.tryParsePackageId(
      'system-images;android-36;google_apis_playstore;x86_64',
    );
    expect(fromPkg, isNotNull);
    expect(fromPkg!.api, 'android-36');
    expect(
      sdkmanagerInstallCommand(r'system-images\android-36\google_apis_playstore\x86_64'),
      'sdkmanager "system-images;android-36;google_apis_playstore;x86_64"',
    );
  });

  test('cadangan config.ini memakai cap waktu', () {
    final path = backupConfigPath(
      r'E:\Android\avd\Demo.avd\config.ini',
      DateTime(2026, 11, 15, 12, 30, 5),
    );
    expect(path, r'E:\Android\avd\Demo.avd\config.ini.bak-20261115-123005');
  });

  test('menyimpan config.ini ke salinan tes, bukan AVD pengguna', () {
    final root = Directory.systemTemp.createTempSync('avd_launcher_config_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final avdDir = Directory(p.join(root.path, 'Copy_Test.avd'))..createSync();
    final config = File(p.join(avdDir.path, 'config.ini'));
    config.writeAsStringSync(
      'AvdId=Copy_Test\n'
      'hw.ramSize=2048\n'
      'disk.dataPartition.size=10G\n'
      'hw.gpu.mode=auto\n'
      'hw.cpu.ncore=4\n'
      'keep.me=yes\n',
    );
    final document = IniDocument.parse(config.readAsStringSync());
    document.set('hw.ramSize', '3072');
    document.set('disk.dataPartition.size', '8G');
    document.set('hw.gpu.mode', 'host');
    document.set('hw.cpu.ncore', '2');
    final backup = File(
      backupConfigPath(config.path, DateTime(2026, 11, 15, 13, 0, 0)),
    );
    config.copySync(backup.path);
    config.writeAsStringSync(document.encode());

    expect(backup.existsSync(), isTrue);
    expect(backup.readAsStringSync(), contains('hw.ramSize=2048'));
    final written = config.readAsStringSync();
    expect(written, contains('hw.ramSize=3072'));
    expect(written, contains('disk.dataPartition.size=8G'));
    expect(written, contains('hw.gpu.mode=host'));
    expect(written, contains('hw.cpu.ncore=2'));
    expect(written, contains('keep.me=yes'));
    expect(written, contains('AvdId=Copy_Test'));
  });

  test('parse daftar perangkat avdmanager list device -c', () {
    const output = 'pixel\n'
        'pixel_7\n'
        'pixel_10_pro_fold\n'
        '\n'
        'medium_phone\n';
    expect(parseDeviceList(output), [
      'pixel',
      'pixel_7',
      'pixel_10_pro_fold',
      'medium_phone',
    ]);
  });

  test('kutip argumen baris perintah Windows', () {
    expect(quoteWindowsArg(r'E:\Android\Sdk\emulator\emulator.exe'), r'E:\Android\Sdk\emulator\emulator.exe');
    expect(quoteWindowsArg('Pixel 10'), '"Pixel 10"');
    expect(
      windowsCommandLine(r'E:\Android\Sdk\emulator\emulator.exe', ['-avd', 'Pixel_10_Pro_Fold']),
      r'E:\Android\Sdk\emulator\emulator.exe -avd Pixel_10_Pro_Fold',
    );
  });

  test('isAvdLockHeld membersihkan direktori .lock yatim dengan pid yang sudah mati', () {
    final root = Directory.systemTemp.createTempSync('avd_launcher_lock_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final lockDir = Directory(p.join(root.path, 'hardware-qemu.ini.lock'))
      ..createSync();
    File(p.join(lockDir.path, 'pid')).writeAsStringSync('9999999');
    final multiFile = File(p.join(root.path, 'multiinstance.lock'))
      ..writeAsStringSync('');

    expect(isAvdLockHeld(root.path), isFalse);
    expect(lockDir.existsSync(), isFalse);
    expect(multiFile.existsSync(), isFalse);
  });
}
