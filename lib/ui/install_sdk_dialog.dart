import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/sdk_installer.dart';
import 'launcher_controller.dart';

Future<void> showInstallSdkDialog(
  BuildContext context,
  LauncherController controller,
) async {
  final installed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => InstallSdkDialog(controller: controller),
  );
  if (installed == true && context.mounted) {
    final text = controller.statusMessage ?? 'Android SDK berhasil dipasang.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

class InstallSdkDialog extends StatefulWidget {
  const InstallSdkDialog({super.key, required this.controller});

  final LauncherController controller;

  @override
  State<InstallSdkDialog> createState() => _InstallSdkDialogState();
}

class _InstallSdkDialogState extends State<InstallSdkDialog> {
  late final TextEditingController _targetDir;
  bool _installPlatformTools = true;
  bool _installEmulator = true;
  bool _installSystemImage = true;
  String _systemImage = SdkInstaller.kRecommendedSystemImages.first;
  bool _running = false;
  String _progressText = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _targetDir = TextEditingController(
      text: widget.controller.defaultSdkInstallRoot,
    );
  }

  @override
  void dispose() {
    _targetDir.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Unduh & Pasang Android SDK Otomatis'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Aplikasi akan mengunduh Android Command-line Tools resmi dari Google, '
                'menyetujui lisensi SDK, dan memasang komponen yang dipilih di bawah ini.',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _targetDir,
                      enabled: !_running,
                      decoration: const InputDecoration(
                        labelText: 'Folder tujuan instalasi SDK',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Pilih folder tujuan',
                    onPressed: _running ? null : _pickFolder,
                    icon: const Icon(Icons.folder_open),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _installPlatformTools,
                onChanged: _running
                    ? null
                    : (v) => setState(() => _installPlatformTools = v ?? true),
                title: const Text('Platform-Tools (adb.exe)'),
                subtitle: const Text('Wajib untuk mendeteksi dan mengendalikan perangkat'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _installEmulator,
                onChanged: _running
                    ? null
                    : (v) => setState(() => _installEmulator = v ?? true),
                title: const Text('Android Emulator (emulator.exe)'),
                subtitle: const Text('Wajib untuk menjalankan virtual device'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              CheckboxListTile(
                value: _installSystemImage,
                onChanged: _running
                    ? null
                    : (v) => setState(() => _installSystemImage = v ?? false),
                title: const Text('System Image & Platform Android'),
                subtitle: const Text('Diperlukan untuk membuat dan menyalakan AVD baru'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              if (_installSystemImage) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _systemImage,
                  decoration: const InputDecoration(
                    labelText: 'Pilih System Image',
                    border: OutlineInputBorder(),
                  ),
                  isExpanded: true,
                  items: [
                    for (final id in SdkInstaller.kRecommendedSystemImages)
                      DropdownMenuItem(
                        value: id,
                        child: Text(id, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _running
                      ? null
                      : (v) {
                          if (v != null) setState(() => _systemImage = v);
                        },
                ),
              ],
              if (_running) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  _progressText.isEmpty ? 'Memulai…' : _progressText,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _running ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton.icon(
          onPressed: _running ? null : _startInstall,
          icon: _running
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download),
          label: Text(_running ? 'Memasang…' : 'Unduh & Pasang'),
        ),
      ],
    );
  }

  Future<void> _pickFolder() async {
    final current = _targetDir.text.trim();
    final chosen = await getDirectoryPath(
      confirmButtonText: 'Pilih',
      initialDirectory: current.isNotEmpty ? current : null,
    );
    if (chosen != null && mounted) {
      setState(() => _targetDir.text = chosen);
    }
  }

  Future<void> _startInstall() async {
    setState(() {
      _running = true;
      _error = null;
      _progressText = 'Menyiapkan pengunduhan…';
    });
    try {
      await widget.controller.downloadAndInstallSdk(
        config: SdkSetupConfig(
          targetRoot: _targetDir.text,
          installPlatformTools: _installPlatformTools,
          installEmulator: _installEmulator,
          installSystemImage: _installSystemImage,
          systemImagePackage: _systemImage,
        ),
        onProgress: (msg) {
          if (mounted) {
            setState(() => _progressText = msg);
          }
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _running = false;
          _error = error.toString();
        });
      }
    }
  }
}
