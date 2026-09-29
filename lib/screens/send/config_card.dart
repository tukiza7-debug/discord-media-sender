import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/app_theme.dart';
import '../../core/error_translator.dart';
import '../../models/models.dart';
import '../../providers/config_providers.dart';
import '../../services/discord_api.dart';
import '../../widgets/common.dart';

/// Kad konfigurasi boleh lipat — mod Webhook / Bot + uji sambungan.
class ConfigCard extends ConsumerStatefulWidget {
  const ConfigCard({super.key});

  @override
  ConsumerState<ConfigCard> createState() => _ConfigCardState();
}

class _ConfigCardState extends ConsumerState<ConfigCard> {
  bool _expanded = true;
  bool _testing = false;
  TestResult? _testResult;
  bool _obscureToken = true;

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);

    return AppCard(
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      config.mode == SendMode.webhook ? LucideIcons.globe : LucideIcons.bot,
                      size: 17,
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Send Configuration',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 2),
                        Text(
                          config.readyToSend
                              ? (config.mode == SendMode.webhook
                                  ? 'Webhook • ready'
                                  : 'Bot • #${config.channelName.isEmpty ? config.channelId : config.channelName}')
                              : 'Not set up yet',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: config.readyToSend
                                    ? AppColors.success
                                    : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0 : -0.25,
                    duration: AppMotion.fast,
                    child: const Icon(LucideIcons.chevronDown, size: 18),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppMotion.normal,
            curve: AppMotion.ease,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<SendMode>(
                          segments: const [
                            ButtonSegment(
                                value: SendMode.webhook,
                                icon: Icon(LucideIcons.globe, size: 16),
                                label: Text('Webhook')),
                            ButtonSegment(
                                value: SendMode.bot,
                                icon: Icon(LucideIcons.bot, size: 16),
                                label: Text('Bot')),
                          ],
                          selected: {config.mode},
                          onSelectionChanged: (s) {
                            HapticFeedback.selectionClick();
                            ref.read(configProvider.notifier).setMode(s.first);
                            setState(() => _testResult = null);
                          },
                        ),
                        const SizedBox(height: 14),
                        if (config.mode == SendMode.webhook)
                          _WebhookFields(
                            onResult: (r) => setState(() => _testResult = r),
                          )
                        else
                          _BotFields(
                            onResult: (r) => setState(() => _testResult = r),
                            obscureToken: _obscureToken,
                            toggleObscure: () =>
                                setState(() => _obscureToken = !_obscureToken),
                          ),
                        const SizedBox(height: 12),
                        _TestSection(
                          testing: _testing,
                          result: _testResult,
                          onTest: () => _runTest(config),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Future<void> _runTest(SendConfig config) async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final api = DiscordApi.instance;
    TestResult result;
    if (config.mode == SendMode.webhook) {
      result = await api.testWebhook(config.webhookUrl);
    } else {
      result = await api.testBot(config.botToken, config.channelId);
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result;
    });
    showAppSnackBar(context, result.message, success: result.ok, error: !result.ok);
  }
}

// ---------------------------------------------------------------- webhook

class _WebhookFields extends ConsumerStatefulWidget {
  const _WebhookFields({required this.onResult});
  final void Function(TestResult) onResult;

  @override
  ConsumerState<_WebhookFields> createState() => _WebhookFieldsState();
}

class _WebhookFieldsState extends ConsumerState<_WebhookFields> {
  late final _urlCtrl = TextEditingController(text: ref.read(configProvider).webhookUrl);
  late final _nameCtrl = TextEditingController(text: ref.read(configProvider).botName);
  late final _avatarCtrl = TextEditingController(text: ref.read(configProvider).avatarUrl);

