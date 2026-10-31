import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/indicators.dart';
import '../services/market_api.dart';
import '../theme.dart';
import 'format.dart';

class Overlays {
  final bool sma20, sma50, sma200, bollinger;
  const Overlays({this.sma20 = true, this.sma50 = true, this.sma200 = false, this.bollinger = false});
}

const smaColors = (Color(0xFFFFB300), Color(0xFF7C4DFF), Color(0xFF00B8D4));

/// Price chart with candlesticks or line, MA/Bollinger overlays, a volume
/// strip and a touch crosshair that reports the selected bar.
class PriceChart extends StatefulWidget {
  final List<Candle> candles;
  final bool candlesMode;
  final bool intraday;
  final Overlays overlays;
  final ValueChanged<int?>? onSelect;

  const PriceChart({
    super.key,
    required this.candles,
    this.candlesMode = true,
    this.intraday = false,
    this.overlays = const Overlays(),
    this.onSelect,
  });

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  int? _sel;

  void _update(Offset p, Size size) {
    final n = widget.candles.length;
    if (n == 0) return;
    final w = size.width - _ChartPainter.axisW;
    final i = (p.dx / w * n).floor().clamp(0, n - 1);
    if (i != _sel) {
      setState(() => _sel = i);
      widget.onSelect?.call(i);
    }
  }

  void _clear() {
    setState(() => _sel = null);
    widget.onSelect?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final closes = widget.candles.map((e) => e.close).toList();
    final o = widget.overlays;
    return LayoutBuilder(
      builder: (context, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          onLongPressStart: (d) => _update(d.localPosition, size),
          onLongPressMoveUpdate: (d) => _update(d.localPosition, size),
          onLongPressEnd: (_) => _clear(),
          onHorizontalDragStart: (d) => _update(d.localPosition, size),
          onHorizontalDragUpdate: (d) => _update(d.localPosition, size),
          onHorizontalDragEnd: (_) => _clear(),
          onTapUp: (_) => _clear(),
          child: CustomPaint(
            size: size,
            painter: _ChartPainter(
              candles: widget.candles,
              candlesMode: widget.candlesMode,
              intraday: widget.intraday,
              selected: _sel,
              theme: Theme.of(context),
              lines: [
                if (o.sma20) (Indicators.sma(closes, 20), smaColors.$1),
                if (o.sma50) (Indicators.sma(closes, 50), smaColors.$2),
                if (o.sma200) (Indicators.sma(closes, 200), smaColors.$3),
              ],
              bands: o.bollinger ? Indicators.bollinger(closes) : null,
            ),
          ),
        );
      },
    );
  }
}

class _ChartPainter extends CustomPainter {
  static const axisW = 56.0;
  static const timeH = 18.0;

  final List<Candle> candles;
  final bool candlesMode, intraday;
  final int? selected;
  final ThemeData theme;
  final List<(List<double?>, Color)> lines;
  final ({List<double?> upper, List<double?> middle, List<double?> lower})? bands;

