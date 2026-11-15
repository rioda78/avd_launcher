import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';

const _createNoWindow = 0x08000000;
const _createUnicodeEnvironment = 0x00000400;
const _createNewProcessGroup = 0x00000200;
const _createBreakawayFromJob = 0x01000000;
const _startfUseStdHandles = 0x00000100;
const _genericRead = 0x80000000;
const _genericWrite = 0x40000000;
const _fileShareRead = 0x00000001;
const _fileShareWrite = 0x00000002;
const _fileShareDelete = 0x00000004;
const _openAlways = 4;
const _openExisting = 3;
const _fileAttributeNormal = 0x00000080;
const _fileAppendData = 0x0004;
const _synchronize = 0x00100000;
const _invalidHandleValue = -1;
const _formatMessageFromSystem = 0x00001000;
const _formatMessageIgnoreInserts = 0x00000200;
const _fileEnd = 2;

DynamicLibrary get _kernel32 =>
    _kernel32Lib ??= DynamicLibrary.open('kernel32.dll');
DynamicLibrary? _kernel32Lib;

final _createProcessW = _kernel32.lookupFunction<
    Int32 Function(
      Pointer<Utf16> appName,
      Pointer<Utf16> commandLine,
      Pointer<Void> processAttrs,
      Pointer<Void> threadAttrs,
      Int32 inheritHandles,
      Uint32 creationFlags,
      Pointer<Void> environment,
      Pointer<Utf16> currentDirectory,
      Pointer<_StartupInfoW> startupInfo,
      Pointer<_ProcessInformation> processInformation,
    ),
    int Function(
      Pointer<Utf16> appName,
      Pointer<Utf16> commandLine,
      Pointer<Void> processAttrs,
      Pointer<Void> threadAttrs,
      int inheritHandles,
      int creationFlags,
      Pointer<Void> environment,
      Pointer<Utf16> currentDirectory,
      Pointer<_StartupInfoW> startupInfo,
      Pointer<_ProcessInformation> processInformation,
    )>('CreateProcessW');

final _createFileW = _kernel32.lookupFunction<
    IntPtr Function(
      Pointer<Utf16> fileName,
      Uint32 desiredAccess,
      Uint32 shareMode,
      Pointer<_SecurityAttributes> securityAttributes,
      Uint32 creationDisposition,
      Uint32 flagsAndAttributes,
      IntPtr templateFile,
    ),
    int Function(
      Pointer<Utf16> fileName,
      int desiredAccess,
      int shareMode,
      Pointer<_SecurityAttributes> securityAttributes,
      int creationDisposition,
      int flagsAndAttributes,
      int templateFile,
    )>('CreateFileW');

final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr handle), int Function(int handle)>(
      'CloseHandle',
    );

final _getLastError = _kernel32.lookupFunction<Uint32 Function(), int Function()>(
  'GetLastError',
);

final _formatMessageW = _kernel32.lookupFunction<
    Uint32 Function(
      Uint32 flags,
      Pointer<Void> source,
      Uint32 messageId,
      Uint32 languageId,
      Pointer<Utf16> buffer,
      Uint32 size,
      Pointer<Void> arguments,
    ),
    int Function(
      int flags,
      Pointer<Void> source,
      int messageId,
      int languageId,
      Pointer<Utf16> buffer,
      int size,
      Pointer<Void> arguments,
    )>('FormatMessageW');

final _setFilePointerEx = _kernel32.lookupFunction<
    Int32 Function(IntPtr file, Int64 distance, Pointer<Int64> newPointer, Uint32 moveMethod),
    int Function(int file, int distance, Pointer<Int64> newPointer, int moveMethod)>(
  'SetFilePointerEx',
);

base class _StartupInfoW extends Struct {
  @Uint32()
  external int cb;
  @Uint32()
  external int pad0;
  external Pointer<Utf16> lpReserved;
  external Pointer<Utf16> lpDesktop;
  external Pointer<Utf16> lpTitle;
  @Uint32()
  external int dwX;
  @Uint32()
  external int dwY;
  @Uint32()
  external int dwXSize;
  @Uint32()
  external int dwYSize;
  @Uint32()
  external int dwXCountChars;
  @Uint32()
  external int dwYCountChars;
  @Uint32()
  external int dwFillAttribute;
  @Uint32()
  external int dwFlags;
  @Uint16()
  external int wShowWindow;
  @Uint16()
  external int cbReserved2;
  @Uint32()
  external int pad1;
  external Pointer<Uint8> lpReserved2;
  @IntPtr()
  external int hStdInput;
  @IntPtr()
  external int hStdOutput;
  @IntPtr()
  external int hStdError;
}

