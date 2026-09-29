import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/models.dart';
import '../../providers/upload_providers.dart';
import '../../widgets/common.dart';

/// Kad progres besar: bar animasi + statistik + Jeda/Sambung/Batal.
/// Landskap: statistik disusun mendatar.
class ProgressCard extends ConsumerWidget {
  const ProgressCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(uploadControllerProvider);
    final p = upload.progress;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalStats = width >= AppBreakpoints.compact;

    final stateColor = switch (upload.state) {
      EngineState.paused => AppColors.warning,
      EngineState.cancelling => AppColors.danger,
      _ => AppColors.blurple,
    };

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: stateColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: upload.state == EngineState.paused
                      ? Icon(LucideIcons.pause, size: 17, color: stateColor)
                      : Icon(LucideIcons.upload, size: 17, color: stateColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        upload.state == EngineState.paused
                            ? 'Upload Paused'
                            : (upload.state == EngineState.cancelling
                                ? 'Cancelling...'
                                : 'Sending to Discord'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Batch ${p.currentBatch}/${p.totalBatches} • '
                        '${p.successFiles} succeeded • ${p.failedFiles} failed',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Text(
                  formatPercent(p.fraction),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: stateColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: p.fraction),
                duration: AppMotion.normal,
                curve: AppMotion.ease,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 8,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _Stats(p: p, horizontal: horizontalStats),
            if (p.message != null) ...[
              const SizedBox(height: 10),
              Text(
                p.message!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 14),
            _Controls(),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.p, required this.horizontal});
  final UploadProgress p;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final cells = [
      _StatCell(
        icon: LucideIcons.checkCircle,
        color: AppColors.success,
        label: 'Succeeded',
        value: '${p.successFiles}',
      ),
      _StatCell(
        icon: LucideIcons.alertCircle,
        color: AppColors.danger,
        label: 'Failed',
        value: '${p.failedFiles}',
      ),
      _StatCell(
        icon: LucideIcons.zap,
        color: AppColors.info,
        label: 'Speed',
        value: formatSpeed(p.speedMBps),
      ),
      _StatCell(
        icon: LucideIcons.upload,
        color: AppColors.blurpleBright,
        label: 'Uploaded',
        value: formatBytes(p.uploadedBytes),
      ),
    ];

    if (horizontal) {
      return Row(
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            Expanded(child: cells[i]),
            if (i != cells.length - 1) const SizedBox(width: 8),
          ],
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: cells[0]),
        Expanded(child: cells[1]),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(uploadControllerProvider);
    final controller = ref.read(uploadControllerProvider.notifier);
    final paused = upload.state == EngineState.paused;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              if (paused) {
                controller.resume();
              } else {
                controller.pause();
              }
            },
            icon: Icon(paused ? LucideIcons.play : LucideIcons.pause, size: 16),
            label: Text(paused ? 'Resume' : 'Pause'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: () => controller.cancel(),
            icon: const Icon(LucideIcons.x, size: 16),
            label: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}
