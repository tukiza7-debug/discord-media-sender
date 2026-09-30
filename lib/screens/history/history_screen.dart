import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/upload_providers.dart';
import '../../services/database_service.dart';
import '../../widgets/common.dart';

/// Skrin Sejarah — setiap sesi hantaran dikelompokkan mengikut tarikh.
/// Landscape (>=600dp): senarai kiri, butiran kanan.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(historyProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.compact;
    final async = ref.watch(historyProvider);
    final sessions = async.value ?? const <SessionRecord>[];

    // Kumpul mengikut tarikh.
    final groups = <String, List<SessionRecord>>{};
    for (final s in sessions) {
      groups.putIfAbsent(formatRelativeDay(s.startedAt), () => []).add(s);
    }

    final listPane = RefreshIndicator(
      onRefresh: () => ref.read(historyProvider.notifier).load(),
      child: sessions.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                EmptyState(
                  icon: LucideIcons.history,
                  title: 'No history yet',
                  subtitle:
                      'Every sending session will be recorded here — date, mode, file count and status.',
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              itemCount: sessions.length + groups.length,
              itemBuilder: (context, i) {
                // Sisip pengepala kumpulan tarikh.
                var idx = i;
                for (final g in groups.entries) {
                  if (idx == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6, top: 6),
                      child: SectionLabel(g.key),
                    );
                  }
                  idx--;
                  if (idx < g.value.length) {
                    final s = g.value[idx];
                    final selected = s.id != null && s.id == ref.watch(selectedSessionIdProvider);
                    return _SessionCard(
                      record: s,
                      selected: selected,
                      onTap: () => _open(context, s),
                    );
                  }
                  idx -= g.value.length;
                }
                return const SizedBox.shrink();
              },
            ),
    );

    if (wide) {
      final selectedId = ref.watch(selectedSessionIdProvider);
      SessionRecord? selected;
      if (selectedId != null) {
        selected = sessions.where((s) => s.id == selectedId).firstOrNull;
      }
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Flexible(flex: 5, child: listPane),
              const VerticalDivider(width: 1),
              Flexible(
                flex: 6,
                child: selected == null
                    ? const EmptyState(
                        icon: LucideIcons.history,
                        title: 'Pick a session',
                        subtitle:
                            'Pick a session to view details and retry actions.',
                      )
                    : _SessionDetail(record: selected),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: listPane,
    );
  }

  void _open(BuildContext context, SessionRecord s) {
    if (s.id == null) return;
    ref.read(selectedSessionIdProvider.notifier).state = s.id;
    if (MediaQuery.sizeOf(context).width < AppBreakpoints.compact) {
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Session Details')),
          body: SafeArea(child: _SessionDetail(record: s)),
        ),
      ));
    }
  }
}

