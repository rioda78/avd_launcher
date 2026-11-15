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

abstract class ProcessRunner {
  Future<ProcessCommandResult> run(
    String executable,
    List<String> arguments, {
    Duration? timeout,
    Map<String, String>? environment,
  });

  Future<void> startDetached(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });
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
  Future<void> startDetached(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      mode: ProcessStartMode.detached,
      runInShell: false,
    );
  }
}
