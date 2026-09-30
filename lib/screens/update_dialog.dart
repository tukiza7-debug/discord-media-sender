import 'dart:io';

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../services/update_service.dart';

/// 1c: dialog kemas kini — nota keluaran boleh skrol, butang
/// "Update now" / "Later" / "Skip this version". Butang Update dilumpuhkan
/// semasa sesi hantaran aktif (3c: kemas kini tidak boleh berjalan semasa
/// sesi) — penjelasan ringkas dipaparkan.
class UpdateAvailableDialog extends StatefulWidget {
  const UpdateAvailableDialog({
    super.key,
    required this.release,
    required this.currentVersion,
    required this.sessionRunning,
    this.updateRunner, // suntikan untuk ujian widget
  });

  final GithubRelease release;
  final String currentVersion;

  /// Keadaan sesi semasa dialog dipapar / butang ditekan.
  final bool Function() sessionRunning;

  /// Lalai: UpdateService.runUpdateFlow (muat turun + sahkan + pasang).
  final Future<UpdateFlowResult> Function(
      void Function(int received, int total) onProgress, CancelToken token)?
      updateRunner;

  @override
  State<UpdateAvailableDialog> createState() => _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends State<UpdateAvailableDialog> {
  bool _busy = false;
  int _received = 0;
  int _total = 0;
  String? _error;
  CancelToken? _cancelToken;

  String get _notes {
    final body = widget.release.body;
    if (body.length <= AppLimits.updateReleaseNotesCap) return body;
    return '${body.substring(0, AppLimits.updateReleaseNotesCap)}\n…';
  }

  Future<void> _startUpdate() async {
    if (widget.sessionRunning()) return; // 3c: jangan sekali-kali semasa sesi
    setState(() {
      _busy = true;
      _error = null;
      _received = 0;
      _total = 0;
    });
    _cancelToken = CancelToken();
    try {
      List<String> abis = const [];
      try {
        final info = await DeviceInfoPlugin().androidInfo;
        abis = info.supportedAbis;
      } catch (_) {}
      // ABI gagal dikenal pasti → runner gugur ke universal (1d).
      final runner = widget.updateRunner ??
          (onProgress, token) => UpdateService.runUpdateFlow(
                release: widget.release,
                deviceAbis: Platform.isAndroid ? abis : const [],
                onProgress: onProgress,
                cancelToken: token,
              );
      final result = await runner((received, total) {
        if (!mounted) return;
        setState(() {
          _received = received;
          _total = total;
        });
      }, _cancelToken!);
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop(true);
        return;
      }
      if (result.cancelled) {
        setState(() => _busy = false);
        return;
      }
      setState(() {
        _busy = false;
        _error = result.error ?? 'Update failed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Update failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionRunning = widget.sessionRunning();
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Update available'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Version ${widget.currentVersion} → '
              '${widget.release.tag}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // Nota keluaran (teks biasa, boleh skrol, had panjang 1c).
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              constraints: const BoxConstraints(maxHeight: 300, minHeight: 64),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: SelectableText(
                  _notes.isEmpty ? 'No release notes.' : _notes,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            if (sessionRunning) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.lock_outline,
                      size: 15, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'An upload session is running — updates are blocked '
                      'until it finishes.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 14),
              Text(
                _total > 0
                    ? 'Downloading… ${(_received / 1048576).toStringAsFixed(1)}'
                        ' / ${(_total / 1048576).toStringAsFixed(1)} MB'
                    : 'Preparing download…',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null,
                minHeight: 6,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _cancelToken?.cancel('Cancelled by user'),
                  child: const Text('Cancel'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 1d: papar URL keluaran + butang Salin.
                    Text(
                      widget.release.htmlUrl,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: widget.release.htmlUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Release page URL copied.')),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 15),
                        label: const Text('Copy URL'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          // 1c: lakukan semasa dialog ditutup — versi ini tidak mengganggu
          // lagi (simpan tag tanpa awalan 'v' — konsisten dgn semakan 1b).
          onPressed: _busy
              ? null
              : () {
                  UpdateService.skipVersion(widget.release.tag);
                  Navigator.of(context).pop(false);
                },
          child: const Text('Skip this version'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        FilledButton(
          // Dilumpuhkan semasa sesi hantaran aktif (1c) / semasa sibuk.
          onPressed: (_busy || sessionRunning) ? null : _startUpdate,
          child: const Text('Update now'),
        ),
      ],
    );
  }
}

/// Papar dialog kemas kini — dipanggil dari aliran automatik/manual.
Future<void> showUpdateAvailableDialog(
  BuildContext context, {
  required GithubRelease release,
  required String currentVersion,
  required bool Function() sessionRunning,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => UpdateAvailableDialog(
      release: release,
      currentVersion: currentVersion,
      sessionRunning: sessionRunning,
    ),
  );
}
