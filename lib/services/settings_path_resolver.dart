import 'package:path/path.dart' as p;

class SettingsCandidate {
  const SettingsCandidate(this.directory, this.label);

  final String directory;
  final String label;

  String get filePath => p.join(directory, 'settings.json');
}

class ResolvedSettingsPath {
  const ResolvedSettingsPath({
    required this.directory,
    required this.filePath,
    required this.label,
  });

  final String directory;
  final String filePath;
  final String label;
}

/// Chooses a settings.json location from an ordered list of candidates.
///
/// [writeCandidates] are tried in order until one is writable.
/// [loadCandidates] are scanned in order for an existing settings.json.
class SettingsPathResolver {
  SettingsPathResolver({
    required this.writeCandidates,
    required this.loadCandidates,
    required this.canWriteDirectory,
    required this.fileExists,
  });

  final List<SettingsCandidate> writeCandidates;
  final List<SettingsCandidate> loadCandidates;
  final Future<bool> Function(String directory) canWriteDirectory;
  final bool Function(String path) fileExists;

  static List<SettingsCandidate> uniqueCandidates(List<SettingsCandidate> input) {
    final seen = <String>{};
    final result = <SettingsCandidate>[];
    for (final candidate in input) {
      final directory = candidate.directory.trim();
      if (directory.isEmpty) continue;
      final key = p.normalize(directory).toLowerCase();
      if (!seen.add(key)) continue;
      result.add(SettingsCandidate(directory, candidate.label));
    }
    return result;
  }

  ResolvedSettingsPath? existingLoadPath() {
    for (final candidate in uniqueCandidates(loadCandidates)) {
      if (fileExists(candidate.filePath)) {
        return ResolvedSettingsPath(
          directory: candidate.directory,
          filePath: candidate.filePath,
          label: candidate.label,
        );
      }
    }
    return null;
  }

  Future<ResolvedSettingsPath?> firstWritable() async {
    for (final candidate in uniqueCandidates(writeCandidates)) {
      if (await canWriteDirectory(candidate.directory)) {
        return ResolvedSettingsPath(
          directory: candidate.directory,
          filePath: candidate.filePath,
          label: candidate.label,
        );
      }
    }
    return null;
  }

  List<String> get writeDirectories =>
      uniqueCandidates(writeCandidates).map((c) => c.directory).toList();
}
