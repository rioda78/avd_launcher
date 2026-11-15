import 'dart:async';
import 'dart:io';

import 'launch_watch.dart';
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

  /// True if [pid] or a child process has a visible top-level window.
  Future<bool> processTreeHasVisibleWindow(int pid);

  /// True if a local TCP port is in LISTENING state (from netstat).
  Future<bool> isLocalPortListening(int port);
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
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        includeParentEnvironment: true,
        runInShell: runInShell,
      );
      await process.stdin.close();
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      final stdoutSub = process.stdout
          .transform(const SystemEncoding().decoder)
          .listen(stdoutBuffer.write, onError: (_) {});
      final stderrSub = process.stderr
          .transform(const SystemEncoding().decoder)
          .listen(stderrBuffer.write, onError: (_) {});
      late final int exitCode;
      try {
        if (timeout == null) {
          exitCode = await process.exitCode;
        } else {
          exitCode = await process.exitCode.timeout(
            timeout,
            onTimeout: () {
              process.kill();
              throw TimeoutException(
                'Perintah melebihi batas waktu (${timeout.inSeconds} dtk): $executable',
                timeout,
              );
            },
          );
        }
        // Give streams a brief moment to flush remaining buffered bytes,
        // without blocking if a background child (like adb daemon) inherited
        // the stdout/stderr pipe handles.
        await Future<void>.delayed(const Duration(milliseconds: 50));
      } finally {
        await stdoutSub.cancel();
        await stderrSub.cancel();
      }
      return ProcessCommandResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.toString(),
        stderr: stderrBuffer.toString(),
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

  @override
  Future<bool> processTreeHasVisibleWindow(int pid) async {
    if (pid <= 0 || !Platform.isWindows) return false;
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$root = $pid
\$ids = @(\$root)
\$i = 0
while (\$i -lt \$ids.Count) {
  Get-CimInstance Win32_Process -Filter "ParentProcessId=\$(\$ids[\$i])" | ForEach-Object {
    if (\$ids -notcontains \$_.ProcessId) { \$ids += \$_.ProcessId }
  }
  \$i++
}
\$titles = Get-Process -Id \$ids | Where-Object { \$_.MainWindowTitle -and \$_.MainWindowTitle.Trim() }
if (\$titles) { \$titles[0].MainWindowTitle }
''';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      stdoutEncoding: const SystemEncoding(),
      stderrEncoding: const SystemEncoding(),
    );
    return result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
  }

  @override
  Future<bool> isLocalPortListening(int port) async {
    if (port <= 0) return false;
    if (Platform.isWindows) {
      final result = await Process.run(
        'netstat',
        ['-ano'],
        stdoutEncoding: const SystemEncoding(),
        stderrEncoding: const SystemEncoding(),
      );
      final out = result.stdout is String
          ? result.stdout as String
          : result.stdout.toString();
      return netstatHasListeningPort(out, port);
    }
    final result = await Process.run('ss', ['-lnt']);
    var out = result.stdout.toString();
    if (out.contains(':$port ')) return true;
    final fallback = await Process.run('netstat', ['-lnt']);
    return fallback.stdout.toString().contains(':$port ');
  }
}
