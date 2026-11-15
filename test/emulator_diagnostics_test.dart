import 'package:avd_launcher/services/emulator_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseIniValue', () {
    test('membaca nilai dan mengabaikan komentar', () {
      const content = '# comment\n'
          'avd.ini.encoding=UTF-8\n'
          'path=E:\\Android\\avd\\pixel_7_-_api_36_0.avd\n'
          'image.sysdir.1=system-images\\android-36\\google_apis_playstore\\x86_64\\\n';
      expect(parseIniValue(content, 'path'), r'E:\Android\avd\pixel_7_-_api_36_0.avd');
      expect(
        parseIniValue(content, 'image.sysdir.1'),
        r'system-images\android-36\google_apis_playstore\x86_64\',
      );
      expect(parseIniValue(content, 'missing'), isNull);
    });
  });

  group('missingSystemImagePath', () {
    const avdHome = r'E:\Android\avd';
    const sdk = r'E:\Android\Sdk';
    const avdName = 'pixel_7_-_api_36_0';
    final files = <String, String>{
      p.join(avdHome, '$avdName.ini'):
          'path=$avdHome\\$avdName.avd\n',
      p.join(avdHome, '$avdName.avd', 'config.ini'):
          'image.sysdir.1=system-images\\android-36\\google_apis_playstore\\x86_64\\\n',
    };

    test('mengembalikan path image yang tidak ada', () {
      final missing = missingSystemImagePath(
        sdkRoot: sdk,
        avdName: avdName,
        avdHome: avdHome,
        directoryExists: (_) => false,
        readFileIfExists: (path) => files[path],
      );
      expect(
        missing,
        p.normalize(p.join(sdk, r'system-images\android-36\google_apis_playstore\x86_64\')),
      );
    });

    test('null jika direktori image ada', () {
      final image = p.normalize(
        p.join(sdk, r'system-images\android-36\google_apis_playstore\x86_64\'),
      );
      final missing = missingSystemImagePath(
        sdkRoot: sdk,
        avdName: avdName,
        avdHome: avdHome,
        directoryExists: (path) => path == image,
        readFileIfExists: (path) => files[path],
      );
      expect(missing, isNull);
    });
  });

  group('extractEmulatorFailure', () {
    test('mengambil baris FATAL dan peringatan system image', () {
      const log = 'INFO         | Android emulator version 37.2.13.0\n'
          'WARNING      | E:\\Android\\Sdk\\system-images\\android-36\\google_apis_playstore\\x86_64\\ is not a valid directory.\n'
          'WARNING      | emulator has searched the above paths but found no valid sdk root directory.\n'
          'FATAL        | Broken AVD system path. Check your ANDROID_SDK_ROOT value [E:\\Android\\Sdk]!\n';
      final extracted = extractEmulatorFailure(log);
      expect(extracted, contains('not a valid directory'));
      expect(extracted, contains('Broken AVD system path'));
    });

    test('null jika hanya log biasa', () {
      expect(extractEmulatorFailure('INFO | starting\n'), isNull);
    });
  });

  group('parseBootCompleted', () {
    test('true hanya jika ada baris 1', () {
      expect(parseBootCompleted('1\n'), isTrue);
      expect(parseBootCompleted('1\r\n'), isTrue);
      expect(parseBootCompleted('0\n'), isFalse);
      expect(parseBootCompleted(''), isFalse);
      expect(parseBootCompleted('error: closed\n'), isFalse);
    });
  });

  test('sanitizeForFileName mengganti karakter terlarang', () {
    expect(sanitizeForFileName(r'pixel_7:a/b'), 'pixel_7_a_b');
  });
}
