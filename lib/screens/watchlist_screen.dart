import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/market_api.dart';
import '../widgets/quote_tile.dart';
import 'stock_detail_screen.dart';

/// Watchlist. On wide screens it becomes a master–detail split view.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});
  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  Map<String, StockQuote> _quotes = {};
  String? _selected;
  bool _loading = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    AppState.instance.addListener(_onState);
    _load();
  }

  @override
  void dispose() {
    AppState.instance.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final missing = AppState.instance.watchlist.where((s) => !_quotes.containsKey(s)).toList();
    if (missing.isNotEmpty) _load(only: missing);
    if (mounted) setState(() {});
  }

  Future<void> _load({bool force = false, List<String>? only}) async {
    setState(() => _loading = true);
    final q = await MarketApi.instance.quotes(only ?? AppState.instance.watchlist, force: force);
    if (!mounted) return;
    setState(() {
      _quotes = {..._quotes, ...q};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = AppState.instance.watchlist;
    return LayoutBuilder(
      builder: (context, c) {
        final split = c.maxWidth >= 900;
        if (split && _selected == null && list.isNotEmpty) _selected = list.first;
        if (_selected != null && !list.contains(_selected)) _selected = list.isEmpty ? null : list.first;

        final listPane = Scaffold(
          appBar: AppBar(
            title: const Text('Watchlist'),
            actions: [
              IconButton(
                tooltip: _editing ? 'Done' : 'Edit',
                icon: Icon(_editing ? Icons.check : Icons.edit_outlined),
                onPressed: () => setState(() => _editing = !_editing),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load(force: true)),
            ],
          ),
          body: list.isEmpty
              ? const _Empty()
              : _editing
              ? ReorderableListView.builder(
                  itemCount: list.length,
                  onReorderItem: AppState.instance.moveItem,
                  itemBuilder: (context, i) => QuoteTile(
                    key: ValueKey(list[i]),
                    symbol: list[i],
                    quote: _quotes[list[i]],
                    showSpark: false,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => AppState.instance.toggleWatch(list[i]),
                        ),
                        ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => _load(force: true),
                  child: ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (context, i) {
                      final s = list[i];
                      return Dismissible(
                        key: ValueKey('d$s'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          child: const Icon(Icons.delete_outline),
                        ),
                        onDismissed: (_) => AppState.instance.toggleWatch(s),
                        child: QuoteTile(
                          symbol: s,
                          quote: _quotes[s],
                          selected: split && s == _selected,
                          onTap: () {
                            if (split) {
                              setState(() => _selected = s);
                            } else {
                              StockDetailScreen.open(context, s);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
        );

        if (!split) return listPane;
        return Row(
          children: [
            SizedBox(width: c.maxWidth >= 1200 ? 420 : 360, child: listPane),
            const VerticalDivider(width: 1),
            Expanded(
              child: _selected == null
                  ? const _Empty()
                  : StockDetailScreen(key: ValueKey(_selected), symbol: _selected!, embedded: true),
            ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_outline, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text('Your watchlist is empty.\nUse Search to add Bursa counters.', textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
