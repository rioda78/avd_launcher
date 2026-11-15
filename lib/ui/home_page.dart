import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'launcher_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('AVD Launcher'),
            actions: [
              IconButton(
                tooltip: 'Segarkan',
                onPressed: controller.loading ? null : () => controller.refresh(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: [
              if (controller.loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Text(
                      'Pilih virtual device Android, lalu jalankan emulator.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 16),
                    _SdkCard(controller: controller),
                    const SizedBox(height: 16),
                    _AvdCard(controller: controller),
                    const SizedBox(height: 16),
                    _OptionsCard(controller: controller),
                    const SizedBox(height: 16),
                    _RunningCard(controller: controller),
                    if (controller.statusMessage != null) ...[
                      const SizedBox(height: 16),
                      _MessageBanner(
                        text: controller.statusMessage!,
                        tone: _BannerTone.info,
                      ),
                    ],
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _MessageBanner(
                        text: controller.errorMessage!,
                        tone: _BannerTone.error,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SdkCard extends StatelessWidget {
  const _SdkCard({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    final sdk = controller.sdk;
    final pathText = sdk.root.isNotEmpty
        ? sdk.root
        : (controller.sdkOverrideText ?? 'Belum terdeteksi');
    final sourceText = sdk.source.isNotEmpty
        ? 'Sumber: ${sdk.source}'
        : 'Lokasi SDK belum terdeteksi.';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lokasi Android SDK', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(pathText, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(sourceText, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: controller.loading ? null : () => _browse(context),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Pilih folder…'),
                ),
                OutlinedButton.icon(
                  onPressed: controller.loading ? null : controller.useAutomaticSdk,
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Deteksi otomatis'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _browse(BuildContext context) async {
    final initial = controller.sdk.root.isNotEmpty ? controller.sdk.root : null;
    final dir = await getDirectoryPath(
      confirmButtonText: 'Pilih',
      initialDirectory: initial,
    );
    if (dir == null) return;
    await controller.setManualSdkPath(dir);
  }
}

class _AvdCard extends StatelessWidget {
  const _AvdCard({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Virtual Device',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (!controller.sdk.hasEmulator)
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text('Daftar AVD akan muncul setelah lokasi SDK valid.'),
              )
            else if (controller.avds.isEmpty && !controller.loading)
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  'Tidak ada AVD yang ditemukan. Buat virtual device di Android Studio atau dengan avdmanager.',
                ),
              )
            else
              RadioGroup<String>(
                groupValue: controller.selectedAvd,
                onChanged: controller.selectAvd,
                child: Column(
                  children: [
                    for (final name in controller.avds)
                      RadioListTile<String>(
                        value: name,
                        title: Text(name),
                        dense: true,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OptionsCard extends StatelessWidget {
  const _OptionsCard({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Text('Opsi jalankan', style: Theme.of(context).textTheme.titleMedium),
            ),
            CheckboxListTile(
              value: controller.coldBoot,
              onChanged: (value) => controller.setColdBoot(value ?? false),
              title: const Text('Boot dingin'),
              subtitle: const Text('Tanpa memuat snapshot  (−no-snapshot-load)'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: controller.wipeData,
              onChanged: (value) => controller.setWipeData(value ?? false),
              title: const Text('Hapus data'),
              subtitle: const Text('Menghapus data di dalam AVD  (−wipe-data)'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            CheckboxListTile(
              value: controller.noAudio,
              onChanged: (value) => controller.setNoAudio(value ?? false),
              title: const Text('Tanpa audio'),
              subtitle: const Text('Menjalankan emulator tanpa suara  (−no-audio)'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  onPressed: controller.canStart ? () => _start(context) : null,
                  icon: controller.starting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Mulai'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _start(BuildContext context) async {
    if (controller.wipeData) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Hapus data AVD?'),
            content: Text(
              'Data di dalam "${controller.selectedAvd}" akan dihapus sebelum emulator dijalankan. Lanjutkan?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Hapus dan jalankan'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }
    await controller.startSelected();
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Emulator yang sedang berjalan',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (controller.devices.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text('Tidak ada perangkat yang terdeteksi oleh adb.'),
              )
            else
              for (final device in controller.devices)
                ListTile(
                  dense: true,
                  leading: Icon(
                    device.isEmulator ? Icons.smartphone : Icons.phone_android,
                  ),
                  title: Text(device.serial),
                  subtitle: Text([
                    device.state,
                    if (device.model != null && device.model!.isNotEmpty) device.model!,
                  ].join('  ·  ')),
                  trailing: device.isEmulator
                      ? OutlinedButton(
                          onPressed: controller.stopping || controller.loading
                              ? null
                              : () => controller.stopDevice(device),
                          child: const Text('Hentikan'),
                        )
                      : Text(
                          'Perangkat fisik',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                ),
          ],
        ),
      ),
    );
  }
}

enum _BannerTone { info, error }

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.text, required this.tone});

  final String text;
  final _BannerTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = tone == _BannerTone.error ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final fg = tone == _BannerTone.error ? scheme.onErrorContainer : scheme.onSurface;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SelectableText(text, style: TextStyle(color: fg)),
      ),
    );
  }
}
