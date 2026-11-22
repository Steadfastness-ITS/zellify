import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';

/// The floating bottom bar: Home, Insights, Exchange (green button), Cards, Me.
/// Every main screen will reuse this same widget.
class ZellifyBottomNav extends StatelessWidget {
  const ZellifyBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  /// 0 = Home, 1 = Insights, 2 = Exchange, 3 = Cards, 4 = Me
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<_NavData> _items = [
    _NavData('Home', Icons.home_outlined),
    _NavData('Insights', Icons.bar_chart_rounded),
    _NavData('', null), // centre slot: the green Exchange button (no label)
    _NavData('Cards', Icons.credit_card_outlined),
    _NavData('Me', Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final bottomMargin = math.max(bottomInset - 18, 10.0);

    return Padding(
      // 20 px on each side: the bar lines up with the edges of the balance
      // card (and the other cards) instead of touching the screen edges.
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottomMargin),
      child: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14102A24),
              blurRadius: 24,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _NavItem(
                  data: _items[i],
                  active: i == currentIndex,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavData {
  const _NavData(this.label, this.icon);
  final String label;
  final IconData? icon;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.data,
    required this.active,
    required this.onTap,
  });

  final _NavData data;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Centre slot: the green Exchange button. It sits inside the bar, on the
    // same row as Home, Insights, Cards and Me. No label, no border.
    if (data.icon == null) {
      return Semantics(
        button: true,
        label: 'Exchange Naira and other currencies',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.greenDark,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x330F3D33),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.currency_exchange_rounded,
                  size: 24,
                  // Slightly brighter while the Exchange screen is open.
                  color: active ? AppColors.mintLight : AppColors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final color = active ? AppColors.green : AppColors.navInactive;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 22,
              child: Icon(data.icon, size: 22, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              data.label,
              style: AppText.style(
                10,
                active ? FontWeight.w700 : FontWeight.w500,
                color,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
