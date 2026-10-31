import 'package:flutter/material.dart';

import '../data/bursa_stocks.dart';
import '../services/market_api.dart';
import '../theme.dart';
import 'format.dart';
import 'sparkline.dart';

class QuoteTile extends StatelessWidget {
  final String symbol;
  final StockQuote? quote;
  final VoidCallback? onTap;
  final bool selected;
  final bool showSpark;
  final Widget? trailing;

  const QuoteTile({
    super.key,
    required this.symbol,
    this.quote,
    this.onTap,
    this.selected = false,
    this.showSpark = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = quote;
    final known = findKnown(symbol);
    final title = known?.name ?? symbol.replaceAll('.KL', '');
    final subtitle = q?.name ?? known?.sector ?? symbol;
    final color = q == null ? theme.colorScheme.outline : changeColor(q.change, context);

    return Material(
      color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      '${symbol.replaceAll('.KL', '')} · $subtitle',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (showSpark)
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 32,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: q == null ? null : Sparkline(data: q.spark, color: color),
                    ),
                  ),
                ),
              SizedBox(
                width: 92,
                child: q == null
                    ? const Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            fmtPrice(q.price),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              fmtPct(q.changePct),
                              style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
