import 'package:avd_launcher/services/settings_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  const support = SettingsCandidate(r'C:\Users\x\AppData\Roaming\id.rioda\AVD Launcher', 'direktori dukungan aplikasi');
  const local = SettingsCandidate(r'C:\Users\x\AppData\Local\AVD Launcher', r'%LOCALAPPDATA%\AVD Launcher');
  const portable = SettingsCandidate(r'E:\proyek\avd_launcher\build\Release', 'folder aplikasi (portabel)');
  const legacy = SettingsCandidate(r'C:\Users\x\AppData\Roaming\AVD Launcher', r'%APPDATA%\AVD Launcher');

  SettingsPathResolver resolver({
    Set<String> writable = const {},
    Set<String> existingFiles = const {},
    List<SettingsCandidate>? write,
    List<SettingsCandidate>? load,
  }) {
    return SettingsPathResolver(
      writeCandidates: write ?? [support, local, portable],
      loadCandidates: load ?? [support, legacy, local, portable],
      canWriteDirectory: (directory) async => writable.contains(directory),
      fileExists: existingFiles.contains,
    );
  }

  test('firstWritable memilih kandidat pertama yang dapat ditulisi', () async {
    final chosen = await resolver(writable: {local.directory, portable.directory}).firstWritable();
    expect(chosen, isNotNull);
    expect(chosen!.directory, local.directory);
    expect(chosen.filePath, p.join(local.directory, 'settings.json'));
    expect(chosen.label, r'%LOCALAPPDATA%\AVD Launcher');
  });

  test('firstWritable melewati lokasi yang ditolak dan memakai folder portabel', () async {
    final chosen = await resolver(writable: {portable.directory}).firstWritable();
    expect(chosen!.directory, portable.directory);
    expect(chosen.label, 'folder aplikasi (portabel)');
  });

  test('firstWritable mengembalikan null jika semua lokasi gagal', () async {
    expect(await resolver(writable: {}).firstWritable(), isNull);
  });

  test('existingLoadPath memakai file yang ada meskipun prioritasnya lebih rendah', () {
    final path = resolver(
      existingFiles: {p.join(portable.directory, 'settings.json')},
    ).existingLoadPath();
    expect(path!.filePath, p.join(portable.directory, 'settings.json'));
    expect(path.label, 'folder aplikasi (portabel)');
  });

  test('existingLoadPath lebih memilih kandidat dengan prioritas lebih tinggi', () {
    final path = resolver(
      existingFiles: {
        p.join(legacy.directory, 'settings.json'),
        p.join(portable.directory, 'settings.json'),
      },
    ).existingLoadPath();
    expect(path!.directory, legacy.directory);
  });

  test('existingLoadPath mengembalikan null jika belum ada berkas', () {
    expect(resolver().existingLoadPath(), isNull);
  });

  test('uniqueCandidates menghapus path kosong dan duplikat', () {
    final unique = SettingsPathResolver.uniqueCandidates([
      const SettingsCandidate('  ', 'kosong'),
      local,
      SettingsCandidate(r'C:\Users\x\AppData\Local\AVD Launcher\', 'duplikat'),
      portable,
    ]);
    expect(unique.map((c) => c.directory).toList(), [local.directory, portable.directory]);
  });
}
