import 'package:flutter/material.dart';

import '../data/bursa_stocks.dart';
import '../services/market_api.dart';
import '../theme.dart';
import '../widgets/format.dart';
import '../widgets/price_chart.dart';
import '../widgets/quote_tile.dart';
import 'stock_detail_screen.dart';
import '../l10n.dart';

class MarketScreen extends StatefulWidget {
  const MarketScreen({super.key});
  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  ChartData? _index;
  Map<String, StockQuote> _quotes = {};
  bool _loading = true;
  String? _error;
  ChartRange _range = ChartRange.m3;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Index and movers load independently so one failing doesn't blank the page.
    final indexFuture = MarketApi.instance
        .chart(klciSymbol, _range, force: force)
        .then<ChartData?>((d) => d)
        .catchError((Object e) {
          if (mounted) setState(() => _error = 'FBM KLCI: $e');
          return null;
        });
    final quotes = await MarketApi.instance.quotes(klciStocks.map((e) => e.symbol).toList(), force: force);
    final index = await indexFuture;
    if (!mounted) return;
    setState(() {
      if (index != null) _index = index;
      _quotes = quotes;
      _loading = false;
      if (index == null && quotes.isEmpty) _error ??= t('Network error. Check your connection.');
    });
  }

  Future<void> _setRange(ChartRange r) async {
    setState(() => _range = r);
    try {
      final d = await MarketApi.instance.chart(klciSymbol, r);
      if (mounted) setState(() => _index = d);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Bursa Malaysia')),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load(force: true)),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 840;
          final indexCard = _indexCard(context, wide ? 360 : 240);
          final breadth = _breadthCard(context);
          final movers = _moversCard(context);
          if (_error != null && _index == null && _quotes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton.tonal(onPressed: () => _load(force: true), child: Text(t('Retry'))),
                ],
              ),
            );
          }
          if (wide) {
            return RefreshIndicator(
              onRefresh: () => _load(force: true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: indexCard),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: breadth),
                    ],
                  ),
                  const SizedBox(height: 16),
                  movers,
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => _load(force: true),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [indexCard, const SizedBox(height: 12), breadth, const SizedBox(height: 12), movers],
            ),
          );
        },
      ),
    );
  }

  Widget _indexCard(BuildContext context, double chartHeight) {
    final theme = Theme.of(context);
    final d = _index;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => StockDetailScreen.open(context, klciSymbol),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('FBM KLCI', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              if (d == null && !_loading && _error != null)
                Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error))
              else if (d == null)
                const SizedBox(height: 40, child: Center(child: LinearProgressIndicator()))
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fmtPrice(d.quote.price),
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${fmtChange(d.quote.change)} (${fmtPct(d.quote.changePct)})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: changeColor(d.quote.change, context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final r in [ChartRange.m1, ChartRange.m3, ChartRange.m6, ChartRange.y1, ChartRange.y5])
                    ChoiceChip(
                      label: Text(r.label),
                      selected: r == _range,
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _setRange(r),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: chartHeight,
                child: d == null
                    ? null
                    : PriceChart(
                        candles: d.candles,
                        candlesMode: false,
                        overlays: const Overlays(sma20: false, sma50: false),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _breadthCard(BuildContext context) {
    final theme = Theme.of(context);
    final qs = _quotes.values.toList();
    final up = qs.where((q) => q.change > 0).length;
    final down = qs.where((q) => q.change < 0).length;
    final flat = qs.length - up - down;
    final total = qs.isEmpty ? 1 : qs.length;
    final sectors = <String, List<double>>{};
    for (final s in klciStocks) {
      final q = _quotes[s.symbol];
      if (q != null) sectors.putIfAbsent(s.sector, () => []).add(q.changePct);
    }
    final sectorAvg = sectors.entries.map((e) => (e.key, e.value.reduce((a, b) => a + b) / e.value.length)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('KLCI market breadth'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    if (up > 0)
                      Expanded(
                        flex: up,
                        child: Container(color: upColor),
                      ),
                    if (flat > 0)
                      Expanded(
                        flex: flat,
                        child: Container(color: theme.colorScheme.outline),
                      ),
                    if (down > 0)
                      Expanded(
                        flex: down,
                        child: Container(color: downColor),
                      ),
                    if (qs.isEmpty) Expanded(child: Container(color: theme.colorScheme.surfaceContainer)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '▲ $up',
                  style: const TextStyle(color: upColor, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '■ $flat',
                  style: TextStyle(color: theme.colorScheme.outline, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '▼ $down',
                  style: const TextStyle(color: downColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            Text(
              tf('{pct}% of constituents advancing', {'pct': (up / total * 100).toStringAsFixed(0)}),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text(t('Sector performance'), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            for (final s in sectorAvg)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(t(s.$1), style: theme.textTheme.bodySmall)),
                    Text(
                      fmtPct(s.$2),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: changeColor(s.$2, context),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _moversCard(BuildContext context) {
    final theme = Theme.of(context);
    final list = _quotes.values.toList();
    switch (_tab) {
      case 0:
        list.sort((a, b) => b.changePct.compareTo(a.changePct));
      case 1:
        list.sort((a, b) => a.changePct.compareTo(b.changePct));
      default:
        list.sort((a, b) => (b.volume ?? 0).compareTo(a.volume ?? 0));
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(t('KLCI movers'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(t('Gainers')), icon: Icon(Icons.trending_up)),
                ButtonSegment(value: 1, label: Text(t('Losers')), icon: Icon(Icons.trending_down)),
                ButtonSegment(value: 2, label: Text(t('Active')), icon: Icon(Icons.bar_chart)),
              ],
              selected: {_tab},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty && _loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          for (final q in list.take(10)) ...[
            QuoteTile(symbol: q.symbol, quote: q, onTap: () => StockDetailScreen.open(context, q.symbol)),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              t('Prices from Yahoo Finance; may be delayed ~15 min.'),
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}
