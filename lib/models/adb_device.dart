class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.extras = const {},
  });

  final String serial;
  final String state;
  final Map<String, String> extras;

  bool get isEmulator => serial.startsWith('emulator-');

  String? get model => extras['model'];

  String get displayLabel {
    final parts = <String>[serial, state];
    final m = model;
    if (m != null && m.isNotEmpty) {
      parts.add(m);
    }
    return parts.join('  ·  ');
  }

  @override
  String toString() => 'AdbDevice($serial, $state, $extras)';

  @override
  bool operator ==(Object other) =>
      other is AdbDevice &&
      other.serial == serial &&
      other.state == state &&
      _mapEquals(other.extras, extras);

  @override
  int get hashCode => Object.hash(serial, state, Object.hashAll(extras.entries));
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