  _ChartPainter({
    required this.candles,
    required this.candlesMode,
    required this.intraday,
    required this.selected,
    required this.theme,
    required this.lines,
    required this.bands,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final n = candles.length;
    if (n == 0) return;
    final cs = theme.colorScheme;
    final w = size.width - axisW;
    final totalH = size.height - timeH;
    final priceH = totalH * 0.78;
    final volTop = totalH * 0.82;
    final volH = totalH - volTop;
    final step = w / n;

    var lo = double.infinity, hi = -double.infinity, maxVol = 0.0;
    for (final c in candles) {
      lo = math.min(lo, candlesMode ? c.low : c.close);
      hi = math.max(hi, candlesMode ? c.high : c.close);
      maxVol = math.max(maxVol, c.volume);
    }
    for (final l in lines) {
      for (final v in l.$1) {
        if (v != null) {
          lo = math.min(lo, v);
          hi = math.max(hi, v);
        }
      }
    }
    if (bands != null) {
      for (var i = 0; i < n; i++) {
        if (bands!.upper[i] != null) {
          hi = math.max(hi, bands!.upper[i]!);
          lo = math.min(lo, bands!.lower[i]!);
        }
      }
    }
    if (hi == lo) {
      hi += hi.abs() * 0.01 + 0.01;
      lo -= lo.abs() * 0.01 + 0.01;
    }
    final pad = (hi - lo) * 0.06;
    hi += pad;
    lo -= pad;
    double y(double v) => priceH - (v - lo) / (hi - lo) * priceH;
    double x(int i) => i * step + step / 2;

    final grid = Paint()
      ..color = cs.outlineVariant.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final label = theme.textTheme.labelSmall!.copyWith(color: cs.onSurfaceVariant, fontSize: 10);

    // horizontal grid + price axis
    for (var g = 0; g <= 4; g++) {
      final v = lo + (hi - lo) * g / 4;
      final yy = y(v);
      canvas.drawLine(Offset(0, yy), Offset(w, yy), grid);
      _text(canvas, fmtPrice(v), Offset(w + 6, yy - 6), label);
    }
    // time axis
    final ticks = math.min(4, n);
    for (var t = 0; t < ticks; t++) {
      final i = ((n - 1) * (t + 0.5) / ticks).round();
      final xx = x(i);
      canvas.drawLine(Offset(xx, 0), Offset(xx, totalH), grid);
      final s = intraday ? fmtDate(candles[i].time, time: true) : fmtDate(candles[i].time);
      _text(canvas, s, Offset(xx, totalH + 3), label, center: true);
    }

    // bollinger band fill
    if (bands != null) {
      final up = Path(), dn = <Offset>[];
      var started = false;
      for (var i = 0; i < n; i++) {
        final u = bands!.upper[i], l = bands!.lower[i];
        if (u == null || l == null) continue;
        started ? up.lineTo(x(i), y(u)) : up.moveTo(x(i), y(u));
        started = true;
        dn.add(Offset(x(i), y(l)));
      }
      for (final p in dn.reversed) {
        up.lineTo(p.dx, p.dy);
      }
      up.close();
      canvas.drawPath(up, Paint()..color = cs.primary.withValues(alpha: 0.08));
      _line(canvas, bands!.upper, x, y, cs.primary.withValues(alpha: 0.5), 1);
      _line(canvas, bands!.lower, x, y, cs.primary.withValues(alpha: 0.5), 1);
    }

    // volume
    if (maxVol > 0) {
      for (var i = 0; i < n; i++) {
        final c = candles[i];
        final up = c.close >= c.open;
        final h = c.volume / maxVol * volH;
        canvas.drawRect(
          Rect.fromLTWH(x(i) - step * 0.35, volTop + volH - h, math.max(step * 0.7, 1), h),
          Paint()..color = (up ? upColor : downColor).withValues(alpha: 0.35),
        );
      }
    }

    // price
    if (candlesMode) {
      final bodyW = math.max(step * 0.65, 1.0);
      for (var i = 0; i < n; i++) {
        final c = candles[i];
        final col = c.close >= c.open ? upColor : downColor;
        final p = Paint()
          ..color = col
          ..strokeWidth = math.max(1, math.min(step * 0.12, 1.5));
        canvas.drawLine(Offset(x(i), y(c.high)), Offset(x(i), y(c.low)), p);
        final top = y(math.max(c.open, c.close)), bot = y(math.min(c.open, c.close));
        canvas.drawRect(Rect.fromLTRB(x(i) - bodyW / 2, top, x(i) + bodyW / 2, math.max(bot, top + 1)), p);
      }
    } else {
      final up = candles.last.close >= candles.first.close;
      final col = up ? upColor : downColor;
      final path = Path();
      for (var i = 0; i < n; i++) {
        i == 0 ? path.moveTo(x(i), y(candles[i].close)) : path.lineTo(x(i), y(candles[i].close));
      }
      final fill = Path.from(path)
        ..lineTo(x(n - 1), priceH)
        ..lineTo(x(0), priceH)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [col.withValues(alpha: 0.28), col.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, w, priceH)),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = col
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (final l in lines) {
      _line(canvas, l.$1, x, y, l.$2, 1.4);
    }

    // last price marker
    final last = candles.last.close;
    final lastCol = candles.last.close >= candles.last.open ? upColor : downColor;
    final ly = y(last);
    _dashed(canvas, Offset(0, ly), Offset(w, ly), lastCol.withValues(alpha: 0.7));
    _tag(canvas, fmtPrice(last), Offset(w, ly), lastCol, Colors.white);

    // crosshair
    if (selected != null && selected! < n) {
      final c = candles[selected!];
      final cx = x(selected!), cy = y(c.close);
      final p = Paint()
        ..color = cs.onSurface.withValues(alpha: 0.5)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, 0), Offset(cx, totalH), p);
      canvas.drawLine(Offset(0, cy), Offset(w, cy), p);
      canvas.drawCircle(Offset(cx, cy), 4, Paint()..color = cs.primary);
      _tag(canvas, fmtPrice(c.close), Offset(w, cy), cs.inverseSurface, cs.onInverseSurface);
    }
  }

  void _line(Canvas canvas, List<double?> v, double Function(int) x, double Function(double) y, Color c, double w) {
    final path = Path();
    var started = false;
    for (var i = 0; i < v.length && i < candles.length; i++) {
      final val = v[i];
      if (val == null) continue;
      started ? path.lineTo(x(i), y(val)) : path.moveTo(x(i), y(val));
      started = true;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = w,
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Color c) {
    final p = Paint()
      ..color = c
      ..strokeWidth = 1;
    for (var xx = a.dx; xx < b.dx; xx += 6) {
      canvas.drawLine(Offset(xx, a.dy), Offset(math.min(xx + 3, b.dx), a.dy), p);
    }
  }

  void _tag(Canvas canvas, String s, Offset at, Color bg, Color fg) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(at.dx + 2, at.dy - tp.height / 2 - 3, tp.width + 8, tp.height + 6),
      const Radius.circular(4),
    );
    canvas.drawRRect(r, Paint()..color = bg);
    tp.paint(canvas, Offset(at.dx + 6, at.dy - tp.height / 2));
  }

  void _text(Canvas canvas, String s, Offset at, TextStyle style, {bool center = false}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center ? at - Offset(tp.width / 2, 0) : at);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.candles != candles ||
      old.selected != selected ||
      old.candlesMode != candlesMode ||
      old.theme != theme ||
      old.lines.length != lines.length ||
      (old.bands == null) != (bands == null);
}

