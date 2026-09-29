import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/media_providers.dart';
import '../../widgets/common.dart';

/// Pratonton mesej ala Discord — menunjukkan rupa mesej sebenar:
/// avatar, nama bot, badge APP, teks, dan thumbnail batch pertama.
class MessagePreview extends ConsumerWidget {
  const MessagePreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(configProvider);
    final caption = ref.watch(captionProvider);
    final items = ref.watch(mediaListProvider);
    final firstBatch = items.where((m) => m.status.canSend).take(10).toList();
    final thumbs = firstBatch.take(4).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Discord Message Preview'),
        AppCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Avatar(url: config.avatarUrl, name: config.botName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  config.mode == SendMode.bot
                                      ? 'Your Bot'
                                      : (config.botName.isEmpty
                                          ? 'Bot Name'
                                          : config.botName),
                                  style: Theme.of(context).textTheme.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const AppTag(),
                              const SizedBox(width: 6),
                              Text(
                                'Today at ${formatClockShort(DateTime.now())}',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: AppColors.textFaint,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            caption.isEmpty
                                ? (firstBatch.isEmpty
                                    ? 'No message — pick media or write a caption'
                                    : 'No caption')
                                : caption,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: caption.isEmpty
                                      ? AppColors.textFaint
                                      : Theme.of(context).colorScheme.onSurface,
                                  fontStyle: caption.isEmpty ? FontStyle.italic : null,
                                ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (thumbs.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < thumbs.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                              right: i == thumbs.length - 1 ? 0 : 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: SizedBox(
                              width: 62,
                              height: 62,
                              child: _PreviewThumb(item: thumbs[i]),
                            ),
                          ),
                        ),
                      if (firstBatch.length > thumbs.length)
                        Container(
                          width: 62,
                          height: 62,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '+${firstBatch.length - thumbs.length}',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.paperclip,
                          size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(width: 5),
                      Text(
                        'First batch: ${firstBatch.length} files '
                        '(${formatBytes(firstBatch.fold<int>(0, (s, f) => s + f.sizeBytes))})',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name});
  final String url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final u = url.trim();
    final hasUrl = u.startsWith('http');
    return ClipOval(
      child: hasUrl
          ? Image.network(
              u,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Container(
        width: 40,
        height: 40,
        color: AppColors.blurple,
        alignment: Alignment.center,
        child: const Icon(LucideIcons.bot, size: 20, color: Colors.white),
      );
}

class _PreviewThumb extends StatelessWidget {
  const _PreviewThumb({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    if (item.type == MediaType.image) {
      return Image.file(
        File(item.path),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _ThumbFallback(icon: LucideIcons.image),
      );
    }
    return Container(
      color: AppColors.surfaceHigh,
      child: const Center(
        child: Icon(LucideIcons.video, size: 20, color: AppColors.textFaint),
      ),
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surfaceHigh,
        child: Center(child: Icon(icon, size: 18, color: AppColors.textFaint)),
      );
}