  @override
  void dispose() {
    _urlCtrl.dispose();
    _nameCtrl.dispose();
    _avatarCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          autofillHints: const [AutofillHints.url],
          onChanged: (v) => ref.read(configProvider.notifier).setWebhookUrl(v),
          decoration: const InputDecoration(
            labelText: 'URL Webhook',
            hintText: 'https://discord.com/api/webhooks/...',
            prefixIcon: Icon(LucideIcons.link, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                onChanged: (v) => ref.read(configProvider.notifier).setBotName(v),
                decoration: const InputDecoration(
                  labelText: 'Bot name (optional)',
                  hintText: 'Media Sender',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _avatarCtrl,
                keyboardType: TextInputType.url,
                onChanged: (v) => ref.read(configProvider.notifier).setAvatarUrl(v),
                decoration: const InputDecoration(
                  labelText: 'Avatar URL (optional)',
                  hintText: 'https://...',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- bot

class _BotFields extends ConsumerStatefulWidget {
  const _BotFields({
    required this.onResult,
    required this.obscureToken,
    required this.toggleObscure,
  });

  final void Function(TestResult) onResult;
  final bool obscureToken;
  final VoidCallback toggleObscure;

  @override
  ConsumerState<_BotFields> createState() => _BotFieldsState();
}

class _BotFieldsState extends ConsumerState<_BotFields> {
  late final _tokenCtrl = TextEditingController(text: ref.read(configProvider).botToken);
  late final _channelCtrl = TextEditingController(text: ref.read(configProvider).channelId);

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _channelCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _tokenCtrl,
          obscureText: widget.obscureToken,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (v) => ref.read(configProvider.notifier).setBotToken(v),
          decoration: InputDecoration(
            labelText: 'Bot Token',
            hintText: 'Paste the token from the Developer Portal',
            prefixIcon: const Icon(LucideIcons.lock, size: 18),
            suffixIcon: IconButton(
              icon: Icon(
                  widget.obscureToken ? LucideIcons.eyeOff : LucideIcons.eye,
                  size: 18),
              onPressed: widget.toggleObscure,
              tooltip: widget.obscureToken ? 'Show' : 'Hide',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _channelCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) =>
                    ref.read(configProvider.notifier).setChannel(id: v),
                decoration: const InputDecoration(
                  labelText: 'Channel ID',
                  hintText: 'Example: 1234567890123456789',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _openChannelPicker(context, ref),
              icon: const Icon(LucideIcons.hash, size: 16),
              label: const Text('Pick'),
            ),
          ],
        ),
        if (config.channelName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(LucideIcons.hash, size: 13, color: AppColors.textFaint),
                const SizedBox(width: 4),
                Text(
                  'Selected channel: #${config.channelName}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _openCreateChannel(context, ref),
            icon: const Icon(LucideIcons.plus, size: 16),
            label: const Text('Create new channel'),
          ),
        ),
      ],
    );
  }

  Future<void> _openChannelPicker(BuildContext context, WidgetRef ref) async {
    final config = ref.read(configProvider);
    if (config.botToken.trim().isEmpty) {
      showAppSnackBar(context, 'Enter the bot token first.', error: true);
      return;
    }
    final sel = await showModalBottomSheet<ChannelInfo>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ChannelPickerSheet(token: config.botToken.trim()),
    );
    if (sel != null) {
      _channelCtrl.text = sel.id;
      await ref.read(configProvider.notifier).setChannel(id: sel.id, name: sel.name);
      if (context.mounted) {
        showAppSnackBar(context, 'Channel selected: #${sel.name}', success: true);
      }
    }
  }

  Future<void> _openCreateChannel(BuildContext context, WidgetRef ref) async {
    final config = ref.read(configProvider);
    if (config.botToken.trim().isEmpty) {
      showAppSnackBar(context, 'Enter the bot token first.', error: true);
      return;
    }
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateChannelSheet(token: config.botToken.trim()),
    );
  }
}

// ---------------------------------------------------------- sheet channel

class _ChannelPickerSheet extends StatefulWidget {
  const _ChannelPickerSheet({required this.token});
  final String token;

  @override
  State<_ChannelPickerSheet> createState() => _ChannelPickerSheetState();
}

class _ChannelPickerSheetState extends State<_ChannelPickerSheet> {
  late Future<List<GuildInfo>> _guilds;
  GuildInfo? _selectedGuild;
  Future<List<ChannelInfo>>? _channels;

