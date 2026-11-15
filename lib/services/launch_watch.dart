/// Outcomes after waiting for an emulator to appear in adb.
class AdbWatchAssessment {
  const AdbWatchAssessment({this.statusMessage, this.errorMessage});

  final String? statusMessage;
  final String? errorMessage;

  bool get isError => errorMessage != null && errorMessage!.isNotEmpty;
}

/// Interprets the 2-minute adb wait. A visible emulator window is not a failure
/// even if adb has not listed the device yet (VPN/localhost/adb-server issues).
AdbWatchAssessment assessAdbWatchTimeout({
  required bool processAlive,
  required bool windowVisible,
  required bool adbHasEmulator,
  required bool adbPortOpen,
  required String logPath,
  String? displayTitle,
}) {
  if (adbHasEmulator) {
    final title = (displayTitle == null || displayTitle.trim().isEmpty)
        ? 'Emulator'
        : displayTitle.trim();
    return AdbWatchAssessment(
      statusMessage:
          '$title terdeteksi di adb, tetapi boot belum selesai dalam 2 menit. Log: $logPath',
    );
  }
  if (!processAlive) {
    return AdbWatchAssessment(
      errorMessage: 'Emulator berhenti sebelum tampil di adb.\nLog: $logPath',
    );
  }
  if (windowVisible || adbPortOpen) {
    final windowBit = windowVisible ? ' (jendela terlihat)' : '';
    final portBit = adbPortOpen ? ' dan port 5554/5555 terbuka' : '';
    return AdbWatchAssessment(
      statusMessage:
          'Emulator masih berjalan$windowBit$portBit, tetapi adb belum terhubung. '
          'Ini belum tentu gagal. Server ADB sudah dicoba dinyalakan ulang sekali. '
          'Jika VPN (misalnya GlobalProtect) aktif, itu dapat memutus koneksi localhost ke emulator. '
          'Coba matikan VPN, lalu nyalakan ulang ADB, atau jalankan: adb connect 127.0.0.1:5555\n'
          'Log: $logPath',
    );
  }
  return AdbWatchAssessment(
    errorMessage:
        'Proses emulator masih berjalan, tetapi jendela perangkat tidak muncul dan adb tidak melihatnya '
        '(port 5554/5555 tidak terbuka). Prosesnya mungkin macet saat start. Lihat log. '
        'Hentikan proses itu secara manual jika perlu, lalu coba Mulai lagi.\n'
        'Log: $logPath',
  );
}

bool netstatHasListeningPort(String netstatOutput, int port) {
  final pattern = RegExp(':$port(?=\\s|\$)');
  for (final raw in netstatOutput.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final upper = line.toUpperCase();
    if (!upper.contains('LISTEN')) continue;
    if (pattern.hasMatch(line)) return true;
  }
  return false;
}

bool parseAdbConnectSuccess(String output) {
  final text = output.toLowerCase();
  if (text.contains('cannot connect') ||
      text.contains('failed to connect') ||
      text.contains('connection refused') ||
      text.contains('unable to connect')) {
    return false;
  }
  return text.contains('connected to') || text.contains('already connected');
}
