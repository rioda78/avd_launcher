import 'package:flutter/material.dart';

import '../services/avd_config.dart';
import '../services/avd_service.dart';
import 'launcher_controller.dart';

Future<void> showEditAvdDialog(BuildContext context, LauncherController controller) async {
  try {
    if (controller.isSelectedAvdRunning()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('AVD sedang berjalan. Hentikan emulator dulu sebelum mengedit.'),
          ),
        );
      return;
    }
    final snapshot = controller.loadSelectedConfig();
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => EditAvdDialog(
        controller: controller,
        snapshot: snapshot,
      ),
    );
    if (saved == true && context.mounted) {
      final text = controller.statusMessage ?? 'Konfigurasi AVD disimpan.';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$error')));
  }
}

class EditAvdDialog extends StatefulWidget {
  const EditAvdDialog({
    super.key,
    required this.controller,
    required this.snapshot,
  });

  final LauncherController controller;
  final AvdConfigSnapshot snapshot;

  @override
  State<EditAvdDialog> createState() => _EditAvdDialogState();
}

class _EditAvdDialogState extends State<EditAvdDialog> {
  late final TextEditingController _ram;
  late final TextEditingController _storage;
  late final TextEditingController _cores;
  late String _gpuMode;
  late String? _imageSysdir;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final snap = widget.snapshot;
    _ram = TextEditingController(text: snap.ramSize);
    _storage = TextEditingController(text: snap.storageSize);
    _cores = TextEditingController(text: snap.cpuCores);
    _gpuMode = kGpuModes.contains(snap.gpuMode) ? snap.gpuMode : 'auto';
    _imageSysdir = snap.imageSysdir.isEmpty ? null : snap.imageSysdir;
  }

  @override
  void dispose() {
    _ram.dispose();
    _storage.dispose();
    _cores.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.snapshot;
    final items = _imageItems();
    return AlertDialog(
      title: Text('Edit AVD: ${snap.avdName}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (snap.currentImageMissing) ...[
                const Text(
                  'System image yang dipakai AVD ini tidak ditemukan di SDK. Pilih image yang sudah terpasang, atau pasang yang hilang dengan perintah di bawah. Perintah itu tidak dijalankan otomatis.',
                ),
                const SizedBox(height: 8),
                SelectableText(
                  sdkmanagerInstallCommand(snap.imageSysdir),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
              ],
              DropdownButtonFormField<String>(
                initialValue: items.any((item) => item.value == _imageSysdir) ? _imageSysdir : null,
                decoration: const InputDecoration(
                  labelText: 'System image',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: items,
                onChanged: (value) => setState(() => _imageSysdir = value),
              ),
              if (snap.currentImageMissing &&
                  _imageSysdir != null &&
                  _normalize(_imageSysdir!) == _normalize(snap.imageSysdir))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Image saat ini hilang. Pilih image terpasang sebelum menyimpan.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _ram,
                decoration: const InputDecoration(
                  labelText: 'RAM (MB)',
                  hintText: '2048',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _storage,
                decoration: const InputDecoration(
                  labelText: 'Penyimpanan internal',
                  hintText: '10G',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _gpuMode,
                decoration: const InputDecoration(
                  labelText: 'Mode GPU',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final mode in kGpuModes)
                    DropdownMenuItem(value: mode, child: Text(_gpuLabel(mode))),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _gpuMode = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cores,
                decoration: const InputDecoration(
                  labelText: 'Inti CPU',
                  hintText: '4',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }

  List<DropdownMenuItem<String>> _imageItems() {
    final items = <DropdownMenuItem<String>>[];
    final snap = widget.snapshot;
    if (snap.currentImageMissing && snap.imageSysdir.isNotEmpty) {
      items.add(
        DropdownMenuItem(
          value: snap.imageSysdir,
          enabled: false,
          child: Text('${snap.imageSysdir}  (tidak ditemukan)', overflow: TextOverflow.ellipsis),
        ),
      );
    }
    for (final image in snap.installedImages) {
      items.add(
        DropdownMenuItem(
          value: image.relativeDirWindows,
          child: Text(image.label, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    return items;
  }

  Future<void> _save() async {
    if (widget.controller.isSelectedAvdRunning()) {
      setState(() {
        _error = 'AVD sedang berjalan. Hentikan emulator dulu sebelum mengedit.';
      });
      return;
    }
    final sysdir = _imageSysdir ?? '';
    if (widget.snapshot.currentImageMissing &&
        _normalize(sysdir) == _normalize(widget.snapshot.imageSysdir)) {
      setState(() {
        _error = 'Pilih system image yang sudah terpasang.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.saveSelectedConfig(
        imageSysdir: sysdir,
        ramSize: _ram.text,
        storageSize: _storage.text,
        gpuMode: _gpuMode,
        cpuCores: _cores.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  String _normalize(String value) {
    var result = value.trim().replaceAll('/', '\\');
    if (!result.endsWith('\\') && result.isNotEmpty) result = '$result\\';
    return result.toLowerCase();
  }
}

String _gpuLabel(String mode) {
  switch (mode) {
    case 'host':
      return 'host (GPU komputer)';
    case 'swiftshader_indirect':
      return 'swiftshader_indirect (software)';
    default:
      return 'auto';
  }
}
