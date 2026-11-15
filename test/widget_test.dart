import 'package:avd_launcher/app.dart';
import 'package:avd_launcher/services/avd_service.dart';
import 'package:avd_launcher/services/sdk_locator.dart';
import 'package:avd_launcher/services/settings_store.dart';
import 'package:avd_launcher/ui/launcher_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('menampilkan judul, Mulai, Edit AVD, dan Buat AVD baru', (tester) async {
    final controller = LauncherController(
      settingsStore: SettingsStore(filePath: 'settings-test-unused.json'),
      service: AvdService(),
      locator: SdkLocator(pathExists: (_) => false, environment: const {}),
    );
    await tester.pumpWidget(AvdLauncherApp(controller: controller));
    expect(find.text('AVD Launcher'), findsOneWidget);
    expect(find.text('Mulai'), findsOneWidget);
    expect(find.text('Deteksi otomatis'), findsOneWidget);
    expect(find.text('Edit AVD'), findsOneWidget);
    expect(find.text('Hapus AVD'), findsOneWidget);
    expect(find.text('Buat AVD baru'), findsOneWidget);
    expect(find.text('Mode GPU saat dijalankan'), findsOneWidget);
  });
}
