import 'dart:io';

class ProcessCommandResult {
  const ProcessCommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class SpawnedProcess {
  const SpawnedProcess({
    required this.pid,
    required this.stdout,
    required this.stderr,
  });

  final int pid;
  final Stream<List<int>> stdout;
  final Stream<List<int>> stderr;
}

abstract class ProcessRunner {
  Future<ProcessCommandResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
    Map<String, String>? environment,
  });

  Future<SpawnedProcess> startDetachedWithStdio(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  Future<bool> isProcessRunning(int pid);
}

class RealProcessRunner implements ProcessRunner {
  const RealProcessRunner();

  @override
  Future<ProcessCommandResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
    Map<String, String>? environment,
  }) async {
    final future = Process.run(
      executable,
      arguments,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
      stdoutEncoding: const SystemEncoding(),
      stderrEncoding: const SystemEncoding(),
    );
    final result = timeout == null ? await future : await future.timeout(timeout);
    return ProcessCommandResult(
      exitCode: result.exitCode,
      stdout: result.stdout is String ? result.stdout as String : result.stdout.toString(),
      stderr: result.stderr is String ? result.stderr as String : result.stderr.toString(),
    );
  }

  @override
  Future<SpawnedProcess> startDetachedWithStdio(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      mode: ProcessStartMode.detachedWithStdio,
      runInShell: false,
    );
    return SpawnedProcess(
      pid: process.pid,
      stdout: process.stdout,
      stderr: process.stderr,
    );
  }

  @override
  Future<bool> isProcessRunning(int pid) async {
    if (pid <= 0) return false;
    if (Platform.isWindows) {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      final out = result.stdout is String ? result.stdout as String : result.stdout.toString();
      return out.contains('"$pid"');
    }
    final result = await Process.run('ps', ['-p', '$pid', '-o', 'pid=']);
    return result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
  }
}
