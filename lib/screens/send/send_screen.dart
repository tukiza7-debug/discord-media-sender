import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../models/models.dart';
import '../../providers/config_providers.dart';
import '../../providers/history_providers.dart';
import '../../providers/media_providers.dart';
import '../../providers/response_providers.dart';
import '../../providers/upload_providers.dart';
import '../../widgets/common.dart';
import 'config_card.dart';
import 'media_zone.dart';
import 'preview_card.dart';
import 'progress_card.dart';

/// Skrin Hantar — konfigurasi, pilih media, kapsyen, pratonton & butang
/// Hantar. Layout adaptif:
/// - potret: satu lajur scroll + bar sticky bawah
/// - landscape (>=600dp): dua lajur (kiri: konfigurasi+mesej, kanan: grid)
class SendScreen extends ConsumerWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppBreakpoints.compact;
    final upload = ref.watch(uploadControllerProvider);
    final running = upload.isRunning;

    if (wide) return _Landscape(running: running);
    return _Portrait(running: running);
  }
}

// ---------------------------------------------------------------- potret

class _Portrait extends ConsumerWidget {
  const _Portrait({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(mediaListProvider);
    final ready = items.where((m) => m.status.canSend).length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  if (running)
                    const SliverPadding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                      sliver: SliverToBoxAdapter(child: ProgressCard()),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _ResponsesBanner(),
                          const SizedBox(height: 12),
                          const ConfigCard(),
                          const SizedBox(height: 16),
                          const MediaZone(),
                          const SizedBox(height: 16),
                          const CaptionField(),
                          const SizedBox(height: 16),
                          const MessagePreview(),
                        ],
                      ),
                    ),
                  ),
                  _MediaGridSliver(items: items),
                  const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
                ],
              ),
            ),
            _BottomBar(readyCount: ready, running: running),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- landscape

class _Landscape extends ConsumerWidget {
  const _Landscape({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(mediaListProvider);
    final ready = items.where((m) => m.status.canSend).length;

    return Scaffold(
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Kiri: konfigurasi + mesej + tindakan
            Flexible(
              flex: 5,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (running) ...[const ProgressCard(), const SizedBox(height: 16)],
                  const _ResponsesBanner(),
                  const SizedBox(height: 12),
                  const ConfigCard(),
                  const SizedBox(height: 16),
                  const CaptionField(),
                  const SizedBox(height: 16),
                  _BottomBar(readyCount: ready, running: running, inline: true),
                  const SizedBox(height: 24),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            // Kanan: zon media + grid + pratonton
            Flexible(
              flex: 6,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const MediaZone(),
                  const SizedBox(height: 12),
                  const MessagePreview(),
                  const SizedBox(height: 12),
                  _MediaGridView(items: items, crossAxisCount: 5),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------- banner respons

class _ResponsesBanner extends ConsumerWidget {
  const _ResponsesBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(uploadControllerProvider);
    final hasActivity = upload.isRunning ||
        ref.watch(responseLogCountProvider) > 0 && upload.state == EngineState.done;
    return AnimatedSize(
      duration: AppMotion.normal,
      curve: AppMotion.ease,
      alignment: Alignment.topCenter,
      child: hasActivity
          ? Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () => ref.read(tabIndexProvider.notifier).state = 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Icon(LucideIcons.messageSquare,
                            size: 17, color: Theme.of(context).colorScheme.onSecondaryContainer),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            upload.isRunning
                                ? 'Hantaran sedang berjalan — Lihat Respons'
                                : 'Lihat Respons',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                                ),
                          ),
                        ),
                        Icon(LucideIcons.chevronRight,
                            size: 16, color: Theme.of(context).colorScheme.onSecondaryContainer),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }
}

// ------------------------------------------------------------- grid sliver

class _MediaGridSliver extends ConsumerWidget {
  const _MediaGridSliver({required this.items});
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppBreakpoints.compact;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: wide ? 5 : 3,
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 0.82,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => MediaTile(item: items[i]),
          childCount: items.length,
        ),
      ),
    );
  }
}

