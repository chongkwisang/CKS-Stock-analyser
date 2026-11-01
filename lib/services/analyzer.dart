import 'indicators.dart';
import 'market_api.dart';
import '../l10n.dart';

enum SignalBias { bullish, neutral, bearish }

class AnalysisPoint {
  final String label;
  final String detail;
  final SignalBias bias;
  const AnalysisPoint(this.label, this.detail, this.bias);
}

class AnalysisResult {
  final List<AnalysisPoint> points;
  final int score; // -100..100
  const AnalysisResult(this.points, this.score);

  SignalBias get overall => score >= 25
      ? SignalBias.bullish
      : score <= -25
      ? SignalBias.bearish
      : SignalBias.neutral;
}

/// Stock analyser engine.
///
/// This is a starter technical-analysis rule set (trend, momentum, MACD,
/// volatility, volume). It is intentionally isolated in one place so the
/// custom analysis rules can be dropped in here later.
class Analyzer {
  static AnalysisResult analyze(List<Candle> candles) {
    if (candles.length < 30) {
      return AnalysisResult([
        AnalysisPoint(t('Not enough data'), t('Need at least 30 bars. Choose a longer range.'), SignalBias.neutral),
      ], 0);
    }
    final closes = candles.map((e) => e.close).toList();
    final price = closes.last;
    final points = <AnalysisPoint>[];
    var score = 0;

    // Trend
    final s20 = Indicators.last(Indicators.sma(closes, 20));
    final s50 = Indicators.last(Indicators.sma(closes, 50));
    final s200 = Indicators.last(Indicators.sma(closes, 200));
    if (s50 != null) {
      final above = price > s50;
      score += above ? 20 : -20;
      points.add(
        AnalysisPoint(
          t('Trend (SMA50)'),
          above ? t('Price is above the 50-day average') : t('Price is below the 50-day average'),
          above ? SignalBias.bullish : SignalBias.bearish,
        ),
      );
    } else if (s20 != null) {
      final above = price > s20;
      score += above ? 15 : -15;
      points.add(
        AnalysisPoint(
          t('Trend (SMA20)'),
          above ? t('Price is above the 20-day average') : t('Price is below the 20-day average'),
          above ? SignalBias.bullish : SignalBias.bearish,
        ),
      );
    }
    if (s50 != null && s200 != null) {
      final golden = s50 > s200;
      score += golden ? 15 : -15;
      points.add(
        AnalysisPoint(
          t('Long-term trend'),
          golden ? t('SMA50 above SMA200 (golden-cross regime)') : t('SMA50 below SMA200 (death-cross regime)'),
          golden ? SignalBias.bullish : SignalBias.bearish,
        ),
      );
    }

    // Momentum
    final rsi = Indicators.last(Indicators.rsi(closes));
    if (rsi != null) {
      final r = rsi.toStringAsFixed(1);
      if (rsi >= 70) {
        score -= 10;
        points.add(AnalysisPoint('RSI(14) $r', t('Overbought — risk of pullback'), SignalBias.bearish));
      } else if (rsi <= 30) {
        score += 10;
        points.add(AnalysisPoint('RSI(14) $r', t('Oversold — potential rebound'), SignalBias.bullish));
      } else if (rsi >= 50) {
        score += 10;
        points.add(AnalysisPoint('RSI(14) $r', t('Positive momentum'), SignalBias.bullish));
      } else {
        score -= 10;
        points.add(AnalysisPoint('RSI(14) $r', t('Weak momentum'), SignalBias.bearish));
      }
    }

    // MACD
    final m = Indicators.macd(closes);
    final h = m.hist.whereType<double>().toList();
    if (h.length >= 2) {
      final cur = h.last, prev = h[h.length - 2];
      if (prev <= 0 && cur > 0) {
        score += 25;
        points.add(AnalysisPoint('MACD', t('Fresh bullish crossover'), SignalBias.bullish));
      } else if (prev >= 0 && cur < 0) {
        score -= 25;
        points.add(AnalysisPoint('MACD', t('Fresh bearish crossover'), SignalBias.bearish));
      } else {
        score += cur > 0 ? 15 : -15;
        points.add(
          AnalysisPoint(
            'MACD',
            cur > 0 ? t('Above signal line') : t('Below signal line'),
            cur > 0 ? SignalBias.bullish : SignalBias.bearish,
          ),
        );
      }
    }

    // Bollinger position
    final bb = Indicators.bollinger(closes);
    final up = Indicators.last(bb.upper), lo = Indicators.last(bb.lower);
    if (up != null && lo != null && up > lo) {
      final pos = (price - lo) / (up - lo) * 100;
      points.add(
        AnalysisPoint(
          'Bollinger %B ${pos.toStringAsFixed(0)}%',
          pos > 100
              ? t('Trading above upper band')
              : pos < 0
              ? t('Trading below lower band')
              : t('Inside the bands'),
          pos > 100
              ? SignalBias.bearish
              : pos < 0
              ? SignalBias.bullish
              : SignalBias.neutral,
        ),
      );
    }

    // Volume
    final vols = candles.map((e) => e.volume).toList();
    final avgVol = Indicators.last(Indicators.sma(vols, 20));
    if (avgVol != null && avgVol > 0) {
      final ratio = vols.last / avgVol;
      final rising = closes.last >= closes[closes.length - 2];
      if (ratio > 1.5) {
        score += rising ? 10 : -10;
        points.add(
          AnalysisPoint(
            tf('Volume {x}× avg', {'x': ratio.toStringAsFixed(1)}),
            rising ? t('Strong buying interest') : t('Heavy selling pressure'),
            rising ? SignalBias.bullish : SignalBias.bearish,
          ),
        );
      } else {
        points.add(
          AnalysisPoint(
            tf('Volume {x}× avg', {'x': ratio.toStringAsFixed(1)}),
            t('Normal activity'),
            SignalBias.neutral,
          ),
        );
      }
    }

    return AnalysisResult(points, score.clamp(-100, 100));
  }
}
