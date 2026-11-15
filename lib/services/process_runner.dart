import 'dart:async';
import 'dart:io';

import 'windows_hidden_process.dart';

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
    String? workingDirectory,
    bool runInShell = false,
    String? stdin,
  });

  Future<SpawnedProcess> startDetachedWithStdio(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  });

  /// Starts a process that outlives this app, without a visible console.
  /// stdout/stderr are appended to [logPath]; stdin is NUL on Windows.
  Future<int> startDetachedHidden(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required String logPath,
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
    String? workingDirectory,
    bool runInShell = false,
    String? stdin,
  }) async {
    if (stdin == null) {
      final future = Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: true,
        runInShell: runInShell,
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

    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: runInShell,
    );
    process.stdin.write(stdin);
    if (!stdin.endsWith('\n')) {
      process.stdin.writeln();
    }
    await process.stdin.close();
    final stdoutFuture = process.stdout.transform(const SystemEncoding().decoder).join();
    final stderrFuture = process.stderr.transform(const SystemEncoding().decoder).join();
    final exitFuture = process.exitCode;
    late final int exitCode;
    if (timeout == null) {
      exitCode = await exitFuture;
    } else {
      exitCode = await exitFuture.timeout(timeout);
    }
    return ProcessCommandResult(
      exitCode: exitCode,
      stdout: await stdoutFuture,
      stderr: await stderrFuture,
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
  Future<int> startDetachedHidden(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    required String logPath,
  }) async {
    if (Platform.isWindows) {
      return startWindowsHiddenProcess(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        logPath: logPath,
      );
    }

    final logFile = File(logPath);
    await logFile.parent.create(recursive: true);
    final sink = logFile.openWrite(mode: FileMode.append);
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: true,
      mode: ProcessStartMode.detachedWithStdio,
      runInShell: false,
    );
    process.stdout.listen(sink.add, onError: (_) {});
    process.stderr.listen(sink.add, onError: (_) {}, onDone: () => unawaited(sink.close()));
    return process.pid;
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
