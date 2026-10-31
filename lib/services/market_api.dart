import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/bursa_stocks.dart';

class Candle {
  final DateTime time;
  final double open, high, low, close;
  final double volume;
  const Candle(this.time, this.open, this.high, this.low, this.close, this.volume);
}

class StockQuote {
  final String symbol;
  final String name;
  final String currency;
  final double price;
  final double previousClose;
  final double? dayHigh, dayLow, volume, fiftyTwoWeekHigh, fiftyTwoWeekLow;
  final DateTime? marketTime;
  final List<double> spark;

  const StockQuote({
    required this.symbol,
    required this.name,
    required this.currency,
    required this.price,
    required this.previousClose,
    this.dayHigh,
    this.dayLow,
    this.volume,
    this.fiftyTwoWeekHigh,
    this.fiftyTwoWeekLow,
    this.marketTime,
    this.spark = const [],
  });

  double get change => price - previousClose;
  double get changePct => previousClose == 0 ? 0 : change / previousClose * 100;
  String get code => symbol.replaceAll('.KL', '');
}

class ChartData {
  final StockQuote quote;
  final List<Candle> candles;
  const ChartData(this.quote, this.candles);
}

class SearchResult {
  final String symbol;
  final String name;
  final String exchange;
  const SearchResult(this.symbol, this.name, this.exchange);
}

enum ChartRange {
  d1('1D', '1d', '5m'),
  d5('5D', '5d', '30m'),
  m1('1M', '1mo', '1d'),
  m3('3M', '3mo', '1d'),
  m6('6M', '6mo', '1d'),
  y1('1Y', '1y', '1d'),
  y2('2Y', '2y', '1d'),
  y5('5Y', '5y', '1wk'),
  max('MAX', 'max', '1mo');

  final String label, range, interval;
  const ChartRange(this.label, this.range, this.interval);
  bool get intraday => interval.endsWith('m');
}

class MarketApiException implements Exception {
  final String message;
  MarketApiException(this.message);
  @override
  String toString() => message;
}

/// Market data client. Uses Yahoo Finance public chart/search endpoints,
/// which cover Bursa Malaysia counters (suffix .KL) and the FBM KLCI (^KLSE).
class MarketApi {
  MarketApi._();
  static final MarketApi instance = MarketApi._();

