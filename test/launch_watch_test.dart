import 'package:avd_launcher/services/launch_watch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('proses mati dianggap gagal', () {
    final result = assessAdbWatchTimeout(
      processAlive: false,
      windowVisible: false,
      adbHasEmulator: false,
      adbPortOpen: false,
      logPath: r'C:\logs\emu.log',
    );
    expect(result.isError, isTrue);
    expect(result.errorMessage, contains('berhenti sebelum tampil di adb'));
    expect(result.errorMessage, contains(r'C:\logs\emu.log'));
    expect(result.statusMessage, isNull);
  });

  test('jendela terlihat bukan kegagalan meskipun adb kosong', () {
    final result = assessAdbWatchTimeout(
      processAlive: true,
      windowVisible: true,
      adbHasEmulator: false,
      adbPortOpen: false,
      logPath: 'emu.log',
    );
    expect(result.isError, isFalse);
    expect(result.errorMessage, isNull);
    expect(result.statusMessage, contains('jendela terlihat'));
    expect(result.statusMessage, contains('adb belum terhubung'));
    expect(result.statusMessage, contains('127.0.0.1:5555'));
    expect(result.statusMessage, contains('GlobalProtect'));
  });

  test('port adb terbuka tanpa jendela juga bukan kegagalan keras', () {
    final result = assessAdbWatchTimeout(
      processAlive: true,
      windowVisible: false,
      adbHasEmulator: false,
      adbPortOpen: true,
      logPath: 'emu.log',
    );
    expect(result.isError, isFalse);
    expect(result.statusMessage, contains('port 5554/5555 terbuka'));
  });

  test('proses hidup tanpa jendela dan tanpa port: macet', () {
    final result = assessAdbWatchTimeout(
      processAlive: true,
      windowVisible: false,
      adbHasEmulator: false,
      adbPortOpen: false,
      logPath: 'emu.log',
    );
    expect(result.isError, isTrue);
    expect(result.errorMessage, contains('mungkin macet'));
    expect(result.errorMessage, contains('port 5554/5555 tidak terbuka'));
  });

  test('perangkat sudah di adb: status boot belum selesai', () {
    final result = assessAdbWatchTimeout(
      processAlive: true,
      windowVisible: true,
      adbHasEmulator: true,
      adbPortOpen: true,
      logPath: 'emu.log',
      displayTitle: 'emulator-5554 (Pixel_10_Pro_Fold)',
    );
    expect(result.isError, isFalse);
    expect(result.statusMessage, contains('emulator-5554 (Pixel_10_Pro_Fold) terdeteksi di adb'));
  });

  test('netstatHasListeningPort membaca LISTENING di localhost', () {
    const output = '''
  TCP    127.0.0.1:5037         0.0.0.0:0              LISTENING       14708
  TCP    127.0.0.1:5555         0.0.0.0:0              LISTENING       40020
  TCP    127.0.0.1:5554         127.0.0.1:5554         TIME_WAIT       0
''';
    expect(netstatHasListeningPort(output, 5555), isTrue);
    expect(netstatHasListeningPort(output, 5554), isFalse);
    expect(netstatHasListeningPort(output, 5037), isTrue);
    expect(netstatHasListeningPort(output, 5556), isFalse);
    expect(netstatHasListeningPort('TCP 127.0.0.1:15555 LISTENING', 5555), isFalse);
  });

  test('parseAdbConnectSuccess', () {
    expect(parseAdbConnectSuccess('connected to 127.0.0.1:5555'), isTrue);
    expect(parseAdbConnectSuccess('already connected to 127.0.0.1:5555'), isTrue);
    expect(
      parseAdbConnectSuccess(
        'cannot connect to 127.0.0.1:5555: No connection could be made because the target machine actively refused it. (10061)',
      ),
      isFalse,
    );
  });
}
