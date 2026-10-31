import 'dart:async';

import 'package:flutter/material.dart';

import '../data/bursa_stocks.dart';
import '../services/app_state.dart';
import '../services/market_api.dart';
import 'stock_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<SearchResult> _results = [];
  bool _loading = false;
  String _sector = 'All';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
    setState(() {});
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final r = await MarketApi.instance.search(q);
    if (!mounted || q != _ctrl.text) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _ctrl.text.trim();
    final sectors = [
      'All',
      ...{for (final s in allKnownStocks) s.sector}.toList()..sort(),
    ];
    final browse = allKnownStocks.where((s) => _sector == 'All' || s.sector == _sector).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final items = query.isEmpty ? browse.map((s) => SearchResult(s.symbol, s.name, s.sector)).toList() : _results;

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _ctrl,
                  onChanged: _onChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _search,
                  decoration: InputDecoration(
                    hintText: 'Stock name or code (e.g. Maybank, 1155)',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _ctrl.clear();
                              _onChanged('');
                            },
                          ),
                  ),
                ),
              ),
              if (query.isEmpty)
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      for (final s in sectors)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ChoiceChip(
                            label: Text(s),
                            selected: _sector == s,
                            showCheckmark: false,
                            onSelected: (_) => setState(() => _sector = s),
                          ),
                        ),
                    ],
                  ),
                ),
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListenableBuilder(
                  listenable: AppState.instance,
                  builder: (context, _) => items.isEmpty && query.isNotEmpty && !_loading
                      ? const Center(child: Text('No Bursa counters found'))
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
                          itemBuilder: (context, i) {
                            final r = items[i];
                            final watched = AppState.instance.isWatched(r.symbol);
                            final code = r.symbol.replaceAll('.KL', '');
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: theme.colorScheme.secondaryContainer,
                                child: Text(
                                  code.length > 4 ? code.substring(0, 4) : code,
                                  style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('$code · ${r.exchange}'),
                              trailing: IconButton(
                                icon: Icon(
                                  watched ? Icons.star : Icons.star_outline,
                                  color: watched ? Colors.amber : null,
                                ),
                                onPressed: () => AppState.instance.toggleWatch(r.symbol),
                              ),
                              onTap: () => StockDetailScreen.open(context, r.symbol),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