extension _FirstOrNullX<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _SessionCard extends ConsumerWidget {
  const _SessionCard({required this.record, required this.onTap, required this.selected});
  final SessionRecord record;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (color, label) = _statusColor(record.status);
    return Dismissible(
      key: ValueKey('session-${record.id}'),
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
      confirmDismiss: (_) async {
        return await confirmDialog(
          context,
          title: 'Delete this session?',
          message: 'The session record and its related failures will be deleted.',
        );
      },
      onDismissed: (_) {
        ref.read(historyProvider.notifier).deleteSession(record.id!);
        ref.read(failedProvider.notifier).load();
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SoftBadge(label, color: color),
                    const SizedBox(width: 8),
                    SoftBadge(record.mode == 'bot' ? 'Bot' : 'Webhook',
                        icon: record.mode == 'bot' ? LucideIcons.bot : LucideIcons.globe),
                    const Spacer(),
                    Text(
                      '${formatClockShort(record.startedAt)} - ${formatClockShort(record.endedAt)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  record.target,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Count(label: 'Files', value: '${record.totalFiles}'),
                    const SizedBox(width: 16),
                    _Count(label: 'Succeeded', value: '${record.successCount}', color: AppColors.success),
                    const SizedBox(width: 16),
                    _Count(label: 'Failed', value: '${record.failedCount}', color: AppColors.danger),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (Color, String) _statusColor(String status) {
    switch (status) {
      case 'completed':
        return (AppColors.success, 'Success');
      case 'partial':
        return (AppColors.warning, 'Partial');
      case 'failed':
        return (AppColors.danger, 'Failed');
      case 'cancelled':
        return (AppColors.textFaint, 'Cancelled');
      case 'running':
        return (AppColors.info, 'In progress');
      default:
        return (AppColors.info, status);
    }
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 9.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _SessionDetail extends ConsumerWidget {
  const _SessionDetail({required this.record});
  final SessionRecord record;

  // 4c: pemetaan warna status — SAMA seperti _SessionCard.
  (Color, String) _statusColor(String status) {
    switch (status) {
      case 'completed':
        return (AppColors.success, 'Success');
      case 'partial':
        return (AppColors.warning, 'Partial');
      case 'failed':
        return (AppColors.danger, 'Failed');
      case 'cancelled':
        return (AppColors.textFaint, 'Cancelled');
      case 'running':
        return (AppColors.info, 'In progress');
      default:
        return (AppColors.info, status);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (statusColor, statusLabel) = _statusColor(record.status);
    // 4c: blok sebab — untuk SETIAP status bukan-completed (sesi 'running'
    // belum tamat, jadi tidak memerlukan sebab lagi).
    final showReason = record.status != 'completed' && record.status != 'running';
    final notSent = record.totalFiles - record.successCount - record.failedCount;
    final reasonText = (record.reason == null || record.reason!.isEmpty)
        ? 'No reason was recorded for this session (created before this update).'
        : record.reason!;
    return FutureBuilder<List<FailedRecord>>(
      future: DatabaseService.instance.failures(sessionId: record.id),
      builder: (context, snap) {
        final failures = snap.data ?? const <FailedRecord>[];
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Session #${record.id ?? '-'}',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          // 4c: lencana status (warna sama seperti _SessionCard).
                          SoftBadge(statusLabel, color: statusColor),
                          const SizedBox(height: 6),
                          Text(
                            '${formatDateTime(record.startedAt)}\n'
                            'Mode: ${record.mode == 'bot' ? 'Bot' : 'Webhook'} • Target: ${record.target}\n'
                            '${record.totalFiles} files • ${record.successCount} succeeded • ${record.failedCount} failed',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  height: 1.6,
                                ),
                          ),
                          if (showReason) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: IntrinsicHeight(
                                // IntrinsicHeight: jalur aksen mengikut
                                // tinggi kandungan (stretch tanpa batas
                                // tinggi = constraint infiniti).
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                  Container(
                                    width: 3,
                                    decoration: BoxDecoration(
                                      color: statusColor,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'REASON',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                fontSize: 9.5,
                                                color: statusColor,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        // 4c: teks boleh dipilih & mesti balut penuh
                                        // (tanpa pemotongan).
                                        SelectableText(
                                          reasonText,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(height: 1.5),
                                        ),
                                        const SizedBox(height: 6),
                                        SelectableText(
                                          [
                                            'Sent: ${record.successCount}',
                                            'Failed: ${record.failedCount}',
                                            if (notSent > 0) 'Not sent: $notSent',
                                          ].join(' • '),
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ), // Row
                            ), // IntrinsicHeight
                            ), // Container (blok sebab)
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionLabel('Failed Files (${failures.length})'),
                  if (failures.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('No failures recorded for this session.'),
                    )
                  else
                    for (final f in failures) _FailureRow(record: f),
                ],
              ),
            ),
            if (failures.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(LucideIcons.rotateCcw, size: 17),
                    label: Text('Retry Session (${failures.length} files)'),
                    onPressed: () => _retrySession(context, ref, failures),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _retrySession(
      BuildContext context, WidgetRef ref, List<FailedRecord> failures) async {
    final items = [for (final f in failures) f.toMediaItem()];
    final upload = ref.read(uploadControllerProvider.notifier);
    final config = ref.read(configProvider);
    // B04: rekod gagal lama dibersihkan automatik oleh onBatchSucceeded.
    final result = await upload.start(
      items: items,
      config: config,
      caption: '',
      maxFileMB: ref.read(settingsProvider).maxFileMB,
    );
    if (context.mounted) {
      showAppSnackBar(context, result.message,
          success: result.isGood, error: !result.isGood);
    }
    ref.read(failedProvider.notifier).load();
    ref.read(historyProvider.notifier).load();
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.record});
  final FailedRecord record;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(LucideIcons.alertCircle, size: 15, color: AppColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.fileName,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // 4c: mesej ralat penuh — boleh dipilih, balut penuh
                // (dulu TIDAK dipapar langsung, bukan sekadar terpotong).
                SelectableText(
                  record.errorMessage,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                ),
              ],
            ),
          ),
          Text(
            formatClockShort(record.createdAt),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