base class _ProcessInformation extends Struct {
  @IntPtr()
  external int hProcess;
  @IntPtr()
  external int hThread;
  @Uint32()
  external int dwProcessId;
  @Uint32()
  external int dwThreadId;
}

base class _SecurityAttributes extends Struct {
  @Uint32()
  external int nLength;
  @Uint32()
  external int pad0;
  external Pointer<Void> lpSecurityDescriptor;
  @Int32()
  external int bInheritHandle;
  @Uint32()
  external int pad1;
}

/// Starts [executable] with no visible console window, redirecting stdout and
/// stderr to [logPath] and stdin to NUL. The process is not tied to this one.
///
/// Does not use SW_HIDE, so a GUI window (the emulator display) can still appear.
Future<int> startWindowsHiddenProcess({
  required String executable,
  required List<String> arguments,
  String? workingDirectory,
  Map<String, String>? environment,
  required String logPath,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError('startWindowsHiddenProcess hanya untuk Windows.');
  }

  final command = windowsCommandLine(executable, arguments);
  final envMap = _mergeCaseInsensitiveEnvironment(
    Platform.environment,
    environment ?? const {},
  );

  final appPtr = executable.toNativeUtf16();
  final cmdPtr = command.toNativeUtf16();
  final dirPtr = (workingDirectory == null || workingDirectory.isEmpty)
      ? nullptr
      : workingDirectory.toNativeUtf16();
  final envPtr = _environmentBlock(envMap);
  final startup = calloc<_StartupInfoW>();
  final processInfo = calloc<_ProcessInformation>();
  final sa = calloc<_SecurityAttributes>();
  final logName = logPath.toNativeUtf16();
  final nulName = r'\\.\NUL'.toNativeUtf16();

  var stdinHandle = _invalidHandleValue;
  var logHandle = _invalidHandleValue;
  var processHandle = 0;
  var threadHandle = 0;

  try {
    sa.ref
      ..nLength = sizeOf<_SecurityAttributes>()
      ..lpSecurityDescriptor = nullptr
      ..bInheritHandle = 1;

    stdinHandle = _createFileW(
      nulName,
      _genericRead,
      _fileShareRead | _fileShareWrite,
      sa,
      _openExisting,
      _fileAttributeNormal,
      0,
    );
    if (stdinHandle == _invalidHandleValue || stdinHandle == 0) {
      throw ProcessException(
        executable,
        arguments,
        'Gagal membuka NUL sebagai stdin: ${_lastErrorMessage()}',
        _getLastError(),
      );
    }

    logHandle = _createFileW(
      logName,
      _fileAppendData | _synchronize | _genericWrite,
      _fileShareRead | _fileShareWrite | _fileShareDelete,
      sa,
      _openAlways,
      _fileAttributeNormal,
      0,
    );
    if (logHandle == _invalidHandleValue || logHandle == 0) {
      throw ProcessException(
        executable,
        arguments,
        'Gagal membuka log emulator ($logPath): ${_lastErrorMessage()}',
        _getLastError(),
      );
    }
    _setFilePointerEx(logHandle, 0, nullptr, _fileEnd);

    startup.ref
      ..cb = sizeOf<_StartupInfoW>()
      ..dwFlags = _startfUseStdHandles
      ..hStdInput = stdinHandle
      ..hStdOutput = logHandle
      ..hStdError = logHandle;

    final flags = _createNoWindow | _createUnicodeEnvironment | _createNewProcessGroup | _createBreakawayFromJob;
    var ok = _createProcessW(
      appPtr,
      cmdPtr,
      nullptr,
      nullptr,
      1,
      flags,
      envPtr.cast(),
      dirPtr,
      startup,
      processInfo,
    );
    if (ok == 0) {
      // Some job objects do not allow breakaway; retry without that flag.
      ok = _createProcessW(
        appPtr,
        cmdPtr,
        nullptr,
        nullptr,
        1,
        _createNoWindow | _createUnicodeEnvironment | _createNewProcessGroup,
        envPtr.cast(),
        dirPtr,
        startup,
        processInfo,
      );
    }
    if (ok == 0) {
      throw ProcessException(
        executable,
        arguments,
        'CreateProcess gagal: ${_lastErrorMessage()}',
        _getLastError(),
      );
    }

    processHandle = processInfo.ref.hProcess;
    threadHandle = processInfo.ref.hThread;
    return processInfo.ref.dwProcessId;
  } finally {
    if (stdinHandle != _invalidHandleValue && stdinHandle != 0) {
      _closeHandle(stdinHandle);
    }
    if (logHandle != _invalidHandleValue && logHandle != 0) {
      _closeHandle(logHandle);
    }
    if (processHandle != 0) _closeHandle(processHandle);
    if (threadHandle != 0) _closeHandle(threadHandle);
    calloc.free(appPtr);
    calloc.free(cmdPtr);
    if (dirPtr != nullptr) calloc.free(dirPtr);
    calloc.free(envPtr);
    calloc.free(startup);
    calloc.free(processInfo);
    calloc.free(sa);
    calloc.free(logName);
    calloc.free(nulName);
  }
}

