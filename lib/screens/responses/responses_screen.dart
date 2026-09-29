import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../core/security.dart';
import '../../models/models.dart';
import '../../providers/response_providers.dart';
import '../../widgets/common.dart';
import 'response_detail.dart';

/// Skrin Respons — log masa nyata respons Discord.
/// Potret: senarai + butiran sebagai halaman. Landscape: master-detail.
class ResponsesScreen extends ConsumerWidget {
  const ResponsesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(filteredResponsesProvider);
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.compact;

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Flexible(
                flex: 5,
                child: _ListPane(entries: entries, wide: true),
              ),
              const VerticalDivider(width: 1),
              Flexible(
                flex: 6,
                child: _DetailPane(entries: entries),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(child: _ListPane(entries: entries, wide: false)),
    );
  }
}

// -------------------------------------------------------------- list pane

class _ListPane extends ConsumerStatefulWidget {
  const _ListPane({required this.entries, required this.wide});
  final List<ResponseLogEntry> entries;
  final bool wide;

  @override
  ConsumerState<_ListPane> createState() => _ListPaneState();
}

class _ListPaneState extends ConsumerState<_ListPane> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final summary = ref.watch(responseSummaryProvider);
    final filter = ref.watch(responseFilterProvider);
    final console = ref.watch(consoleModeProvider);
    final autoScroll = ref.watch(autoScrollProvider);
    final entries = widget.entries;

    // Auto-scroll ke atas (entri terbaru) bila log baharu masuk.
    ref.listen<int>(responseLogCountProvider, (prev, next) {
      if (next > (prev ?? 0) && autoScroll && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: AppMotion.normal,
          curve: AppMotion.ease,
        );
      }
    });

    return Column(
      children: [
        // Ringkasan atas
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _SummaryRow(summary: summary),
        ),
        // Bar tindakan: penapis + carian + mod konsol
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        onChanged: (v) =>
                            ref.read(responseQueryProvider.notifier).state = v,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: 'Search status code or file name...',
                          prefixIcon: const Icon(LucideIcons.search, size: 16),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          filled: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _IconToggle(
                    active: console,
                    icon: LucideIcons.terminal,
                    tooltip: 'Console mode',
                    onTap: () =>
                        ref.read(consoleModeProvider.notifier).state = !console,
                  ),
                  _IconToggle(
                    active: autoScroll,
                    icon: LucideIcons.chevronDown,
                    tooltip: 'Auto-scroll',
                    onTap: () =>
                        ref.read(autoScrollProvider.notifier).state = !autoScroll,
                  ),
                  _IconToggle(
                    active: false,
                    icon: LucideIcons.download,
                    tooltip: 'Export log',
                    onTap: () => _exportLog(context, ref),
                  ),
                  _IconToggle(
                    active: false,
                    icon: LucideIcons.trash2,
                    tooltip: 'Clear log',
                    danger: true,
                    onTap: () => _clearLog(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final f in ResponseFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.label),
                          selected: filter == f,
                          onSelected: (_) =>
                              ref.read(responseFilterProvider.notifier).state = f,
                          labelStyle: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Senarai kad
        Expanded(
          child: console
              ? Container(
                  color: AppColors.consoleBg,
                  child: entries.isEmpty
                      ? const Center(
                          child: Text(
                            'No responses yet. Send something to see Discord responses here.',
                            style: TextStyle(color: AppColors.textFaint, fontSize: 12.5),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _ConsoleList(entries: entries, scrollCtrl: _scrollCtrl, wide: widget.wide),
                )
              : entries.isEmpty
                  ? EmptyState(
                      icon: LucideIcons.inbox,
                      title: 'No responses yet',
                      subtitle:
                          'Send something to see Discord responses here.',
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: entries.length,
                      itemBuilder: (context, i) => ResponseCard(
                        entry: entries[i],
                        selected: false,
                        onTap: () => _openDetail(context, ref, entries[i]),
                      ),
                    ),
        ),
      ],
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref, ResponseLogEntry e) {
    ref.read(selectedResponseIdProvider.notifier).state = e.id;
    if (!widget.wide) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Response Details')),
            body: SafeArea(child: ResponseDetailView(entry: e)),
          ),
        ),
      );
    }
  }

  Future<void> _exportLog(BuildContext context, WidgetRef ref) async {
    final entries = ref.read(responseLogProvider);
    if (entries.isEmpty) {
      showAppSnackBar(context, 'No log entries to export.');
      return;
    }
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(LucideIcons.fileArchive),
              title: const Text('Export as JSON'),
              onTap: () => Navigator.pop(ctx, 'json'),
            ),
            ListTile(
              leading: const Icon(LucideIcons.fileArchive),
              title: const Text('Export as TXT'),
              onTap: () => Navigator.pop(ctx, 'txt'),
            ),
          ],
        ),
      ),
    );
    if (pick == null || !context.mounted) return;

    // Keselamatan: data log sentiasa ditapis sejak dicipta — tulis terus.
    // B25: sanitizeText turut dipakai pada EKSPORT JSON (pertahanan
    // mendalam — sama seperti TXT), bukan hanya TXT.
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final content = pick == 'json'
        ? Security.sanitizeText(const JsonEncoder.withIndent('  ').convert([
            for (final e in entries)
              {
                'batch': e.batchNumber,
                'method': e.method,
                'endpoint': e.endpoint,
                'status_code': e.statusCode,
                'status': e.status.name,
                'latency_ms': e.latencyMs,
                'upload_bytes': e.uploadBytes,
                'speed_mbps': e.speedMBps,
                'attempt': e.attempt,
                'timestamp': e.timestamp.toIso8601String(),
                'files': e.fileNames,
                'rate_limit_headers': e.rateLimitHeaders,
                'response': e.responseJson,
                'error': e.errorMessage,
                'explanation': e.explanation,
              }
          ]))
        : Security.sanitizeText([
            for (final e in entries)
              '[${formatDateTime(e.timestamp)}] #${e.batchNumber} ${e.method} ${e.endpoint} '
                  '-> ${e.statusCode ?? '-'} ${e.status.name} ${e.latencyMs}ms '
                  '${e.errorMessage ?? ''}',
          ].join('\n'));

    try {
      final uri = await FilePicker.saveFile(
        fileName: 'dms_log_$stamp.${pick == 'json' ? 'json' : 'txt'}',
        bytes: utf8.encode(content),
        mimeType: pick == 'json' ? 'application/json' : 'text/plain',
      );
      if (uri != null && context.mounted) {
        showAppSnackBar(context, 'Log exported to $uri', success: true);
      }
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, 'Export cancelled.', error: true);
    }
  }

  Future<void> _clearLog(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Clear the log?',
      message: 'All in-memory response entries will be discarded. '
          'Persistent errors remain in the History & Failed screens.',
      confirmLabel: 'Clear',
    );
    if (ok) {
      ref.read(responseLogProvider.notifier).clear();
      HapticFeedback.mediumImpact();
    }
  }
}