class _MediaGridView extends StatelessWidget {
  const _MediaGridView({required this.items, required this.crossAxisCount});
  final List<MediaItem> items;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) => MediaTile(item: items[i]),
    );
  }
}

// -------------------------------------------------------------- caption

class CaptionField extends ConsumerWidget {
  const CaptionField({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Mesej (pilihan)'),
        TextField(
          maxLength: 2000,
          minLines: 3,
          maxLines: 5,
          textInputAction: TextInputAction.newline,
          onChanged: (v) => ref.read(captionProvider.notifier).state = v,
          decoration: const InputDecoration(
            hintText: 'Tulis mesej untuk dihantar bersama batch pertama...',
          ),
          buildCounter: (context,
                  {required currentLength, required isFocused, maxLength}) =>
              Text(
            '$currentLength/$maxLength',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: currentLength >= 2000
                      ? AppColors.danger
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Kapsyen hanya dihantar bersama batch pertama.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- bottom bar

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.readyCount, required this.running, this.inline = false});
  final int readyCount;
  final bool running;
  final bool inline;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (running) return const _RunningBar();
    final canSend = readyCount > 0;
    final upload = ref.watch(uploadControllerProvider);

    final button = SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        icon: const Icon(LucideIcons.send, size: 18),
        label: Text(canSend ? 'Hantar ($readyCount fail)' : 'Pilih media dahulu'),
        onPressed: canSend ? () => _send(context, ref) : null,
      ),
    );

    if (inline) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (upload.lastFinishedStatus != null) ..._lastResult(context, upload),
          button,
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerTheme.color ?? AppColors.outline),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (upload.lastFinishedStatus != null) ..._lastResult(context, upload),
            button,
          ],
        ),
      ),
    );
  }

  List<Widget> _lastResult(BuildContext context, UploadUiState upload) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            const SizedBox(width: 4),
            Icon(LucideIcons.checkCircle, size: 15, color: AppColors.success),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                upload.progress.message ?? 'Sesi selesai',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _send(BuildContext context, WidgetRef ref) async {
    final config = ref.read(configProvider);
    final items = ref.read(mediaListProvider);
    final caption = ref.read(captionProvider);

    if (!config.readyToSend) {
      showAppSnackBar(context, 'Lengkapkan konfigurasi dahulu (URL webhook / token bot).',
          error: true);
      return;
    }

    final controller = ref.read(uploadControllerProvider.notifier);
    final result = await controller.start(items: items, config: config, caption: caption);

    // Segar semula sejarah & gagal.
    ref.read(historyProvider.notifier).load();
    ref.read(failedProvider.notifier).load();

    if (context.mounted && result != null) {
      showAppSnackBar(context, result, success: !result.startsWith('Gagal'));
    }
  }
}

class _RunningBar extends ConsumerWidget {
  const _RunningBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upload = ref.watch(uploadControllerProvider);
    final p = upload.progress;
    final controller = ref.read(uploadControllerProvider.notifier);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerTheme.color ?? AppColors.outline),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: () {
                if (upload.state == EngineState.paused) {
                  controller.resume();
                } else {
                  controller.pause();
                }
              },
              icon: Icon(
                upload.state == EngineState.paused ? LucideIcons.play : LucideIcons.pause,
                size: 20,
              ),
              tooltip: upload.state == EngineState.paused ? 'Sambung' : 'Jeda',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.message ?? 'Menghantar...',
                          style: Theme.of(context).textTheme.labelMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${p.successFiles}/${p.totalFiles}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: p.fraction),
                      duration: AppMotion.normal,
                      curve: AppMotion.ease,
                      builder: (context, v, _) =>
                          LinearProgressIndicator(value: v, minHeight: 6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Batalkan hantaran?',
                  message: 'Fail yang belum dihantar akan ditanda gagal/dibatalkan.',
                  confirmLabel: 'Batal Hantar',
                );
                if (ok) await controller.cancel();
              },
              icon: const Icon(LucideIcons.x, size: 20, color: AppColors.danger),
              tooltip: 'Batal',
            ),
          ],
        ),
      ),
    );
  }
}
