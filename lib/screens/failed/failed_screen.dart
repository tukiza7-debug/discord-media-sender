import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/error_translator.dart';
import '../../core/formatters.dart';
import '../../models/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/upload_providers.dart';
import '../../widgets/common.dart';

/// Skrin Gagal — fail/batch yang gagal selepas 3 cubaan.
/// Potret: senarai penuh dengan butang Cuba Semula per item.
/// Landscape: senarai kiri + panel butiran kanan.
class FailedScreen extends ConsumerStatefulWidget {
  const FailedScreen({super.key});

  @override
  ConsumerState<FailedScreen> createState() => _FailedScreenState();
}

class _FailedScreenState extends ConsumerState<FailedScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(failedProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.compact;
    final async = ref.watch(failedProvider);
    final failures = async.value ?? const <FailedRecord>[];

    final listPane = RefreshIndicator(
      onRefresh: () => ref.read(failedProvider.notifier).load(),
      child: failures.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                EmptyState(
                  icon: LucideIcons.alertTriangle,
                  title: 'No failures',
                  subtitle:
                      'Files or batches that fail after 3 automatic attempts will appear here with the full reason.',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: failures.length,
              itemBuilder: (context, i) => _FailedCard(record: failures[i], wide: wide),
            ),
    );

    final appBar = wide
        ? null
        : AppBar(
            title: const Text('Failed'),
            actions: [
              if (failures.isNotEmpty) ...[
                IconButton(
                  tooltip: 'Retry All',
                  icon: const Icon(LucideIcons.rotateCcw, size: 19),
                  onPressed: () => _retryAll(context),
                ),
                IconButton(
                  tooltip: 'Delete All',
                  icon: const Icon(LucideIcons.trash2, size: 19, color: AppColors.danger),
                  onPressed: () => _clearAll(context),
                ),
              ],
            ],
          );

    if (wide) {
      final selectedId = ref.watch(selectedFailedIdProvider);
      FailedRecord? selected;
      if (selectedId != null) {
        selected = failures.where((f) => f.id == selectedId).firstOrNull;
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('Failed'),
          actions: [
            if (failures.isNotEmpty) ...[
              TextButton.icon(
                onPressed: () => _retryAll(context),
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: const Text('Retry All'),
              ),
              IconButton(
                tooltip: 'Delete All',
                icon: const Icon(LucideIcons.trash2, size: 19, color: AppColors.danger),
                onPressed: () => _clearAll(context),
              ),
            ],
          ],
        ),
        body: SafeArea(
          child: Row(
            children: [
              Flexible(flex: 5, child: listPane),
              const VerticalDivider(width: 1),
              Flexible(
                flex: 6,
                child: selected == null
                    ? const EmptyState(
                        icon: LucideIcons.alertTriangle,
                        title: 'Pick a failure',
                        subtitle: 'Pick an entry to view the HTTP code, message and actions.',
                      )
                    : _FailedDetail(record: selected, onRetry: () => _retryOne(context, selected!)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(appBar: appBar, body: listPane);
  }

  Future<void> _retryOne(BuildContext context, FailedRecord f) => _retry(context, [f]);

  Future<void> _retryAll(BuildContext context) async {
    final failures = ref.read(failedProvider).value ?? const <FailedRecord>[];
    await _retry(context, failures);
  }

  Future<void> _retry(BuildContext context, List<FailedRecord> list) async {
    if (list.isEmpty) return;
    final items = [for (final f in list) f.toMediaItem()];
    final upload = ref.read(uploadControllerProvider.notifier);
    final config = ref.read(configProvider);
    final result = await upload.start(items: items, config: config, caption: '');
    if (context.mounted && result != null) {
      showAppSnackBar(context, result, success: !result.startsWith('Failed'));
    }
    ref.read(failedProvider.notifier).load();
  }

  Future<void> _clearAll(BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete all failure records?',
      message: 'All failure entries will be removed. Files on your device are not touched.',
    );
    if (ok) {
      ref.read(failedProvider.notifier).clearAll();
      if (context.mounted) showAppSnackBar(context, 'Failure records cleared.');
    }
  }
}

extension _FirstOrNullF<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _FailedCard extends ConsumerWidget {
  const _FailedCard({required this.record, required this.wide});
  final FailedRecord record;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = record.httpCode == null || record.httpCode! >= 500
        ? AppColors.danger
        : AppColors.warning;
    return Dismissible(
      key: ValueKey('failed-${record.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(LucideIcons.trash2, color: Colors.white),
      ),
      onDismissed: (_) {
        if (record.id != null) ref.read(failedProvider.notifier).deleteFailure(record.id!);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          onTap: wide ? () => ref.read(selectedFailedIdProvider.notifier).state = record.id : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.fileName,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Chip kod HTTP (merah rangkaian/5xx, kuning 4xx)
                    SoftBadge(
                      record.httpCode?.toString() ?? 'NETWORK',
                      color: color,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  ErrorTranslator.shortReason(
                    statusCode: record.httpCode,
                    error: record.httpCode == null ? StateError('network') : null,
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(LucideIcons.clock,
                        size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 5),
                    Text(
                      '${formatDateTime(record.createdAt)} • Batch ${record.batchIndex}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const Spacer(),
                    if (!wide)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 36),
                          foregroundColor: AppColors.blurpleBright,
                        ),
                        onPressed: () => _retryOne(context, ref, record),
                        icon: const Icon(LucideIcons.rotateCcw, size: 14),
                        label: const Text('Retry'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _retryOne(BuildContext context, WidgetRef ref, FailedRecord f) async {
    final upload = ref.read(uploadControllerProvider.notifier);
    final config = ref.read(configProvider);
    final result = await upload.start(items: [f.toMediaItem()], config: config, caption: '');
    if (context.mounted && result != null) {
      showAppSnackBar(context, result, success: !result.startsWith('Failed'));
    }
    ref.read(failedProvider.notifier).load();
  }
}

class _FailedDetail extends StatelessWidget {
  const _FailedDetail({required this.record, required this.onRetry});
  final FailedRecord record;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.fileName, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                Text(
                  'HTTP code: ${record.httpCode?.toString() ?? 'None (network error)'}\n'
                  'Batch: ${record.batchIndex}\n'
                  'Time: ${formatDateTime(record.createdAt)}\n'
                  'Mode: ${record.mode == 'bot' ? 'Bot' : 'Webhook'} • Target: ${record.target}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.7,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  record.errorMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(LucideIcons.rotateCcw, size: 17),
          label: const Text('Retry This File'),
        ),
      ],
    );
  }
}
