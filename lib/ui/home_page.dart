import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/adb_device.dart';
import 'create_avd_dialog.dart';
import 'edit_avd_dialog.dart';
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
              if (controller.lastEmulatorLogPath != null)
                IconButton(
                  tooltip: 'Buka log emulator terakhir',
                  onPressed: controller.openLastEmulatorLog,
                  icon: const Icon(Icons.article_outlined),
                ),
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
                        onOpenLog: controller.lastEmulatorLogPath != null
                            ? controller.openLastEmulatorLog
                            : null,
                      ),
                    ],
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      _MessageBanner(
                        text: controller.errorMessage!,
                        tone: _BannerTone.error,
                        onOpenLog: controller.lastEmulatorLogPath != null
                            ? controller.openLastEmulatorLog
                            : null,
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
            if (controller.settingsFilePath != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                'Berkas pengaturan: ${controller.settingsFilePath}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (controller.settingsLocationLabel != null)
                Text(
                  'Lokasi: ${controller.settingsLocationLabel}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
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
                  onPressed: controller.loading
                      ? null
                      : () async {
                          await controller.useAutomaticSdk();
                          if (context.mounted) {
                            _showSettingsSnackBar(context, controller);
                          }
                        },
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
    if (context.mounted) {
      _showSettingsSnackBar(context, controller);
    }
  }
}

class _AvdCard extends StatelessWidget {
  const _AvdCard({required this.controller});

  final LauncherController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  'Tidak ada AVD yang ditemukan. Buat virtual device dari tombol di bawah, di Android Studio, atau dengan avdmanager.',
                ),
              )
            else
              RadioGroup<String>(
                groupValue: controller.selectedAvd,
                onChanged: controller.selectAvd,
                child: Column(
                  children: [
                    for (final name in controller.avds)
                      Builder(
                        builder: (context) {
                          final summary = controller.avdSummaries[name];
                          final isRunning = controller.isAvdRunningByName(name);
                          final subtitleParts = <String>[
                            if (summary != null && summary.subtitle.isNotEmpty)
                              summary.subtitle,
                            if (summary != null && summary.imageMissing)
                              'System image hilang',
                          ];
                          return RadioListTile<String>(
                            value: name,
                            title: Row(
                              children: [
                                Flexible(child: Text(name)),
                                if (isRunning) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: scheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Berjalan',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onPrimaryContainer,
                                          ),
                                    ),
                                  ),
                                ],
                                if (summary != null && summary.imageMissing) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.warning_amber_rounded,
                                    size: 18,
                                    color: scheme.error,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: subtitleParts.isEmpty
                                ? null
                                : Text(
                                    subtitleParts.join(' · '),
                                    style: summary != null && summary.imageMissing
                                        ? TextStyle(color: scheme.error)
                                        : null,
                                  ),
                            dense: true,
                          );
                        },
                      ),
                  ],
                ),
              ),
            if (controller.orphanedAvds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Text(
                  'Folder .avd tanpa berkas .ini terdeteksi: ${controller.orphanedAvds.join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.tertiary,
                      ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: controller.canCreateAvd
                        ? () => showCreateAvdDialog(context, controller)
                        : null,
                    icon: const Icon(Icons.add),
                    label: const Text('Buat AVD baru'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.canEditSelected
                        ? () => showEditAvdDialog(context, controller)
                        : null,
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit AVD'),
                  ),
                  OutlinedButton.icon(
                    onPressed: controller.canDeleteSelected
                        ? () => _confirmDeleteAvd(context)
                        : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus AVD'),
                  ),
                  if (controller.selectedAvd != null)
                    TextButton.icon(
                      onPressed: controller.openSelectedAvdFolder,
                      icon: const Icon(Icons.folder_outlined),
                      label: const Text('Buka folder AVD'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAvd(BuildContext context) async {
    final name = controller.selectedAvd;
    if (name == null || name.isEmpty) return;
    if (controller.isAvdRunningByName(name)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'AVD "$name" sedang berjalan. Hentikan emulator dulu sebelum menghapus.',
            ),
          ),
        );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus AVD?'),
          content: Text(
            'Virtual device "$name" beserta seluruh data di dalamnya akan dihapus permanen. Lanjutkan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await controller.deleteSelectedAvd();
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: DropdownButtonFormField<String>(
                key: ValueKey<String>(controller.gpuLaunchMode),
                initialValue: controller.gpuLaunchMode,
                decoration: const InputDecoration(
                  labelText: 'Mode GPU saat dijalankan',
                  border: OutlineInputBorder(),
                ),
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('Dari config AVD')),
                  DropdownMenuItem(value: 'auto', child: Text('auto')),
                  DropdownMenuItem(value: 'host', child: Text('host (GPU komputer)')),
                  DropdownMenuItem(
                    value: 'swiftshader_indirect',
                    child: Text('swiftshader_indirect (software)'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) controller.setGpuLaunchMode(value);
                },
              ),
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
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Emulator yang sedang berjalan',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (controller.sdk.hasAdb)
                    TextButton.icon(
                      onPressed: controller.loading ? null : controller.restartAdb,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Restart ADB'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
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
                  title: Text(device.displayTitle),
                  subtitle: Text([
                    device.state,
                    if (device.model != null && device.model!.isNotEmpty) device.model!,
                  ].join('  ·  ')),
                  trailing: Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (device.state == 'device')
                        OutlinedButton.icon(
                          onPressed: controller.installingApk || controller.loading
                              ? null
                              : () => _pickAndInstallApk(context, device),
                          icon: const Icon(Icons.install_mobile, size: 16),
                          label: const Text('Pasang APK'),
                        ),
                      if (device.isEmulator)
                        OutlinedButton(
                          onPressed: controller.stopping || controller.loading
                              ? null
                              : () => controller.stopDevice(device),
                          child: const Text('Hentikan'),
                        )
                      else
                        Text(
                          'Perangkat fisik',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndInstallApk(BuildContext context, AdbDevice device) async {
    const typeGroup = XTypeGroup(
      label: 'Berkas APK Android',
      extensions: <String>['apk'],
    );
    final file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[typeGroup],
      confirmButtonText: 'Pasang',
    );
    if (file == null) return;
    await controller.installApkOnDevice(device, file.path);
  }
}

void _showSettingsSnackBar(BuildContext context, LauncherController controller) {
  final path = controller.settingsFilePath;
  final text = controller.errorMessage ??
      (path == null
          ? (controller.statusMessage ?? 'Pengaturan diperbarui.')
          : 'Pengaturan disimpan di: $path');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

enum _BannerTone { info, error }

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({
    required this.text,
    required this.tone,
    this.onOpenLog,
  });

  final String text;
  final _BannerTone tone;
  final VoidCallback? onOpenLog;

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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(text, style: TextStyle(color: fg)),
            ),
            if (onOpenLog != null) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: onOpenLog,
                icon: const Icon(Icons.article_outlined, size: 18),
                label: const Text('Buka Log'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
