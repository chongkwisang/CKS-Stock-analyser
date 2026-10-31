import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../ai/ai_config.dart';
import '../ai/ai_controller.dart';
import '../services/app_state.dart';
import '../services/updater.dart';

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
      appBar: AppBar(title: const Text('Settings')),
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
                                'Version ${_info?.version ?? '…'} (build ${_info?.buildNumber ?? '…'})',
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
                _section(context, 'AI assistant'),
                Card(
                  child: ListenableBuilder(
                    listenable: AiConfig.instance,
                    builder: (context, _) => ListTile(
                      leading: const Icon(Icons.auto_awesome),
                      title: const Text('Claude AI'),
                      subtitle: Text(
                        AiConfig.instance.useClaudeAccount
                            ? 'Your Claude account (claude.ai sign-in)'
                            : AiConfig.instance.signedIn
                            ? 'Connected · ${AiConfig.instance.modelLabel}'
                            : 'Not connected. Tap to sign in',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => AiController.instance.show(page: AiPage.settings),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, 'Updates'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.system_update),
                        title: const Text('Check for update'),
                        subtitle: const Text('Download and install the latest version'),
                        trailing: _checking
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_right),
                        onTap: _checking ? null : _check,
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.autorenew),
                        title: const Text('Check automatically on start'),
                        value: s.autoCheckUpdates,
                        onChanged: (v) => s.autoCheckUpdates = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, 'Appearance'),
                Card(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                            ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System'),
                              icon: Icon(Icons.phone_android),
                            ),
                          ],
                          selected: {s.themeMode},
                          onSelectionChanged: (v) => s.themeMode = v.first,
                        ),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.candlestick_chart),
                        title: const Text('Candlestick charts'),
                        subtitle: const Text('Off = line charts'),
                        value: s.candles,
                        onChanged: (v) => s.candles = v,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _section(context, 'About'),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text('Data & disclaimer'),
                    subtitle: Text(
                      'Market data from Yahoo Finance, may be delayed. Analysis is for information only and is not financial advice.',
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
