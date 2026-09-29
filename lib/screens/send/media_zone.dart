import 'dart:io' show File;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/formatters.dart';
import '../../models/models.dart';
import '../../providers/media_providers.dart';
import '../../widgets/common.dart';

/// Zon pilih media: 3 tindakan jelas (Media / Folder / ZIP) + ringkasan.
class MediaZone extends ConsumerWidget {
  const MediaZone({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(mediaListProvider);
    final ready = items.where((m) => m.status.canSend).length;
    final skipped = items.length - ready;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Pilih Media',
          trailing: items.isEmpty
              ? null
              : TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 36),
                    foregroundColor: AppColors.danger,
                  ),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Kosongkan semua?',
                      message: '${items.length} fail akan dibuang daripada senarai.',
                      confirmLabel: 'Kosongkan',
                    );
                    if (ok) ref.read(mediaListProvider.notifier).clearAll();
                  },
                  icon: const Icon(LucideIcons.trash2, size: 14),
                  label: const Text('Kosongkan'),
                ),
        ),
        Row(
          children: [
            Expanded(
              child: _PickAction(
                icon: LucideIcons.image,
                label: 'Media',
                hint: 'Gambar / video',
                onTap: () => _pick(context, ref, PickAction.files),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PickAction(
                icon: LucideIcons.folder,
                label: 'Folder',
                hint: 'Semua subfolder',
                onTap: () => _pick(context, ref, PickAction.folder),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PickAction(
                icon: LucideIcons.fileArchive,
                label: 'ZIP',
                hint: 'Ekstrak automatik',
                onTap: () => _pick(context, ref, PickAction.zip),
              ),
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text(
                '${items.length} fail dipilih',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: 8),
              SoftBadge('$ready sedia', color: AppColors.success, icon: LucideIcons.check),
              if (skipped > 0) ...[
                const SizedBox(width: 6),
                SoftBadge('$skipped dilangkau', color: AppColors.warning),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, PickAction action) async {
    HapticFeedbackHelper.light();
    final notifier = ref.read(mediaListProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final info = await notifier.pick(action);
    if (info != null && info.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(info)));
    }
  }
}

class _PickAction extends StatelessWidget {
  const _PickAction({required this.icon, required this.label, required this.hint, required this.onTap});
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: Theme.of(context).dividerTheme.color ?? AppColors.outline),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSecondaryContainer),
              const SizedBox(height: 8),
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                hint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11.5,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tile grid media dengan thumbnail, badge saiz & jenis, butang buang.
class MediaTile extends ConsumerWidget {
  const MediaTile({super.key, required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isProblem = !item.status.canSend;
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: _thumb(context, ref),
              ),
              if (isProblem)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(color: Colors.black54),
                ),
              if (isProblem)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Text(
                      item.note ?? 'Dilangkau',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w700,
                          ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              // Badge jenis video
              if (item.type == MediaType.video && !isProblem)
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Icon(LucideIcons.video, size: 11, color: Colors.white),
                  ),
                ),
              // Badge saiz
              Positioned(
                bottom: 5,
                right: 5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    formatBytes(item.sizeBytes),
                    style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              // Butang buang
              Positioned(
                top: 0,
                right: 0,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      HapticFeedbackHelper.selection();
                      ref.read(mediaListProvider.notifier).remove(item.id);
                    },
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(LucideIcons.x, size: 12, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.name,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _thumb(BuildContext context, WidgetRef ref) {
    if (item.type == MediaType.video) {
      final thumb = ref.watch(videoThumbProvider(item.path));
      return thumb.when(
        data: (data) => data != null
            ? Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true)
            : _fallback(Colors.redAccent),
        loading: () => _fallback(null),
        error: (_, _) => _fallback(Colors.redAccent),
      );
    }
    final file = File(item.path);
    return Image.file(
      file,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _fallback(null),
    );
  }

  Widget _fallback(Color? accent) => Container(
        color: AppColors.surfaceHigh,
        child: Center(
          child: Icon(
            item.type == MediaType.video ? LucideIcons.video : LucideIcons.image,
            size: 22,
            color: accent ?? AppColors.textFaint,
          ),
        ),
      );
}

/// Helper haptic ringan (dikekal di sini untuk keseragaman skrin Hantar).
class HapticFeedbackHelper {
  HapticFeedbackHelper._();
  static void light() => HapticFeedback.lightImpact();
  static void selection() => HapticFeedback.selectionClick();
}
