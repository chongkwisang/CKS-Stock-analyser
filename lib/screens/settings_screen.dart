import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../ai/ai_config.dart';
import '../ai/ai_controller.dart';
import '../services/app_state.dart';
import '../services/updater.dart';
import '../l10n.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  PackageInfo? _info;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _info = i);
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    await Updater.checkAndPrompt(context);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppState.instance;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('Settings'))),
      body: ListenableBuilder(
        listenable: s,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: theme.colorScheme.primary,
                          child: Text(
                            'CKS',
                            style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'CKS Stock Analyser',
                                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              Text(
                                tf('Version {v} (build {b})', {
                                  'v': _info?.version ?? '…',
                                  'b': _info?.buildNumber ?? '…',
                                }),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, t('AI assistant')),
                Card(
                  child: ListenableBuilder(
                    listenable: AiConfig.instance,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.auto_awesome),
                      title: Text(t('Claude AI')),
                      subtitle: Text(
                        AiConfig.instance.useClaudeAccount
                            ? t('Your Claude account (claude.ai sign-in)')
                            : AiConfig.instance.signedIn
                            ? tf('Connected · {model}', {'model': AiConfig.instance.modelLabel})
                            : t('Not connected. Tap to sign in'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => AiController.instance.show(page: AiPage.settings),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, t('Updates')),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.system_update),
                        title: Text(t('Check for update')),
                        subtitle: Text(t('Download and install the latest version')),
                        trailing: _checking
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: _checking ? null : _check,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.autorenew),
                        title: Text(t('Check automatically on start')),
                        value: s.autoCheckUpdates,
                        onChanged: (v) => s.autoCheckUpdates = v,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16),
                _section(context, t('Appearance')),
                Card(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<ThemeMode>(
                            segments: [
                              ButtonSegment(
                                value: ThemeMode.light,
                                label: Text(t('Light')),
                                icon: Icon(Icons.light_mode),
                              ),
                              ButtonSegment(value: ThemeMode.dark, label: Text(t('Dark')), icon: Icon(Icons.dark_mode)),
                              ButtonSegment(
                                value: ThemeMode.system,
                                label: Text(t('System')),
                                icon: Icon(Icons.phone_android),
                              ),
                            ],
                            selected: {s.themeMode},
                            onSelectionChanged: (v) => s.themeMode = v.first,
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.candlestick_chart),
                        title: Text(t('Candlestick charts')),
                        subtitle: Text(t('Off = line charts')),
                        value: s.candles,
                        onChanged: (v) => s.candles = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, t('Language')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'en', label: Text('English')),
                        ButtonSegment(value: 'zh', label: Text('简体中文')),
                      ],
                      selected: {s.language},
                      onSelectionChanged: (v) => s.language = v.first,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, t('About')),
                Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text(t('Data & disclaimer')),
                    subtitle: Text(
                      t(
                        t(
                          t(
                            'Market data from Yahoo Finance, may be delayed. Analysis is for information only and is not financial advice.',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      t.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.primary, letterSpacing: 1.2),
    ),
  );
}
