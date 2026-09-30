import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../providers/config_providers.dart';
import '../../root_shell.dart';

/// Onboarding 3 skrin ringkas kali pertama:
/// 1. Cara dapat URL Webhook
/// 2. Cara dapat Bot Token + Channel ID
/// 3. Pilih media/folder & hantar
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.asPage = false});
  final bool asPage;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _ctrl = PageController();
  int _page = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    HapticFeedback.mediumImpact();
    await ref.read(settingsProvider.notifier).completeOnboarding();
    if (!mounted) return;
    if (widget.asPage) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const RootShell()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= AppBreakpoints.compact;
    final isLast = _page == 2;

    final pages = const [
      _OnboardingPage(
        icon: LucideIcons.globe,
        title: 'Connect with a Webhook',
        steps: [
          'Open Server Settings in Discord > Integrations > Webhooks',
          'Tap "New Webhook" and pick the target channel',
          'Copy the Webhook URL and paste it into the app',
        ],
        note: 'A webhook is the fastest way — no bot creation needed.',
      ),
      _OnboardingPage(
        icon: LucideIcons.bot,
        title: 'Or Use a Bot Token',
        steps: [
          'Open discord.com/developers/applications > New Application',
          'Go to the Bot tab > Reset Token > copy the token',
          'Add the bot to your server, then enter the Channel ID\n(Enable Developer Mode > right-click the channel > Copy ID)',
        ],
        note: 'Bot mode lets you pick/create channels directly from the app.',
      ),
      _OnboardingPage(
        icon: LucideIcons.upload,
        title: 'Pick & Send',
        steps: [
          'Pick Media, a whole Folder (Sent Folder) or a ZIP file',
          'ZIP files are extracted automatically',
          'Write a caption (optional) and tap Send',
        ],
        note: 'Progress is tracked on the Responses screen; sending keeps running in the background.',
      ),
    ];

    final content = Column(
      children: [
        Expanded(
          child: PageView(
            controller: _ctrl,
            onPageChanged: (i) {
              HapticFeedback.selectionClick();
              setState(() => _page = i);
            },
            children: pages,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    AnimatedContainer(
                      duration: AppMotion.fast,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? AppColors.blurple
                            : AppColors.outline,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(140, 50)),
                    onPressed: () {
                      if (isLast) {
                        _finish();
                      } else {
                        _ctrl.nextPage(
                          duration: AppMotion.slow,
                          curve: AppMotion.ease,
                        );
                      }
                    },
                    icon: Text(isLast ? 'Start' : 'Next'),
                    label: Icon(
                      isLast ? LucideIcons.send : LucideIcons.chevronRight,
                      size: 17,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final scaffold = Scaffold(
      body: SafeArea(
        child: wide
            ? Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
                  child: content,
                ),
              )
            : content,
      ),
    );

    return scaffold;
  }
}

class _OnboardingPage extends StatelessWidget {
  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.steps,
    required this.note,
  });

  final IconData icon;
  final String title;
  final List<String> steps;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            const SizedBox(height: 24),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSecondaryContainer),
            ),
            const SizedBox(height: 24),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 18),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppColors.blurple,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.info, size: 15, color: AppColors.blurpleBright),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      note,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