String windowsCommandLine(String executable, List<String> arguments) {
  return [quoteWindowsArg(executable), ...arguments.map(quoteWindowsArg)].join(' ');
}

String quoteWindowsArg(String argument) {
  if (argument.isEmpty) return '""';
  final needsQuotes = argument.contains(RegExp(r'[\s"]'));
  if (!needsQuotes) return argument;

  final buffer = StringBuffer('"');
  var backslashes = 0;
  for (final unit in argument.codeUnits) {
    if (unit == 0x5c) {
      backslashes++;
      continue;
    }
    if (unit == 0x22) {
      buffer
        ..write(r'\' * (backslashes * 2 + 1))
        ..write('"');
      backslashes = 0;
      continue;
    }
    if (backslashes > 0) {
      buffer.write(r'\' * backslashes);
      backslashes = 0;
    }
    buffer.writeCharCode(unit);
  }
  buffer
    ..write(r'\' * (backslashes * 2))
    ..write('"');
  return buffer.toString();
}

Map<String, String> _mergeCaseInsensitiveEnvironment(
  Map<String, String> base,
  Map<String, String> overrides,
) {
  final result = <String, String>{};
  final keyByUpper = <String, String>{};
  for (final entry in base.entries) {
    if (entry.key.isEmpty) continue;
    final upper = entry.key.toUpperCase();
    final existingKey = keyByUpper[upper];
    if (existingKey != null) {
      result.remove(existingKey);
    }
    keyByUpper[upper] = entry.key;
    result[entry.key] = entry.value;
  }
  for (final entry in overrides.entries) {
    if (entry.key.isEmpty) continue;
    final upper = entry.key.toUpperCase();
    final existingKey = keyByUpper[upper];
    if (existingKey != null) {
      result.remove(existingKey);
    }
    keyByUpper[upper] = entry.key;
    result[entry.key] = entry.value;
  }
  return result;
}

Pointer<Utf16> _environmentBlock(Map<String, String> environment) {
  final sortedEntries = environment.entries
      .where((entry) => entry.key.isNotEmpty)
      .toList()
    ..sort(
      (a, b) => a.key.toUpperCase().compareTo(b.key.toUpperCase()),
    );
  final entries = sortedEntries
      .map((entry) => '${entry.key}=${entry.value}')
      .toList();
  final text = '${entries.join('\u0000')}\u0000\u0000';
  final units = text.codeUnits;
  final ptr = calloc<Uint16>(units.length);
  for (var i = 0; i < units.length; i++) {
    ptr[i] = units[i];
  }
  return ptr.cast();
}

String _lastErrorMessage() {
  final code = _getLastError();
  final buffer = calloc<Uint16>(512).cast<Utf16>();
  try {
    final length = _formatMessageW(
      _formatMessageFromSystem | _formatMessageIgnoreInserts,
      nullptr,
      code,
      0,
      buffer,
      512,
      nullptr,
    );
    if (length == 0) return 'kode $code';
    return 'kode $code, ${buffer.toDartString(length: min(length, 512)).trim()}';
  } finally {
    calloc.free(buffer);
  }
}
