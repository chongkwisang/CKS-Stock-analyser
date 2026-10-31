import 'package:cks_stock_analyser/services/analyzer.dart';
import 'package:cks_stock_analyser/services/indicators.dart';
import 'package:cks_stock_analyser/services/market_api.dart';
import 'package:cks_stock_analyser/services/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SMA', () {
    expect(Indicators.sma([1, 2, 3, 4, 5], 3), [null, null, 2, 3, 4]);
  });

  test('RSI stays in range and is 100 for a pure uptrend', () {
    final up = List<double>.generate(30, (i) => i + 1.0);
    expect(Indicators.last(Indicators.rsi(up)), 100);
    final zig = List<double>.generate(60, (i) => 10 + (i % 2 == 0 ? 1 : -1) * (i % 7) / 3);
    for (final v in Indicators.rsi(zig).whereType<double>()) {
      expect(v, inInclusiveRange(0, 100));
    }
  });

  test('MACD histogram = macd - signal', () {
    final v = List<double>.generate(80, (i) => 10 + i * 0.1 + (i % 5) * 0.05);
    final m = Indicators.macd(v);
    final i = v.length - 1;
    expect(m.hist[i], closeTo(m.macd[i]! - m.signal[i]!, 1e-9));
  });

  test('version compare', () {
    expect(Updater.compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(Updater.compareVersions('1.0.3', '1.0.3'), 0);
    expect(Updater.compareVersions('1.0.2', '1.1.0'), lessThan(0));
  });

  test('analyzer flags an uptrend as bullish', () {
    final candles = List.generate(
      250,
      (i) => Candle(
        DateTime(2025, 1, 1).add(Duration(days: i)),
        1 + i * .01,
        1.02 + i * .01,
        .99 + i * .01,
        1.01 + i * .01,
        1000,
      ),
    );
    expect(Analyzer.analyze(candles).score, greaterThan(0));
  });
}
