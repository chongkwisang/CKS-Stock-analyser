import 'dart:convert';

import 'package:flutter/material.dart';

import '../app_nav.dart';
import '../data/bursa_stocks.dart';
import '../screens/stock_detail_screen.dart';
import '../services/analyzer.dart';
import '../services/app_state.dart';
import '../services/indicators.dart';
import '../services/market_api.dart';

/// Tools that expose the app's own market data and actions to Claude.
/// Each is a client-side tool: Claude asks for it, the app runs it locally
/// and returns the result.
class AppTools {
  /// Called when a tool navigates (so the chat can minimise).
  static VoidCallback? onNavigate;

  static const _symbolProp = {
    'type': 'string',
    'description':
        'Bursa Malaysia stock: 4-digit code (e.g. "1155"), Yahoo symbol ("1155.KL"), '
        'short name ("MAYBANK"), or "^KLSE" for the FBM KLCI index.',
  };
  static const _rangeProp = {
    'type': 'string',
    'enum': ['1mo', '3mo', '6mo', '1y', '2y', '5y'],
    'description': 'History range (daily bars; 5y uses weekly).',
  };

  static final List<Map<String, dynamic>> definitions = [
    {
      'name': 'search_stocks',
      'description':
          'Find Bursa Malaysia counters by company name, short name, code or sector. '
          'Use this first whenever the user names a company and you are not sure of its code.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Name, code or sector keyword'},
        },
        'required': ['query'],
      },
    },
    {
      'name': 'get_quote',
      'description':
          'Latest price, change, day range, volume and 52-week range for one or more Bursa stocks '
          '(prices may be delayed ~15 min).',
      'input_schema': {
        'type': 'object',
        'properties': {
          'symbols': {'type': 'array', 'items': _symbolProp, 'description': 'Up to 20 symbols'},
        },
        'required': ['symbols'],
      },
    },
    {
      'name': 'get_price_history',
      'description': 'OHLCV price history for a stock as a CSV table (downsampled to at most 120 rows).',
      'input_schema': {
        'type': 'object',
        'properties': {'symbol': _symbolProp, 'range': _rangeProp},
        'required': ['symbol'],
      },
    },
    {
      'name': 'get_technical_analysis',
      'description':
          'Technical indicators for a stock: SMA20/50/200, RSI(14), MACD(12,26,9), Bollinger Bands, '
          'volume vs average, period returns, distance from 52-week high/low, and the app\'s analyzer score '
          '(-100 bearish .. +100 bullish) with its reasons.',
      'input_schema': {
        'type': 'object',
        'properties': {'symbol': _symbolProp, 'range': _rangeProp},
        'required': ['symbol'],
      },
    },
    {
      'name': 'compare_stocks',
      'description':
          'Side-by-side comparison of 2-10 stocks: price, 1M/3M/1Y returns, RSI, trend vs SMA50/200 '
          'and analyzer score.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'symbols': {'type': 'array', 'items': _symbolProp},
        },
        'required': ['symbols'],
      },
    },
    {
      'name': 'get_market_overview',
      'description':
          'FBM KLCI level and change, KLCI breadth (advancers/decliners), sector performance, and the '
          'top gainers, losers and most active KLCI constituents today.',
      'input_schema': {'type': 'object', 'properties': <String, dynamic>{}},
    },
    {
      'name': 'get_watchlist',
      'description': 'The user\'s watchlist in the app, with current quotes.',
      'input_schema': {'type': 'object', 'properties': <String, dynamic>{}},
    },
    {
      'name': 'update_watchlist',
      'description':
          'Add a stock to, or remove one from, the user\'s watchlist in the app. Only do this when the '
          'user asks.',
      'input_schema': {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['add', 'remove'],
          },
          'symbol': _symbolProp,
        },
        'required': ['action', 'symbol'],
      },
    },
    {
      'name': 'open_stock_chart',
      'description':
          'Open the stock\'s chart screen in the app (minimises the chat so the user sees it). Use when '
          'the user asks to see/show/open a chart.',
      'input_schema': {
        'type': 'object',
        'properties': {'symbol': _symbolProp},
        'required': ['symbol'],
      },
    },
  ];

  static String label(String name, Map<String, dynamic> input) {
    String sym() {
      final s = input['symbol'] ?? (input['symbols'] is List ? (input['symbols'] as List).join(', ') : null);
      return s == null ? '' : ' $s';
    }

    return switch (name) {
      'search_stocks' => 'Searching "${input['query'] ?? ''}"',
      'get_quote' => 'Getting quote${sym()}',
      'get_price_history' => 'Loading price history${sym()}',
      'get_technical_analysis' => 'Analysing${sym()}',
      'compare_stocks' => 'Comparing${sym()}',
      'get_market_overview' => 'Reading market overview',
      'get_watchlist' => 'Reading your watchlist',
      'update_watchlist' => '${input['action'] == 'remove' ? 'Removing' : 'Adding'}${sym()}',
      'open_stock_chart' => 'Opening chart${sym()}',
      'web_search' => 'Searching the web "${input['query'] ?? ''}"',
      'web_fetch' => 'Reading ${input['url'] ?? 'web page'}',
      _ => name,
    };
  }

  static bool isAppTool(String name) => definitions.any((d) => d['name'] == name);

  /// Resolve user/model text to a Yahoo symbol.
  static String? resolve(Object? raw) {
    if (raw is! String) return null;
    final s = raw.trim().toUpperCase();
    if (s.isEmpty) return null;
    if (s == '^KLSE' || s == 'KLCI' || s == 'FBMKLCI' || s == 'FBM KLCI') return klciSymbol;
    if (s.endsWith('.KL')) return s;
    if (RegExp(r'^\d{4}[A-Z0-9]*$').hasMatch(s)) return '$s.KL';
    for (final k in allKnownStocks) {
      if (k.name == s) return k.symbol;
    }
    return '$s.KL';
  }

  static ChartRange _range(Object? r) => switch (r) {
    '1mo' => ChartRange.m1,
    '3mo' => ChartRange.m3,
    '6mo' => ChartRange.m6,
    '2y' => ChartRange.y2,
    '5y' => ChartRange.y5,
    _ => ChartRange.y1,
  };

  static String _p(double? v) => v == null ? 'n/a' : (v.abs() < 10 ? v.toStringAsFixed(3) : v.toStringAsFixed(2));
  static String _pct(double? v) => v == null ? 'n/a' : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';
  static String _day(DateTime t) => t.toUtc().add(const Duration(hours: 8)).toIso8601String().substring(0, 10);

  static Map<String, dynamic> _quoteJson(StockQuote q) => {
    'symbol': q.symbol,
    'name': q.name,
    'currency': q.currency,
    'price': q.price,
    'change': double.parse(q.change.toStringAsFixed(4)),
    'change_pct': double.parse(q.changePct.toStringAsFixed(2)),
    'prev_close': q.previousClose,
    'day_high': q.dayHigh,
    'day_low': q.dayLow,
    'volume': q.volume,
    '52w_high': q.fiftyTwoWeekHigh,
    '52w_low': q.fiftyTwoWeekLow,
    if (q.marketTime != null) 'as_of_myt': q.marketTime!.toUtc().add(const Duration(hours: 8)).toIso8601String(),
  };

  static double? _ret(List<Candle> c, int bars) =>
      c.length > bars ? (c.last.close / c[c.length - 1 - bars].close - 1) * 100 : null;

  /// Runs a tool. Throws [ToolInputError] for bad input.
  static Future<String> run(String name, Map<String, dynamic> input) async {
    final api = MarketApi.instance;
    switch (name) {
      case 'search_stocks':
        final q = input['query'];
        if (q is! String || q.trim().isEmpty) throw ToolInputError('query is required');
        final lower = q.toLowerCase();
        final bySector = allKnownStocks.where((s) => s.sector.toLowerCase().contains(lower));
        final res = await api.search(q);
        final out = <String, Map<String, String>>{
          for (final r in res) r.symbol: {'symbol': r.symbol, 'name': r.name},
          for (final s in bySector) s.symbol: {'symbol': s.symbol, 'name': s.name, 'sector': s.sector},
        };
        return jsonEncode({'results': out.values.take(25).toList()});

      case 'get_quote':
        final syms = _symbols(input['symbols'], max: 20);
        final quotes = await api.quotes(syms);
        return jsonEncode({
          'quotes': [
            for (final s in syms) quotes[s] == null ? {'symbol': s, 'error': 'not found'} : _quoteJson(quotes[s]!),
          ],
        });

      case 'get_price_history':
        final sym = _symbol(input['symbol']);
        final d = await api.chart(sym, _range(input['range']));
        var c = d.candles;
        final step = (c.length / 120).ceil().clamp(1, 1000);
        final rows = StringBuffer('date,open,high,low,close,volume\n');
        for (var i = c.length - 1; i >= 0; i -= step) {
          final k = c[i];
          rows.writeln('${_day(k.time)},${_p(k.open)},${_p(k.high)},${_p(k.low)},${_p(k.close)},${k.volume.round()}');
        }
        final lines = rows.toString().trim().split('\n');
        return 'symbol: $sym (${d.quote.name})\nbars: ${c.length}${step > 1 ? ' (every ${step}th bar shown, newest first)' : ' (newest first)'}\n'
            '${lines.first}\n${lines.skip(1).join('\n')}';

      case 'get_technical_analysis':
        final sym = _symbol(input['symbol']);
        final d = await api.chart(sym, _range(input['range'] ?? '1y'));
        return jsonEncode(_technicals(d));

      case 'compare_stocks':
        final syms = _symbols(input['symbols'], max: 10);
        final rows = await Future.wait(
          syms.map((s) async {
            try {
              final d = await api.chart(s, ChartRange.y1);
              final t = _technicals(d);
              return {
                'symbol': s,
                'name': d.quote.name,
                'price': d.quote.price,
                'day_change_pct': t['day_change_pct'],
                'returns_pct': t['returns_pct'],
                'rsi14': t['rsi14'],
                'above_sma50': t['above_sma50'],
                'above_sma200': t['above_sma200'],
                'analyzer_score': (t['analyzer'] as Map)['score'],
              };
            } catch (e) {
              return {'symbol': s, 'error': '$e'};
            }
          }),
        );
        return jsonEncode({'comparison': rows});

      case 'get_market_overview':
        final idx = await api.chart(klciSymbol, ChartRange.m1);
        final quotes = await api.quotes(klciStocks.map((e) => e.symbol).toList());
        final qs = quotes.values.toList();
        final sectors = <String, List<double>>{};
        for (final s in klciStocks) {
          final q = quotes[s.symbol];
          if (q != null) sectors.putIfAbsent(s.sector, () => []).add(q.changePct);
        }
        Map<String, dynamic> brief(StockQuote q) => {
          'symbol': q.symbol,
          'name': findKnown(q.symbol)?.name ?? q.name,
          'price': q.price,
          'change_pct': double.parse(q.changePct.toStringAsFixed(2)),
          'volume': q.volume,
        };
        final byPct = [...qs]..sort((a, b) => b.changePct.compareTo(a.changePct));
        final byVol = [...qs]..sort((a, b) => (b.volume ?? 0).compareTo(a.volume ?? 0));
        return jsonEncode({
          'klci': _quoteJson(idx.quote),
          'klci_1m_return_pct': _ret(idx.candles, idx.candles.length - 1)?.toStringAsFixed(2),
          'breadth': {
            'advancers': qs.where((q) => q.change > 0).length,
            'decliners': qs.where((q) => q.change < 0).length,
            'unchanged': qs.where((q) => q.change == 0).length,
            'of': qs.length,
          },
          'sector_avg_change_pct': {
            for (final e in sectors.entries)
              e.key: double.parse((e.value.reduce((a, b) => a + b) / e.value.length).toStringAsFixed(2)),
          },
          'top_gainers': byPct.take(5).map(brief).toList(),
          'top_losers': byPct.reversed.take(5).map(brief).toList(),
          'most_active': byVol.take(5).map(brief).toList(),
        });

      case 'get_watchlist':
        final syms = AppState.instance.watchlist;
        final quotes = await api.quotes(syms);
        return jsonEncode({
          'watchlist': [
            for (final s in syms) quotes[s] == null ? {'symbol': s} : _quoteJson(quotes[s]!),
          ],
        });

      case 'update_watchlist':
        final sym = _symbol(input['symbol']);
        final action = input['action'];
        if (action != 'add' && action != 'remove') throw ToolInputError('action must be "add" or "remove"');
        final watched = AppState.instance.isWatched(sym);
        if ((action == 'add') != watched) AppState.instance.toggleWatch(sym);
        return jsonEncode({'ok': true, 'symbol': sym, 'in_watchlist': action == 'add'});

      case 'open_stock_chart':
        final sym = _symbol(input['symbol']);
        final nav = appNavigatorKey.currentState;
        if (nav == null) return jsonEncode({'ok': false, 'error': 'app not ready'});
        onNavigate?.call();
        nav.push(MaterialPageRoute(builder: (_) => StockDetailScreen(symbol: sym)));
        return jsonEncode({'ok': true, 'opened': sym});
    }
    throw ToolInputError('Unknown tool $name');
  }

  static Map<String, dynamic> _technicals(ChartData d) {
    final c = d.candles;
    if (c.length < 2) return {'symbol': d.quote.symbol, 'error': 'not enough data'};
    final closes = c.map((e) => e.close).toList();
    final price = closes.last;
    final s20 = Indicators.last(Indicators.sma(closes, 20));
    final s50 = Indicators.last(Indicators.sma(closes, 50));
    final s200 = Indicators.last(Indicators.sma(closes, 200));
    final rsi = Indicators.last(Indicators.rsi(closes));
    final macd = Indicators.macd(closes);
    final bb = Indicators.bollinger(closes);
    final vols = c.map((e) => e.volume).toList();
    final avgVol = Indicators.last(Indicators.sma(vols, 20));
    final hi = c.map((e) => e.high).reduce((a, b) => a > b ? a : b);
    final lo = c.map((e) => e.low).reduce((a, b) => a < b ? a : b);
    final a = Analyzer.analyze(c);
    double? r(double? v) => v == null ? null : double.parse(v.toStringAsFixed(4));
    return {
      'symbol': d.quote.symbol,
      'name': d.quote.name,
      'price': price,
      'day_change_pct': double.parse(d.quote.changePct.toStringAsFixed(2)),
      'bars': c.length,
      'from': _day(c.first.time),
      'to': _day(c.last.time),
      'sma20': r(s20),
      'sma50': r(s50),
      'sma200': r(s200),
      'above_sma50': s50 == null ? null : price > s50,
      'above_sma200': s200 == null ? null : price > s200,
      'rsi14': rsi == null ? null : double.parse(rsi.toStringAsFixed(1)),
      'macd': r(Indicators.last(macd.macd)),
      'macd_signal': r(Indicators.last(macd.signal)),
      'macd_hist': r(Indicators.last(macd.hist)),
      'bollinger_upper': r(Indicators.last(bb.upper)),
      'bollinger_lower': r(Indicators.last(bb.lower)),
      'volume_vs_20d_avg': avgVol == null || avgVol == 0 ? null : double.parse((vols.last / avgVol).toStringAsFixed(2)),
      'returns_pct': {
        '1w': _pct(_ret(c, 5)),
        '1m': _pct(_ret(c, 21)),
        '3m': _pct(_ret(c, 63)),
        'period': _pct((price / closes.first - 1) * 100),
      },
      'period_high': hi,
      'period_low': lo,
      'pct_below_period_high': _pct((price / hi - 1) * 100),
      'pct_above_period_low': _pct((price / lo - 1) * 100),
      'analyzer': {
        'score': a.score,
        'bias': a.overall.name,
        'signals': [for (final p in a.points) '${p.label}: ${p.detail} (${p.bias.name})'],
      },
    };
  }

  static String _symbol(Object? raw) {
    final s = resolve(raw);
    if (s == null) throw ToolInputError('symbol is required');
    return s;
  }

  static List<String> _symbols(Object? raw, {required int max}) {
    if (raw is String) raw = [raw];
    if (raw is! List || raw.isEmpty) throw ToolInputError('symbols must be a non-empty array');
    return raw.map(resolve).whereType<String>().toSet().take(max).toList();
  }
}

class ToolInputError implements Exception {
  final String message;
  ToolInputError(this.message);
  @override
  String toString() => message;
}
