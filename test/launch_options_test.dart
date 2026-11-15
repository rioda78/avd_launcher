import 'package:avd_launcher/services/avd_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('argumen default hanya -avd dan nama', () {
    expect(
      const LaunchOptions().toArgs('Pixel_10_Pro_Fold'),
      ['-avd', 'Pixel_10_Pro_Fold'],
    );
  });

  test('menggabungkan opsi cold boot, wipe data, dan tanpa audio', () {
    expect(
      const LaunchOptions(coldBoot: true, wipeData: true, noAudio: true)
          .toArgs('SaringSMS_Test'),
      ['-avd', 'SaringSMS_Test', '-no-snapshot-load', '-wipe-data', '-no-audio'],
    );
  });

  test('menambahkan -gpu jika mode dipilih', () {
    expect(
      const LaunchOptions(gpuMode: 'swiftshader_indirect').toArgs('Pixel_10_Pro_Fold'),
      ['-avd', 'Pixel_10_Pro_Fold', '-gpu', 'swiftshader_indirect'],
    );
    expect(
      const LaunchOptions(gpuMode: 'default').toArgs('Pixel_10_Pro_Fold'),
      ['-avd', 'Pixel_10_Pro_Fold'],
    );
    expect(
      const LaunchOptions(gpuMode: 'auto').toArgs('Fold'),
      ['-avd', 'Fold', '-gpu', 'auto'],
    );
  });
}
