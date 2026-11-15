class AdbDevice {
  const AdbDevice({
    required this.serial,
    required this.state,
    this.extras = const {},
    this.avdName,
  });

  final String serial;
  final String state;
  final Map<String, String> extras;
  final String? avdName;

  bool get isEmulator => serial.startsWith('emulator-');

  String? get model => extras['model'];

  AdbDevice copyWith({String? avdName}) {
    return AdbDevice(
      serial: serial,
      state: state,
      extras: extras,
      avdName: avdName ?? this.avdName,
    );
  }

  String get displayTitle {
    final name = avdName?.trim();
    if (name != null && name.isNotEmpty) {
      return '$name ($serial)';
    }
    return serial;
  }

  String get displayLabel {
    final parts = <String>[displayTitle, state];
    final m = model;
    if (m != null && m.isNotEmpty) {
      parts.add(m);
    }
    return parts.join('  ·  ');
  }

  @override
  String toString() => 'AdbDevice($serial, $state, avdName: $avdName, $extras)';

  @override
  bool operator ==(Object other) =>
      other is AdbDevice &&
      other.serial == serial &&
      other.state == state &&
      other.avdName == avdName &&
      _mapEquals(other.extras, extras);

  @override
  int get hashCode =>
      Object.hash(serial, state, avdName, Object.hashAll(extras.entries));
}

bool _mapEquals(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (b[e.key] != e.value) return false;
  }
  return true;
}