  @override
  void initState() {
    super.initState();
    _guilds = DiscordApi.instance.fetchGuilds(widget.token);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          maxWidth: 560,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pick a Channel', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('Pick a server, then pick a text channel.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
              const SizedBox(height: 16),
              FutureBuilder<List<GuildInfo>>(
                future: _guilds,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return Text(
                      'Failed to load servers: ${ErrorTranslator.explain(error: snap.error).title}',
                      style: const TextStyle(color: AppColors.danger),
                    );
                  }
                  final guilds = snap.data ?? [];
                  if (guilds.isEmpty) {
                    return const Text('No servers found for this bot.');
                  }
                  return Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: guilds.length,
                      itemBuilder: (context, i) {
                        final g = guilds[i];
                        final selected = _selectedGuild?.id == g.id;
                        return ListTile(
                          leading: Icon(
                            LucideIcons.globe,
                            size: 18,
                            color: selected ? AppColors.blurpleBright : null,
                          ),
                          title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          selected: selected,
                          onTap: () {
                            setState(() {
                              _selectedGuild = g;
                              _channels =
                                  DiscordApi.instance.fetchTextChannels(widget.token, g.id);
                            });
                          },
                        );
                      },
                    ),
                  );
                },
              ),
              if (_selectedGuild != null) ...[
                const Divider(height: 24),
                FutureBuilder<List<ChannelInfo>>(
                  future: _channels,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(
                            child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2))),
                      );
                    }
                    if (snap.hasError) {
                      return const Text('Failed to load channels.',
                          style: TextStyle(color: AppColors.danger));
                    }
                    final channels = snap.data ?? [];
                    if (channels.isEmpty) {
                      return const Text('No text channels in this server.');
                    }
                    return Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: channels.length,
                        itemBuilder: (context, i) {
                          final c = channels[i];
                          return ListTile(
                            leading: const Icon(LucideIcons.hash, size: 16),
                            title: Text(c.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            dense: true,
                            onTap: () => Navigator.of(context).pop(c),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CreateChannelSheet extends StatefulWidget {
  const _CreateChannelSheet({required this.token});
  final String token;

  @override
  State<_CreateChannelSheet> createState() => _CreateChannelSheetState();
}

class _CreateChannelSheetState extends State<_CreateChannelSheet> {
  final _nameCtrl = TextEditingController();
  late Future<List<GuildInfo>> _guilds;
  GuildInfo? _guild;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _guilds = DiscordApi.instance.fetchGuilds(widget.token);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_guild == null || _nameCtrl.text.trim().length < 2) return;
    setState(() => _creating = true);
    try {
      final ch = await DiscordApi.instance
          .createChannel(token: widget.token, guildId: _guild!.id, name: _nameCtrl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
      showAppSnackBar(context, 'Channel created: #${ch.name}', success: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      final expl = ErrorTranslator.explain(error: e);
      showAppSnackBar(context, 'Failed to create channel: ${expl.title}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Create a New Channel', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              FutureBuilder<List<GuildInfo>>(
                future: _guilds,
                builder: (context, snap) {
                  final guilds = snap.data ?? const [];
                  return DropdownButtonFormField<GuildInfo>(
                    initialValue: _guild,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Server',
                      prefixIcon: Icon(LucideIcons.globe, size: 18),
                    ),
                    items: [
                      for (final g in guilds)
                        DropdownMenuItem(
                          value: g,
                          child: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (g) => setState(() => _guild = g),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: const InputDecoration(
                  labelText: 'Channel name',
                  hintText: 'media-upload',
                  prefixIcon: Icon(LucideIcons.hash, size: 18),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _creating ? null : _create,
                icon: _creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(LucideIcons.plus, size: 17),
                label: Text(_creating ? 'Creating...' : 'Create Channel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ uji sambungan

class _TestSection extends StatelessWidget {
  const _TestSection({required this.testing, required this.result, required this.onTest});
  final bool testing;
  final TestResult? result;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: testing ? null : onTest,
          icon: testing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(LucideIcons.zap, size: 16),
          label: Text(testing ? 'Testing...' : 'Test Connection'),
        ),
        if (result != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                result!.ok ? LucideIcons.checkCircle : LucideIcons.alertCircle,
                size: 15,
                color: result!.ok ? AppColors.success : AppColors.danger,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result!.message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: result!.ok ? AppColors.success : AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
