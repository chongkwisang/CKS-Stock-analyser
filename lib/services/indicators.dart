import 'dart:math' as math;

/// Technical indicator helpers. Each returns a list aligned with the input,
/// with null where the indicator is not yet defined.
class Indicators {
  static List<double?> sma(List<double> v, int period) {
    final out = List<double?>.filled(v.length, null);
    double sum = 0;
    for (var i = 0; i < v.length; i++) {
      sum += v[i];
      if (i >= period) sum -= v[i - period];
      if (i >= period - 1) out[i] = sum / period;
    }
    return out;
  }

  static List<double?> ema(List<double> v, int period) {
    final out = List<double?>.filled(v.length, null);
    if (v.length < period) return out;
    final k = 2 / (period + 1);
    double prev = v.take(period).reduce((a, b) => a + b) / period;
    out[period - 1] = prev;
    for (var i = period; i < v.length; i++) {
      prev = v[i] * k + prev * (1 - k);
      out[i] = prev;
    }
    return out;
  }

  /// Wilder's RSI.
  static List<double?> rsi(List<double> v, [int period = 14]) {
    final out = List<double?>.filled(v.length, null);
    if (v.length <= period) return out;
    double gain = 0, loss = 0;
    for (var i = 1; i <= period; i++) {
      final d = v[i] - v[i - 1];
      if (d >= 0) {
        gain += d;
      } else {
        loss -= d;
      }
    }
    gain /= period;
    loss /= period;
    out[period] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
    for (var i = period + 1; i < v.length; i++) {
      final d = v[i] - v[i - 1];
      gain = (gain * (period - 1) + math.max(d, 0)) / period;
      loss = (loss * (period - 1) + math.max(-d, 0)) / period;
      out[i] = loss == 0 ? 100 : 100 - 100 / (1 + gain / loss);
    }
    return out;
  }

  static ({List<double?> macd, List<double?> signal, List<double?> hist}) macd(
    List<double> v, [
    int fast = 12,
    int slow = 26,
    int signal = 9,
  ]) {
    final ef = ema(v, fast), es = ema(v, slow);
    final m = List<double?>.generate(v.length, (i) => ef[i] != null && es[i] != null ? ef[i]! - es[i]! : null);
    final start = m.indexWhere((e) => e != null);
    final sig = List<double?>.filled(v.length, null);
    if (start >= 0) {
      final sub = m.sublist(start).map((e) => e!).toList();
      final se = ema(sub, signal);
      for (var i = 0; i < se.length; i++) {
        sig[start + i] = se[i];
      }
    }
    final h = List<double?>.generate(v.length, (i) => m[i] != null && sig[i] != null ? m[i]! - sig[i]! : null);
    return (macd: m, signal: sig, hist: h);
  }

  static ({List<double?> upper, List<double?> middle, List<double?> lower}) bollinger(
    List<double> v, [
    int period = 20,
    double mult = 2,
  ]) {
    final mid = sma(v, period);
    final up = List<double?>.filled(v.length, null), lo = List<double?>.filled(v.length, null);
    for (var i = period - 1; i < v.length; i++) {
      double s = 0;
      for (var j = i - period + 1; j <= i; j++) {
        s += math.pow(v[j] - mid[i]!, 2);
      }
      final sd = math.sqrt(s / period);
      up[i] = mid[i]! + mult * sd;
      lo[i] = mid[i]! - mult * sd;
    }
    return (upper: up, middle: mid, lower: lo);
  }

  static double? last(List<double?> v) {
    for (var i = v.length - 1; i >= 0; i--) {
      if (v[i] != null) return v[i];
    }
    return null;
  }
}
