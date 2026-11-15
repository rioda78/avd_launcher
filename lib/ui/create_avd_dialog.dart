import 'package:flutter/material.dart';

import '../services/avd_config.dart';
import 'launcher_controller.dart';

Future<void> showCreateAvdDialog(BuildContext context, LauncherController controller) async {
  final manager = controller.avdManagerPath;
  if (manager == null || manager.isEmpty) {
    final message = avdManagerMissingMessage(controller.sdk.root);
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('avdmanager tidak ditemukan'),
          content: SelectableText(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
    return;
  }

  try {
    final images = await controller.installedSystemImages();
    final devices = await controller.listDeviceProfiles();
    if (!context.mounted) return;
    if (images.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Tidak ada system image'),
            content: const Text(
              'Tidak ada system image terpasang di folder system-images pada SDK. '
              'Pasang image lewat Android Studio atau sdkmanager, lalu coba lagi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      );
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreateAvdDialog(
        controller: controller,
        images: images,
        devices: devices,
      ),
    );
    if (created == true && context.mounted) {
      final text = controller.statusMessage ?? 'AVD baru dibuat.';
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

class CreateAvdDialog extends StatefulWidget {
  const CreateAvdDialog({
    super.key,
    required this.controller,
    required this.images,
    required this.devices,
  });

  final LauncherController controller;
  final List<SystemImage> images;
  final List<String> devices;

  @override
  State<CreateAvdDialog> createState() => _CreateAvdDialogState();
}

class _CreateAvdDialogState extends State<CreateAvdDialog> {
  final _name = TextEditingController();
  final _ram = TextEditingController(text: '2048');
  final _storage = TextEditingController(text: '6G');
  late String _gpuMode;
  late String _packageId;
  late String _deviceId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _gpuMode = 'auto';
    _packageId = widget.images.first.packageId;
    _deviceId = widget.devices.contains('pixel_7')
        ? 'pixel_7'
        : widget.devices.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _ram.dispose();
    _storage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Buat AVD baru'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nama',
                  hintText: 'Pixel_Test',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: widget.devices.contains(_deviceId) ? _deviceId : widget.devices.first,
                decoration: const InputDecoration(
                  labelText: 'Profil perangkat',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: [
                  for (final id in widget.devices)
                    DropdownMenuItem(value: id, child: Text(id, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _deviceId = value);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _packageId,
                decoration: const InputDecoration(
                  labelText: 'System image',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: [
                  for (final image in widget.images)
                    DropdownMenuItem(
                      value: image.packageId,
                      child: Text(image.label, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _packageId = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ram,
                decoration: const InputDecoration(
                  labelText: 'RAM (MB)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _storage,
                decoration: const InputDecoration(
                  labelText: 'Penyimpanan internal',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _gpuMode,
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
          onPressed: _saving ? null : _create,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Buat'),
        ),
      ],
    );
  }

  Future<void> _create() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.createAvd(
        name: _name.text,
        packageId: _packageId,
        deviceId: _deviceId,
        ramSize: _ram.text,
        storageSize: _storage.text,
        gpuMode: _gpuMode,
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
