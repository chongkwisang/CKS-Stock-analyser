import 'package:intl/intl.dart';

final _price3 = NumberFormat('#,##0.000');
final _price2 = NumberFormat('#,##0.00');
final _compact = NumberFormat.compact();

/// Bursa prices under RM1 trade in 0.005 ticks, so show 3 decimals.
String fmtPrice(double v) => v.abs() < 10 ? _price3.format(v) : _price2.format(v);
String fmtChange(double v) => '${v >= 0 ? '+' : ''}${fmtPrice(v)}';
String fmtPct(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';
String fmtVol(double v) => _compact.format(v);
String fmtDate(DateTime t, {bool time = false}) =>
    DateFormat(time ? 'd MMM HH:mm' : 'd MMM yyyy').format(t.toUtc().add(const Duration(hours: 8)));
