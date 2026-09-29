import 'dart:convert';
import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../models/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/upload_providers.dart';
import '../../services/discord_api.dart';
import '../../widgets/common.dart';
import '../../widgets/json_view.dart';

/// Butiran penuh satu respons: endpoint ditapis, header rate limit,
/// JSON berwarna boleh lipat, penerangan ralat BM + tindakan.
class ResponseDetailView extends ConsumerWidget {
  const ResponseDetailView({super.key, required this.entry});
  final ResponseLogEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = statusColor(context, status: entry.status, statusCode: entry.statusCode);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Pengepala status
        Row(
          children: [
            StatusBadge(status: entry.status, statusCode: entry.statusCode),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.reasonPhrase ?? DiscordApi.describeStatusCode(entry.statusCode),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          entry.batchNumber == 0
              ? 'Test/info request'
              : 'Batch ${entry.batchNumber}/${entry.totalBatches} • ${entry.fileCount} files • '
                  'attempt ${entry.attempt}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 14),

        // Endpoint + kaedah (sentiasa ditapis)
        _SectionCard(
          title: 'REQUEST',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.blurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      entry.method,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.blurpleBright,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.endpoint,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              MonoBlock(Security.buildCurl(
                isWebhook: entry.endpoint.contains('/webhooks/'),
                endpoint: entry.endpoint,
                fileNames: entry.fileNames,
              )),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(LucideIcons.shieldCheck, size: 13, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text(
                    'Tokens & webhook URLs are sanitized automatically.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.success,
                          fontSize: 11,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Metrik
        _SectionCard(
          title: 'METRICS',
          child: Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _Metric(label: 'Response time', value: formatMs(entry.latencyMs)),
              if (entry.uploadBytes > 0)
                _Metric(label: 'Upload size', value: formatBytes(entry.uploadBytes)),
              if (entry.uploadBytes > 0 && entry.latencyMs > 0)
                _Metric(label: 'Speed', value: formatSpeed(entry.speedMBps)),
              _Metric(label: 'Request time', value: formatClock(entry.timestamp)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Header rate limit (jika ada)
        if (entry.rateLimitHeaders.isNotEmpty) ...[
          _SectionCard(
            title: 'HEADER RATE LIMIT',
            child: Column(
              children: [
                for (final e in entry.rateLimitHeaders.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Expanded(
                          child: MonoBlock(e.key,
                              maxLines: 1),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: Text(e.value,
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Ralat + penerangan BM
        if (entry.status.isError || entry.explanation != null) ...[
          _SectionCard(
            title: 'ERROR & RESOLUTION',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.explanation ?? entry.errorMessage ?? '—',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
                ),
                if (entry.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Original message: ${entry.errorMessage}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Kad khas countdown 429
        if (entry.status == LogStatus.rateLimited && entry.retryAfterMs != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
            ),
            child: RateLimitCountdown(
              retryAfterMs: entry.retryAfterMs!,
              startedAt: entry.timestamp,
            ),
          ),
          const SizedBox(height: 12),
        ],

        // JSON badan respons
        JsonView(json: entry.responseJson),
        const SizedBox(height: 14),

        // Tindakan
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () => _copyJson(context),
              icon: const Icon(LucideIcons.copy, size: 15),
              label: const Text('Copy JSON'),
            ),
            OutlinedButton.icon(
              onPressed: () => _copyCurl(context),
              icon: const Icon(LucideIcons.terminal, size: 15),
              label: const Text('Copy cURL'),
            ),
            if (entry.status.isError) ...[
              FilledButton.icon(
                onPressed: () => _retryBatch(context, ref),
                icon: const Icon(LucideIcons.rotateCcw, size: 15),
                label: const Text('Retry This Batch'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _copyJson(BuildContext context) {
    final text = const JsonEncoder.withIndent('  ').convert(
      Security.sanitizeJson(entry.responseJson),
    );
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.selectionClick();
    showAppSnackBar(context, 'JSON (sanitized) copied to clipboard.', success: true);
  }

  void _copyCurl(BuildContext context) {
    final curl = Security.buildCurl(
      isWebhook: entry.endpoint.contains('/webhooks/'),
      endpoint: entry.endpoint,
      fileNames: entry.fileNames,
    );
    Clipboard.setData(ClipboardData(text: curl));
    HapticFeedback.selectionClick();
    showAppSnackBar(context, 'cURL (sanitized) copied to clipboard.', success: true);
  }

  Future<void> _retryBatch(BuildContext context, WidgetRef ref) async {
    // Bina semula senarai fail daripada laluan tersimpan.
    final items = <MediaItem>[];
    for (var i = 0; i < entry.filePaths.length; i++) {
      final path = entry.filePaths[i];
      final name = i < entry.fileNames.length ? entry.fileNames[i] : path.split('/').last;
      final f = File(path);
      if (!f.existsSync()) {
        showAppSnackBar(context, 'File $name no longer exists on the device.', error: true);
        return;
      }
      final isVideo = MediaCatalog.isVideo(name);
      items.add(MediaItem(
        id: 'retry-$path-$i',
        path: path,
        name: name,
        sizeBytes: f.lengthSync(),
        type: isVideo ? MediaType.video : MediaType.image,
        mimeType: MediaCatalog.mimeType(name),
      ));
    }
    if (items.isEmpty) return;

    final upload = ref.read(uploadControllerProvider.notifier);
    final config = ref.read(configProvider);
    final result = await upload.start(items: items, config: config, caption: '');
    if (context.mounted && result != null) {
      showAppSnackBar(context, result, success: !result.startsWith('Failed'));
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleSmall),
      ],
    );
  }
}