/// Oscillator panel used for RSI and MACD.
class OscillatorChart extends StatelessWidget {
  final List<(List<double?>, Color)> lines;
  final List<double?>? histogram;
  final List<double> levels;
  final double? fixedMin, fixedMax;
  final int? selected;

  const OscillatorChart({
    super.key,
    required this.lines,
    this.histogram,
    this.levels = const [],
    this.fixedMin,
    this.fixedMax,
    this.selected,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.infinite,
    painter: _OscPainter(lines, histogram, levels, fixedMin, fixedMax, selected, Theme.of(context)),
  );
}

class _OscPainter extends CustomPainter {
  final List<(List<double?>, Color)> lines;
  final List<double?>? hist;
  final List<double> levels;
  final double? fmin, fmax;
  final int? selected;
  final ThemeData theme;
  _OscPainter(this.lines, this.hist, this.levels, this.fmin, this.fmax, this.selected, this.theme);

  @override
  void paint(Canvas canvas, Size size) {
    final n = lines.isEmpty ? 0 : lines.first.$1.length;
    if (n == 0) return;
    final w = size.width - _ChartPainter.axisW;
    final step = w / n;
    double x(int i) => i * step + step / 2;
    var lo = fmin ?? double.infinity, hi = fmax ?? -double.infinity;
    if (fmin == null || fmax == null) {
      for (final l in [...lines.map((e) => e.$1), ?hist]) {
        for (final v in l) {
          if (v == null) continue;
          if (fmin == null) lo = math.min(lo, v);
          if (fmax == null) hi = math.max(hi, v);
        }
      }
    }
    if (!lo.isFinite || !hi.isFinite) return;
    if (hi == lo) hi = lo + 1;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;

    final cs = theme.colorScheme;
    final label = theme.textTheme.labelSmall!.copyWith(color: cs.onSurfaceVariant, fontSize: 10);
    for (final lv in levels) {
      final yy = y(lv);
      canvas.drawLine(Offset(0, yy), Offset(w, yy), Paint()..color = cs.outlineVariant.withValues(alpha: 0.5));
      final tp = TextPainter(
        text: TextSpan(text: lv.toStringAsFixed(0), style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w + 6, yy - 6));
    }
    if (hist != null) {
      final zero = y(0);
      for (var i = 0; i < n; i++) {
        final v = hist![i];
        if (v == null) continue;
        canvas.drawRect(
          Rect.fromLTRB(x(i) - step * 0.35, math.min(zero, y(v)), x(i) + step * 0.35, math.max(zero, y(v))),
          Paint()..color = (v >= 0 ? upColor : downColor).withValues(alpha: 0.6),
        );
      }
    }
    for (final l in lines) {
      final path = Path();
      var started = false;
      for (var i = 0; i < n; i++) {
        final v = l.$1[i];
        if (v == null) continue;
        started ? path.lineTo(x(i), y(v)) : path.moveTo(x(i), y(v));
        started = true;
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = l.$2
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
    if (selected != null && selected! < n) {
      canvas.drawLine(
        Offset(x(selected!), 0),
        Offset(x(selected!), size.height),
        Paint()..color = cs.onSurface.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OscPainter old) => true;
}
