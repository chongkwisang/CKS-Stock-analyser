import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/updater.dart';
import 'market_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import 'watchlist_screen.dart';

/// Adaptive navigation: bottom bar on phones, navigation rail on tablets
/// (extended with labels on large landscape tablets).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _destinations = [
    (Icons.show_chart_outlined, Icons.show_chart, 'Market'),
    (Icons.star_outline, Icons.star, 'Watchlist'),
    (Icons.search, Icons.search, 'Search'),
    (Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    if (AppState.instance.autoCheckUpdates) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Updater.checkAndPrompt(context, silent: true);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const MarketScreen(), const WatchlistScreen(), const SearchScreen(), const SettingsScreen()];
    final body = IndexedStack(index: _index, children: pages);

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 600) {
          return Scaffold(
            body: body,
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final d in _destinations)
                  NavigationDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: d.$3),
              ],
            ),
          );
        }
        final extended = c.maxWidth >= 1200;
        return Scaffold(
          body: Row(
            children: [
              SafeArea(
                right: false,
                child: NavigationRail(
                  extended: extended,
                  minExtendedWidth: 200,
                  selectedIndex: _index,
                  labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      child: Text(
                        'CKS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          ),
        );
      },
    );
  }
}