// --------------------------------------------------------------- summary

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.summary});
  final ResponseSummary summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _SummaryCell(label: 'Requests', value: '${summary.total}')),
        Expanded(child: _SummaryCell(label: 'Succeeded', value: '${summary.success}', color: AppColors.success)),
        Expanded(child: _SummaryCell(label: 'Failed', value: '${summary.failed}', color: AppColors.danger)),
        Expanded(child: _SummaryCell(label: 'Average', value: formatMs(summary.avgLatencyMs), color: AppColors.info)),
        Expanded(
          child: _SummaryCell(
            label: 'Rate Limit',
            value: summary.rateLimitedNow ? 'ACTIVE' : 'OK',
            color: summary.rateLimitedNow ? AppColors.warning : AppColors.success,
          ),
        ),
      ],
    );
  }
}

class _SummaryCell extends StatelessWidget {
  const _SummaryCell({required this.label, required this.value, this.color});
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
                letterSpacing: 0.5,
              ),
          maxLines: 1,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _IconToggle extends StatelessWidget {
  const _IconToggle({
    required this.active,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });
  final bool active;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(left: 6),
          decoration: BoxDecoration(
            color: active
                ? (danger ? AppColors.danger.withValues(alpha: 0.15) : Theme.of(context).colorScheme.secondaryContainer)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: active
                  ? (danger ? AppColors.danger : AppColors.blurple)
                  : Theme.of(context).dividerTheme.color ?? AppColors.outline,
            ),
          ),
          child: Icon(
            icon,
            size: 17,
            color: danger && !active ? AppColors.danger : null,
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- kad respons

/// Kad log respons (boleh dipakai dalam senarai & master-detail).
class ResponseCard extends StatelessWidget {
  const ResponseCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.selected = false,
    this.console = false,
  });

  final ResponseLogEntry entry;
  final VoidCallback onTap;
  final bool selected;
  final bool console;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(context, status: entry.status, statusCode: entry.statusCode);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? Theme.of(context).colorScheme.secondaryContainer : Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? AppColors.blurple : color.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Talian warna status
                Container(width: 4, decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppRadius.md)))),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: console ? _consoleBody(context) : _normalBody(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _normalBody(BuildContext context) {
    final color = statusColor(context, status: entry.status, statusCode: entry.statusCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                entry.batchNumber == 0
                    ? 'Test Connection / Info'
                    : 'Batch ${entry.batchNumber}/${entry.totalBatches} • ${entry.fileCount} files',
                style: Theme.of(context).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StatusBadge(status: entry.status, statusCode: entry.statusCode, small: true),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${entry.method} ${entry.endpoint}',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        if (entry.status == LogStatus.rateLimited && entry.retryAfterMs != null)
          RateLimitCountdown(retryAfterMs: entry.retryAfterMs!, startedAt: entry.timestamp)
        else
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _Meta(icon: LucideIcons.clock, text: formatMs(entry.latencyMs)),
              if (entry.uploadBytes > 0)
                _Meta(icon: LucideIcons.upload, text: formatBytes(entry.uploadBytes)),
              if (entry.uploadBytes > 0 && entry.latencyMs > 0)
                _Meta(icon: LucideIcons.zap, text: formatSpeed(entry.speedMBps)),
              if (entry.attempt > 1)
                _Meta(icon: LucideIcons.rotateCcw, text: 'attempt ${entry.attempt}'),
              _Meta(icon: LucideIcons.clock, text: formatClock(entry.timestamp)),
            ],
          ),
        if (entry.explanation != null) ...[
          const SizedBox(height: 6),
          Text(
            entry.explanation!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  Widget _consoleBody(BuildContext context) {
    final monoStyle = Theme.of(context).textTheme.bodySmall;
    final color = statusColor(context, status: entry.status, statusCode: entry.statusCode);
    return Text.rich(
      TextSpan(
        style: monoStyle?.copyWith(
          color: AppColors.consoleText,
          fontFamily: 'monospace',
          fontSize: 12,
        ),
        children: [
          TextSpan(text: '[${formatClock(entry.timestamp)}] '),
          TextSpan(text: '#${entry.batchNumber} ', style: TextStyle(color: AppColors.blurpleBright)),
          TextSpan(text: '${entry.method} '),
          TextSpan(text: '${entry.statusCode ?? 'ERR'} ', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          TextSpan(text: '${entry.latencyMs}ms  '),
          TextSpan(text: entry.endpoint),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- mod konsol

class _ConsoleList extends StatelessWidget {
  const _ConsoleList({required this.entries, required this.scrollCtrl, required this.wide});
  final List<ResponseLogEntry> entries;
  final ScrollController scrollCtrl;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: entries.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ResponseCard(
          entry: entries[i],
          onTap: () {},
          selected: false,
          console: true,
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ detail pane

class _DetailPane extends ConsumerWidget {
  const _DetailPane({required this.entries});
  final List<ResponseLogEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedResponseIdProvider);
    ResponseLogEntry? selected;
    if (selectedId != null) {
      selected = entries.where((e) => e.id == selectedId).firstOrNull;
    }
    if (selected == null && entries.isNotEmpty) {
      selected = entries.first;
    }

    if (selected == null) {
      return const EmptyState(
        icon: LucideIcons.inbox,
        title: 'No responses yet',
        subtitle: 'Send something to see Discord responses here.',
      );
    }
    return ResponseDetailView(entry: selected);
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
