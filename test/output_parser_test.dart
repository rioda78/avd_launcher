import 'package:avd_launcher/services/output_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseAvdList', () {
    test('membaca daftar AVD yang bersih', () {
      const output = 'Pixel_10_Pro_Fold\nSaringSMS_Test\npixel_7_-_api_36_0\n';
      expect(
        parseAvdList(output),
        ['Pixel_10_Pro_Fold', 'SaringSMS_Test', 'pixel_7_-_api_36_0'],
      );
    });

    test('mengabaikan baris kosong, log emulator, dan duplikat', () {
      const output = '''
INFO         | Android emulator version 37.2.13.0
Pixel_10_Pro_Fold

WARNING        | some warning
SaringSMS_Test
SaringSMS_Test
ERROR | failed something
pixel_7_-_api_36_0

''';
      expect(
        parseAvdList(output),
        ['Pixel_10_Pro_Fold', 'SaringSMS_Test', 'pixel_7_-_api_36_0'],
      );
    });

    test('menerima pemisah baris Windows', () {
      expect(parseAvdList('Satu\r\nDua\r\n'), ['Satu', 'Dua']);
    });

    test('hasil kosong jika hanya log', () {
      expect(parseAvdList('INFO | starting\n'), isEmpty);
    });
  });

  group('parseAdbDevices', () {
    test('hasil kosong jika tidak ada perangkat', () {
      const output = '''
List of devices attached

''';
      expect(parseAdbDevices(output), isEmpty);
    });

    test('mengabaikan pesan daemon dan membaca emulator serta perangkat fisik', () {
      const output = '''
* daemon not running; starting now at tcp:5037
* daemon started successfully
List of devices attached
emulator-5554	device
emulator-5556	offline
R58M123ABC	device
''';
      final devices = parseAdbDevices(output);
      expect(devices.map((d) => d.serial).toList(), [
        'emulator-5554',
        'emulator-5556',
        'R58M123ABC',
      ]);
      expect(devices.map((d) => d.state).toList(), ['device', 'offline', 'device']);
      expect(devices[0].isEmulator, isTrue);
      expect(devices[2].isEmulator, isFalse);
    });

    test('membaca keluaran adb devices -l', () {
      const output = '''
List of devices attached
emulator-5554          device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64xa transport_id:1
adb: warning ignored
''';
      final devices = parseAdbDevices(output);
      expect(devices, hasLength(1));
      expect(devices.single.serial, 'emulator-5554');
      expect(devices.single.state, 'device');
      expect(devices.single.model, 'sdk_gphone64_x86_64');
      expect(devices.single.extras['transport_id'], '1');
    });
  });

  group('parseEmulatorAvdName', () {
    test('membaca nama AVD dan mengabaikan OK', () {
      expect(parseEmulatorAvdName('Pixel_7_API_34\r\nOK\r\n'), 'Pixel_7_API_34');
      expect(parseEmulatorAvdName('OK\n'), isNull);
      expect(parseEmulatorAvdName('KO: unknown command\n'), isNull);
    });
  });
}