  static const _hosts = ['query1.finance.yahoo.com', 'query2.finance.yahoo.com'];
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36',
    'Accept': 'application/json',
  };

  final http.Client _client = http.Client();
  final Map<String, (DateTime, ChartData)> _cache = {};

  Future<Map<String, dynamic>> _getJson(String path, Map<String, String> query) async {
    Object? lastError;
    for (final host in _hosts) {
      try {
        final uri = Uri.https(host, path, query);
        final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          return jsonDecode(res.body) as Map<String, dynamic>;
        }
        if (res.statusCode == 404) {
          throw MarketApiException('Symbol not found');
        }
        lastError = MarketApiException('Server error ${res.statusCode}');
      } on MarketApiException {
        rethrow;
      } on TimeoutException {
        lastError = MarketApiException('Request timed out');
      } catch (e) {
        lastError = MarketApiException('Network error. Check your connection.');
      }
    }
    throw lastError ?? MarketApiException('Unknown error');
  }

  Future<ChartData> chart(String symbol, ChartRange range, {bool force = false}) async {
    final key = '$symbol|${range.name}';
    final cached = _cache[key];
    if (!force && cached != null && DateTime.now().difference(cached.$1) < const Duration(seconds: 60)) {
      return cached.$2;
    }
    final json = await _getJson('/v8/finance/chart/$symbol', {
      'range': range.range,
      'interval': range.interval,
      'includePrePost': 'false',
      'events': 'div,splits',
    });
    final chart = json['chart'] as Map<String, dynamic>?;
    final results = chart?['result'] as List?;
    if (results == null || results.isEmpty) {
      final err = chart?['error'];
      throw MarketApiException(err is Map ? '${err['description'] ?? 'No data'}' : 'No data');
    }
    final r = results.first as Map<String, dynamic>;
    final meta = (r['meta'] as Map).cast<String, dynamic>();
    final ts = (r['timestamp'] as List?) ?? const [];
    final q = ((r['indicators']?['quote'] as List?)?.firstOrNull as Map?)?.cast<String, dynamic>() ?? {};
    List<dynamic> col(String k) => (q[k] as List?) ?? const [];
    final o = col('open'), h = col('high'), l = col('low'), c = col('close'), v = col('volume');

    final candles = <Candle>[];
    for (var i = 0; i < ts.length; i++) {
      final close = _d(i < c.length ? c[i] : null);
      if (close == null) continue;
      candles.add(
        Candle(
          DateTime.fromMillisecondsSinceEpoch((ts[i] as num).toInt() * 1000),
          _d(i < o.length ? o[i] : null) ?? close,
          _d(i < h.length ? h[i] : null) ?? close,
          _d(i < l.length ? l[i] : null) ?? close,
          close,
          _d(i < v.length ? v[i] : null) ?? 0,
        ),
      );
    }

    final price = _d(meta['regularMarketPrice']) ?? (candles.isNotEmpty ? candles.last.close : 0);
    final marketTime = meta['regularMarketTime'] is num
        ? DateTime.fromMillisecondsSinceEpoch((meta['regularMarketTime'] as num).toInt() * 1000)
        : null;

    double prev = _d(meta['previousClose']) ?? 0;
    if (prev == 0 && !range.intraday && marketTime != null && candles.isNotEmpty) {
      // previous close = close of last bar before the current trading day (MYT)
      final today = _mytDate(marketTime);
      for (final cd in candles.reversed) {
        if (_mytDate(cd.time).isBefore(today)) {
          prev = cd.close;
          break;
        }
      }
    }
    if (prev == 0) prev = _d(meta['chartPreviousClose']) ?? price;

    final known = findKnown(symbol);
    final quote = StockQuote(
      symbol: symbol,
      name: (meta['longName'] ?? meta['shortName'] ?? known?.name ?? symbol).toString(),
      currency: (meta['currency'] ?? 'MYR').toString(),
      price: price,
      previousClose: prev,
      dayHigh: _d(meta['regularMarketDayHigh']),
      dayLow: _d(meta['regularMarketDayLow']),
      volume: _d(meta['regularMarketVolume']),
      fiftyTwoWeekHigh: _d(meta['fiftyTwoWeekHigh']),
      fiftyTwoWeekLow: _d(meta['fiftyTwoWeekLow']),
      marketTime: marketTime,
      spark: candles.map((e) => e.close).toList(),
    );
    final data = ChartData(quote, candles);
    _cache[key] = (DateTime.now(), data);
    return data;
  }

  /// Lightweight quote with a 1-month daily sparkline.
  Future<StockQuote> quote(String symbol, {bool force = false}) async =>
      (await chart(symbol, ChartRange.m1, force: force)).quote;

  /// Fetch many quotes concurrently; failures are skipped.
  Future<Map<String, StockQuote>> quotes(List<String> symbols, {bool force = false, int concurrency = 6}) async {
    final out = <String, StockQuote>{};
    var index = 0;
    Future<void> worker() async {
      while (index < symbols.length) {
        final s = symbols[index++];
        try {
          out[s] = await quote(s, force: force);
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));
    return out;
  }

  Future<List<SearchResult>> search(String text) async {
    final q = text.trim();
    if (q.isEmpty) return [];
    final lower = q.toLowerCase();
    final local = allKnownStocks
        .where((s) => s.code.contains(q) || s.name.toLowerCase().contains(lower))
        .map((s) => SearchResult(s.symbol, s.name, 'Bursa'))
        .toList();
    final results = <String, SearchResult>{for (final r in local) r.symbol: r};
    if (RegExp(r'^\d{4}[A-Za-z0-9]*$').hasMatch(q)) {
      final sym = '${q.toUpperCase()}.KL';
      results.putIfAbsent(sym, () => SearchResult(sym, sym, 'Bursa'));
    }
    try {
      final json = await _getJson('/v1/finance/search', {
        'q': q,
        'quotesCount': '20',
        'newsCount': '0',
        'listsCount': '0',
      });
      for (final item in (json['quotes'] as List? ?? const [])) {
        final m = (item as Map).cast<String, dynamic>();
        final sym = (m['symbol'] ?? '').toString();
        final exch = (m['exchange'] ?? '').toString();
        if (!(sym.endsWith('.KL') || exch == 'KLS' || sym == klciSymbol)) continue;
        final name = (m['shortname'] ?? m['longname'] ?? sym).toString();
        results[sym] = SearchResult(sym, name, 'Bursa');
      }
    } catch (_) {
      // offline: local results only
    }
    return results.values.toList();
  }

  static DateTime _mytDate(DateTime t) {
    final m = t.toUtc().add(const Duration(hours: 8));
    return DateTime.utc(m.year, m.month, m.day);
  }

  static double? _d(Object? v) => v is num ? v.toDouble() : null;
}
