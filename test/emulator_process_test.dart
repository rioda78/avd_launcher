import 'dart:io';

import 'package:avd_launcher/services/emulator_process.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('parseAvdNameFromCommandLine membaca -avd', () {
    expect(
      parseAvdNameFromCommandLine(r'E:\Android\Sdk\emulator\emulator.exe -avd Pixel_10_Pro_Fold'),
      'Pixel_10_Pro_Fold',
    );
    expect(
      parseAvdNameFromCommandLine('qemu-system-x86_64.exe -avd Pixel_10_Pro_Fold'),
      'Pixel_10_Pro_Fold',
    );
    expect(parseAvdNameFromCommandLine(r'emulator.exe -avd "My Fold"'), 'My Fold');
    expect(parseAvdNameFromCommandLine('emulator.exe -list-avds'), isNull);
  });

  test('parseHostEmulatorProcessLines dan filter nama AVD', () {
    const output = '68132|emulator.exe|E:\\Android\\Sdk\\emulator\\emulator.exe -avd Pixel_10_Pro_Fold\n'
        '62728|qemu-system-x86_64.exe|qemu-system-x86_64.exe -avd Pixel_10_Pro_Fold\n'
        '11|emulator.exe|emulator.exe -avd Other\n';
    final all = parseHostEmulatorProcessLines(output);
    expect(all, hasLength(3));
    final fold = processesForAvd(all, 'Pixel_10_Pro_Fold');
    expect(fold.map((p) => p.pid), [68132, 62728]);
  });

  test('snapshot dirty atau snapshot.pb sangat kecil dianggap tidak lengkap', () {
    expect(
      isIncompleteQuickbootSnapshot(dirtyFileExists: true, dirtyContents: '1'),
      isTrue,
    );
    expect(
      isIncompleteQuickbootSnapshot(dirtyFileExists: false, snapshotPbLength: 11),
      isTrue,
    );
    expect(
      isIncompleteQuickbootSnapshot(dirtyFileExists: false, snapshotPbLength: 2048),
      isFalse,
    );
  });

  test('cadangan berkas .lock ke folder cap waktu, bukan AVD pengguna', () {
    final root = Directory.systemTemp.createTempSync('avd_lock_backup_');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    File(p.join(root.path, 'multiinstance.lock')).writeAsStringSync('stale');
    File(p.join(root.path, 'hardware-qemu.ini.lock')).writeAsStringSync('stale');
    File(p.join(root.path, 'config.ini')).writeAsStringSync('keep=yes\n');
    final backup = staleLockBackupDirectory(root.path, DateTime(2026, 11, 15, 17, 40, 0));
    expect(p.basename(backup), 'lock-backup-20261115-174000');
    Directory(backup).createSync();
    File(p.join(root.path, 'multiinstance.lock')).copySync(p.join(backup, 'multiinstance.lock'));
    File(p.join(root.path, 'hardware-qemu.ini.lock')).copySync(p.join(backup, 'hardware-qemu.ini.lock'));
    File(p.join(root.path, 'multiinstance.lock')).deleteSync();
    File(p.join(root.path, 'hardware-qemu.ini.lock')).deleteSync();
    expect(File(p.join(backup, 'multiinstance.lock')).existsSync(), isTrue);
    expect(File(p.join(root.path, 'multiinstance.lock')).existsSync(), isFalse);
    expect(File(p.join(root.path, 'config.ini')).readAsStringSync(), contains('keep=yes'));
  });
}
