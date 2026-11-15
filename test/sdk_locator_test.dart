import 'package:avd_launcher/services/sdk_locator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('override manual dipakai jika emulator.exe ada', () {
    final existing = {
      r'E:\Android\Sdk\emulator\emulator.exe',
      r'E:\Android\Sdk\platform-tools\adb.exe',
    };
    final locator = SdkLocator(
      pathExists: existing.contains,
      environment: const {'ANDROID_HOME': r'C:\Other\Sdk'},
      localAppData: r'C:\Users\x\AppData\Local',
    );
    final sdk = locator.resolve(override: r'E:\Android\Sdk');
    expect(sdk.isUsable, isTrue);
    expect(sdk.root, r'E:\Android\Sdk');
    expect(sdk.source, 'pengaturan manual');
    expect(sdk.emulatorPath, r'E:\Android\Sdk\emulator\emulator.exe');
    expect(sdk.adbPath, r'E:\Android\Sdk\platform-tools\adb.exe');
  });

  test('override yang tidak valid tidak beralih diam-diam ke lokasi lain', () {
    final existing = {
      r'C:\Users\x\AppData\Local\Android\Sdk\emulator\emulator.exe',
      r'C:\Users\x\AppData\Local\Android\Sdk\platform-tools\adb.exe',
    };
    final locator = SdkLocator(
      pathExists: existing.contains,
      environment: const {'ANDROID_HOME': r'C:\Users\x\AppData\Local\Android\Sdk'},
      localAppData: r'C:\Users\x\AppData\Local',
    );
    final sdk = locator.resolve(override: r'D:\salah');
    expect(sdk.isUsable, isFalse);
    expect(sdk.source, 'pengaturan manual');
    expect(sdk.errorMessage, contains(r'D:\salah\emulator\emulator.exe'));
  });

  test('deteksi otomatis berurutan ANDROID_HOME lalu LOCALAPPDATA', () {
    final existing = {
      r'C:\Users\x\AppData\Local\Android\Sdk\emulator\emulator.exe',
      r'C:\Users\x\AppData\Local\Android\Sdk\platform-tools\adb.exe',
    };
    final locator = SdkLocator(
      pathExists: existing.contains,
      environment: const {'ANDROID_HOME': r'Z:\tidak-ada'},
      localAppData: r'C:\Users\x\AppData\Local',
    );
    final sdk = locator.resolve();
    expect(sdk.isUsable, isTrue);
    expect(sdk.source, r'%LOCALAPPDATA%\Android\Sdk');
    expect(sdk.root, r'C:\Users\x\AppData\Local\Android\Sdk');
  });

  test('emulator tanpa adb dilaporkan sebagai tidak lengkap', () {
    final locator = SdkLocator(
      pathExists: {r'E:\Android\Sdk\emulator\emulator.exe'}.contains,
      environment: const {'ANDROID_HOME': r'E:\Android\Sdk'},
    );
    final sdk = locator.resolve();
    expect(sdk.hasEmulator, isTrue);
    expect(sdk.hasAdb, isFalse);
    expect(sdk.isUsable, isFalse);
    expect(sdk.errorMessage, contains('adb.exe'));
  });
}
