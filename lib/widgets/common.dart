import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/app_theme.dart';
import '../core/formatters.dart';
import '../models/models.dart';

/// Kad asas aplikasi (permukaan + sempadan halus, tiada bayang berat).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      margin: margin ?? EdgeInsets.zero,
      child: padding == null
          ? child
          : Padding(padding: padding!, child: child),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppRadius.lg), child: card);
  }
}

/// Label seksyen kecil (huruf besar, jarak huruf).
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    letterSpacing: 0.8,
                  ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Warna status mengikut kod HTTP / jenis ralat.
Color statusColor(BuildContext context, {int? statusCode, required LogStatus status}) {
  if (status == LogStatus.success) return AppColors.success;
  if (status == LogStatus.rateLimited) return AppColors.warning;
  if (status == LogStatus.cancelled) return AppColors.textFaint;
  if (status == LogStatus.networkError) return AppColors.danger;
  if (statusCode != null && statusCode >= 500) return AppColors.danger;
  if (statusCode != null && statusCode >= 400) return AppColors.warning;
  return AppColors.danger;
}

/// Lencana status HTTP berwarna (2xx hijau, 4xx kuning, 5xx merah).
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.statusCode,
    this.label,
    this.small = false,
  });

  final LogStatus status;
  final int? statusCode;
  final String? label;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final color = statusColor(context, status: status, statusCode: statusCode);
    final text = label ??
        (statusCode?.toString() ?? (status == LogStatus.networkError ? 'RANGKAIAN' : '—'));
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : AppSpacing.sm,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
      ),
    );
  }
}

/// Lencana kecil generik.
class SoftBadge extends StatelessWidget {
  const SoftBadge(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final i?) ...[
            Icon(i, size: 12, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: c, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Badge "APP" ala Discord.
class AppTag extends StatelessWidget {
  const AppTag({super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: AppColors.blurple,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'APP',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Skrin kosong dengan ilustrasi ikon ringkas + teks berguna.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: Theme.of(context).colorScheme.onSecondaryContainer),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kad khas 429 dengan kira detik sebelum cuba semula automatik.
class RateLimitCountdown extends StatefulWidget {
  const RateLimitCountdown({super.key, required this.retryAfterMs, required this.startedAt});
  final int retryAfterMs;
  final DateTime startedAt;

  @override
  State<RateLimitCountdown> createState() => _RateLimitCountdownState();
}

class _RateLimitCountdownState extends State<RateLimitCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.startedAt).inMilliseconds;
    final remaining = (widget.retryAfterMs - elapsed).clamp(0, widget.retryAfterMs);
    final done = remaining <= 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(LucideIcons.clock, size: 13, color: AppColors.warning),
        const SizedBox(width: 5),
        Text(
          done
              ? 'Menyambung semula...'
              : 'Tunggu ${formatCountdown(remaining)} sebelum cuba semula automatik',
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Snackbar kemas dengan haptic ringan.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool success = false,
  bool error = false,
}) {
  if (success) HapticFeedback.mediumImpact();
  if (error) HapticFeedback.heavyImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              success
                  ? LucideIcons.checkCircle2
                  : (error ? LucideIcons.alertTriangle : LucideIcons.info),
              size: 17,
              color: success
                  ? AppColors.success
                  : (error ? AppColors.danger : AppColors.blurpleBright),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        duration: Duration(milliseconds: error || success ? 2600 : 1800),
      ),
    );
}

/// Dialog pengesahan ringkas.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Padam',
  bool destructive = true,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: AppColors.danger)
              : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return res == true;
}
