import 'package:flutter/material.dart';

import '../data/bursa_stocks.dart';
import '../services/analyzer.dart';
import '../services/app_state.dart';
import '../services/indicators.dart';
import '../services/market_api.dart';
import '../theme.dart';
import '../widgets/format.dart';
import '../widgets/price_chart.dart';
import '../l10n.dart';

/// Full stock view. Used as a pushed page on phones and embedded in the
/// right pane on tablets ([embedded] = true).
class StockDetailScreen extends StatefulWidget {
  final String symbol;
  final bool embedded;
  const StockDetailScreen({super.key, required this.symbol, this.embedded = false});

  static void open(BuildContext context, String symbol) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: symbol)));
  }

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  ChartRange _range = ChartRange.m6;
  ChartData? _data;
  Object? _error;
  bool _loading = true;
  int? _sel;
  bool _sma20 = true, _sma50 = true, _sma200 = false, _bb = false;
  bool _showRsi = true, _showMacd = true;

  @override
  void initState() {
    super.initState();
    AppState.instance.viewingSymbol = widget.symbol;
    _load();
  }

  @override
  void dispose() {
    if (AppState.instance.viewingSymbol == widget.symbol) AppState.instance.viewingSymbol = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(StockDetailScreen old) {
    super.didUpdateWidget(old);
    if (old.symbol != widget.symbol) {
      AppState.instance.viewingSymbol = widget.symbol;
      _data = null;
      _load();
    }
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await MarketApi.instance.chart(widget.symbol, _range, force: force);
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
        _sel = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final known = findKnown(widget.symbol);
    final title = widget.symbol == klciSymbol ? 'FBM KLCI' : known?.name ?? widget.symbol.replaceAll('.KL', '');
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) {
        final watched = AppState.instance.isWatched(widget.symbol);
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !widget.embedded,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                Text(
                  widget.symbol == klciSymbol ? 'FBM KLCI' : '${widget.symbol.replaceAll('.KL', '')} · Bursa Malaysia',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: AppState.instance.candles ? t('Line chart') : t('Candlestick chart'),
                icon: Icon(AppState.instance.candles ? Icons.show_chart : Icons.candlestick_chart),
                onPressed: () => AppState.instance.candles = !AppState.instance.candles,
              ),
              IconButton(tooltip: t('Refresh'), icon: const Icon(Icons.refresh), onPressed: () => _load(force: true)),
              if (widget.symbol != klciSymbol)
                IconButton(
                  tooltip: watched ? t('Remove from watchlist') : t('Add to watchlist'),
                  icon: Icon(watched ? Icons.star : Icons.star_outline, color: watched ? Colors.amber : null),
                  onPressed: () => AppState.instance.toggleWatch(widget.symbol),
                ),
            ],
          ),
          body: _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final d = _data;
    if (d == null) {
      if (_error != null) return _ErrorView(error: _error!, onRetry: _load);
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;
        final chartCol = _chartColumn(context, d, wide ? c.maxHeight : null);
        final side = _sidePanel(context, d);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: chartCol),
              SizedBox(
                width: 340,
                child: ListView(padding: const EdgeInsets.fromLTRB(0, 8, 16, 24), children: side),
              ),
            ],
          );
        }
        return RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              chartCol,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: side),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chartColumn(BuildContext context, ChartData d, double? height) {
    final theme = Theme.of(context);
    final candles = d.candles;
    final q = d.quote;
    final sel = _sel != null && _sel! < candles.length ? candles[_sel!] : null;
    final price = sel?.close ?? q.price;
    final base = sel != null && _sel! > 0 ? candles[_sel! - 1].close : q.previousClose;
    final chg = price - base;
    final pct = base == 0 ? 0.0 : chg / base * 100;
    final col = changeColor(chg, context);
    final closes = candles.map((e) => e.close).toList();
    final macd = Indicators.macd(closes);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${q.currency == 'MYR' ? 'RM ' : ''}${fmtPrice(price)}',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${fmtChange(chg)} (${fmtPct(pct)})',
                  style: theme.textTheme.titleMedium?.copyWith(color: col, fontWeight: FontWeight.w700),
                ),
              ),
              if (_loading) ...[
                const SizedBox(width: 12),
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            sel != null
                ? '${fmtDate(sel.time, time: _range.intraday)}  O ${fmtPrice(sel.open)}  H ${fmtPrice(sel.high)}  L ${fmtPrice(sel.low)}  C ${fmtPrice(sel.close)}  V ${fmtVol(sel.volume)}'
                : q.marketTime != null
                ? tf('As of {time} MYT · data may be delayed', {'time': fmtDate(q.marketTime!, time: true)})
                : '',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    final rangeBar = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final r in ChartRange.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                label: Text(r.label),
                selected: r == _range,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  setState(() => _range = r);
                  _load();
                },
              ),
            ),
        ],
      ),
    );

    final overlayBar = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _toggle('MA20', _sma20, smaColors.$1, (v) => setState(() => _sma20 = v)),
          _toggle('MA50', _sma50, smaColors.$2, (v) => setState(() => _sma50 = v)),
          _toggle('MA200', _sma200, smaColors.$3, (v) => setState(() => _sma200 = v)),
          _toggle(t('BOLL'), _bb, theme.colorScheme.primary, (v) => setState(() => _bb = v)),
          _toggle('RSI', _showRsi, theme.colorScheme.tertiary, (v) => setState(() => _showRsi = v)),
          _toggle('MACD', _showMacd, theme.colorScheme.secondary, (v) => setState(() => _showMacd = v)),
        ],
      ),
    );

    final chart = PriceChart(
      candles: candles,
      candlesMode: AppState.instance.candles,
      intraday: _range.intraday,
      overlays: Overlays(sma20: _sma20, sma50: _sma50, sma200: _sma200, bollinger: _bb),
      onSelect: (i) => setState(() => _sel = i),
    );

    final rsiPanel = _panel(
      context,
      'RSI (14)',
      OscillatorChart(
        lines: [(Indicators.rsi(closes), const Color(0xFFAB47BC))],
        levels: const [30, 50, 70],
        fixedMin: 0,
        fixedMax: 100,
        selected: _sel,
      ),
    );
    final macdPanel = _panel(
      context,
      'MACD (12, 26, 9)',
      OscillatorChart(
        lines: [(macd.macd, const Color(0xFF2962FF)), (macd.signal, const Color(0xFFFF6D00))],
        histogram: macd.hist,
        levels: const [0],
        selected: _sel,
      ),
    );

    if (height != null) {
      // Tablet: fill available height
      final oscCount = (_showRsi ? 1 : 0) + (_showMacd ? 1 : 0);
      return Column(
        children: [
          header,
          rangeBar,
          const SizedBox(height: 4),
          overlayBar,
          Expanded(
            flex: 5,
            child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 4, 4), child: chart),
          ),
          if (_showRsi) Expanded(flex: oscCount == 2 ? 1 : 2, child: rsiPanel),
          if (_showMacd) Expanded(flex: oscCount == 2 ? 1 : 2, child: macdPanel),
          const SizedBox(height: 8),
        ],
      );
    }
    return Column(
      children: [
        header,
        rangeBar,
        const SizedBox(height: 4),
        overlayBar,
        SizedBox(
          height: 320,
          child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 4, 4), child: chart),
        ),
        if (_showRsi) SizedBox(height: 110, child: rsiPanel),
        if (_showMacd) SizedBox(height: 120, child: macdPanel),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _toggle(String label, bool on, Color color, ValueChanged<bool> f) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 3),
    child: FilterChip(
      label: Text(label),
      selected: on,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      avatar: CircleAvatar(backgroundColor: on ? color : Colors.transparent, radius: 5),
      onSelected: f,
    ),
  );

  Widget _panel(BuildContext context, String title, Widget child) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Expanded(child: child),
      ],
    ),
  );

  List<Widget> _sidePanel(BuildContext context, ChartData d) {
    final q = d.quote;
    final theme = Theme.of(context);
    final c = d.candles;
    final today = c.isNotEmpty ? c.last : null;
    final stats = <(String, String)>[
      (t('Prev close'), fmtPrice(q.previousClose)),
      (t('Open'), today != null && !_range.intraday ? fmtPrice(today.open) : '—'),
      (t('Day high'), q.dayHigh != null ? fmtPrice(q.dayHigh!) : '—'),
      (t('Day low'), q.dayLow != null ? fmtPrice(q.dayLow!) : '—'),
      (t('Volume'), q.volume != null ? fmtVol(q.volume!) : '—'),
      (t('52W high'), q.fiftyTwoWeekHigh != null ? fmtPrice(q.fiftyTwoWeekHigh!) : '—'),
      (t('52W low'), q.fiftyTwoWeekLow != null ? fmtPrice(q.fiftyTwoWeekLow!) : '—'),
      if (c.length > 1)
        (tf('{range} return', {'range': _range.label}), fmtPct((c.last.close / c.first.close - 1) * 100)),
    ];
    final analysis = _range.intraday ? null : Analyzer.analyze(c);

    return [
      const SizedBox(height: 8),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('Key statistics'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 3.2,
                children: [
                  for (final s in stats)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          s.$1,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        Text(s.$2, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (analysis != null) _AnalysisCard(result: analysis),
      if (analysis == null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              t('Switch to a daily range (1M or longer) to see the analysis.'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
    ];
  }
}

class _AnalysisCard extends StatelessWidget {
  final AnalysisResult result;
  const _AnalysisCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color biasColor(SignalBias b) => switch (b) {
      SignalBias.bullish => upColor,
      SignalBias.bearish => downColor,
      SignalBias.neutral => theme.colorScheme.outline,
    };
    final overall = result.overall;
    final label = switch (overall) {
      SignalBias.bullish => t('BULLISH'),
      SignalBias.bearish => t('BEARISH'),
      SignalBias.neutral => t('NEUTRAL'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t('Technical analysis'),
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: biasColor(overall).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: biasColor(overall),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _ScoreBar(score: result.score),
            const SizedBox(height: 12),
            for (final p in result.points)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: CircleAvatar(radius: 5, backgroundColor: biasColor(p.bias)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                          Text(
                            p.detail,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              t('For information only — not financial advice.'),
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final int score;
  const _ScoreBar({required this.score});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final pos = (score + 100) / 200 * c.maxWidth;
            return SizedBox(
              height: 16,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    top: 5,
                    bottom: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(colors: [downColor, Color(0xFF9E9E9E), upColor]),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (pos - 8).clamp(0, c.maxWidth - 16),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: theme.colorScheme.surface,
                        border: Border.all(color: theme.colorScheme.onSurface, width: 3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(t('Bearish'), style: theme.textTheme.labelSmall),
            const Spacer(),
            Text(
              tf('Score {score}', {'score': '${score > 0 ? '+' : ''}$score'}),
              style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(t('Bullish'), style: theme.textTheme.labelSmall),
          ],
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48),
          const SizedBox(height: 12),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRetry, child: Text(t('Retry'))),
        ],
      ),
    ),
  );
}
