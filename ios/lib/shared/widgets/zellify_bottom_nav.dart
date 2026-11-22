import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';

/// The floating bottom bar: Home, Insights, Pay (raised button), Cards, Me.
/// Every main screen will reuse this same widget.
class ZellifyBottomNav extends StatelessWidget {
  const ZellifyBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  /// 0 = Home, 1 = Insights, 2 = Pay, 3 = Cards, 4 = Me
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<_NavData> _items = [
    _NavData('Home', Icons.home_outlined),
    _NavData('Insights', Icons.bar_chart_rounded),
    _NavData('Pay', null), // the raised button is drawn separately
    _NavData('Cards', Icons.credit_card_outlined),
    _NavData('Me', Icons.person_outline_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final bottomMargin = math.max(bottomInset - 18, 10.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(6, 0, 6, bottomMargin),
      child: SizedBox(
        height: 68,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
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
            ),
            // The raised "Pay" button sits slightly above the bar.
            Positioned(
              top: -9,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () => onTap(2),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.greenDark,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x330F3D33),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: AppColors.white,
                      size: 22,
                    ),
                  ),
                ),
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
              child: data.icon == null
                  ? null
                  : Icon(data.icon, size: 22, color: color),
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
