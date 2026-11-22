// lib/features/insights/insights_screen.dart
//
// "Money insights" screen (Insights tab). Uses the same AppColors, AppText
// and ZellifyBottomNav as the Home screen. All numbers below are sample data
// (they add up, and match the Money in / Money out on your Transactions
// design). Replace the `_periods` list with real data later.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import '../../shared/widgets/zellify_bottom_nav.dart';
import '../cards/cards_screen.dart';
import '../exchange/exchange_screen.dart';
import '../profile/profile_screen.dart';

/// Colors that only this screen needs (not in AppColors yet).
class _C {
  static const segmentBg = Color(0xFFE9EDEA); // period tabs background
  static const iconBtn = Color(0xFFEBEFEC); // back / dropdown / "..." buttons
  static const barIdle = Color(0xFFD9E7E1); // normal chart bar
  static const barActive = Color(0xFF3BC69B); // highlighted chart bar
  static const track = Color(0xFFEDF1EE); // empty part of progress bars
}

// ─────────────────────────────────── Data ────────────────────────────────────
class _Bar {
  const _Bar(this.label, this.value);
  final String label;
  final int value;
}

class _Category {
  const _Category(this.name, this.icon, this.bg, this.fg, this.amount);
  final String name;
  final IconData icon;
  final Color bg;
  final Color fg;
  final int amount;
}

class _Period {
  const _Period({
    required this.label,
    required this.total,
    required this.compare,
    required this.spendDown,
    required this.bars,
    required this.moneyIn,
    required this.moneyOut,
    required this.inChange,
    required this.outChange,
    required this.changeSuffix,
    required this.categories,
  });

  final String label; // tab text
  final int total; // total spent
  final String compare; // "12% vs July"
  final bool spendDown; // true = spent less than before (green chip)
  final List<_Bar> bars;
  final int moneyIn;
  final int moneyOut;
  final String inChange; // "+8.4%"
  final String outChange; // "-12%"
  final String changeSuffix; // "this month"
  final List<_Category> categories; // biggest first
}

const List<_Period> _periods = [
  _Period(
    label: 'This month',
    total: 286450,
    compare: '12% vs July',
    spendDown: true,
    bars: [
      _Bar('M', 27300),
      _Bar('T', 48550),
      _Bar('W', 25500),
      _Bar('T', 60690),
      _Bar('F', 37630),
      _Bar('S', 53410),
      _Bar('S', 33370),
    ],
    moneyIn: 562300,
    moneyOut: 286450,
    inChange: '+8.4%',
    outChange: '-12%',
    changeSuffix: 'this month',
    categories: [
      _Category('Shopping', Icons.shopping_bag_outlined, AppColors.tileLavender,
          AppColors.iconLavender, 97200),
      _Category('Bills & utilities', Icons.receipt_long_outlined,
          AppColors.tileAmber, AppColors.iconAmber, 74480),
      _Category('Transport', Icons.flight_outlined, AppColors.tileBlue,
          AppColors.iconBlue, 41840),
      _Category('Food & drinks', Icons.restaurant_outlined, AppColors.tileMint,
          AppColors.iconMint, 38430),
      _Category('Others', Icons.grid_view_rounded, AppColors.tileGrey,
          AppColors.iconGrey, 34500),
    ],
  ),
  _Period(
    label: 'Last month',
    total: 325540,
    compare: '4% vs June',
    spendDown: false,
    bars: [
      _Bar('M', 45580),
      _Bar('T', 35810),
      _Bar('W', 58600),
      _Bar('T', 32550),
      _Bar('F', 65110),
      _Bar('S', 48830),
      _Bar('S', 39060),
    ],
    moneyIn: 498900,
    moneyOut: 325540,
    inChange: '+3.1%',
    outChange: '+4%',
    changeSuffix: 'last month',
    categories: [
      _Category('Shopping', Icons.shopping_bag_outlined, AppColors.tileLavender,
          AppColors.iconLavender, 104300),
      _Category('Bills & utilities', Icons.receipt_long_outlined,
          AppColors.tileAmber, AppColors.iconAmber, 82100),
      _Category('Transport', Icons.flight_outlined, AppColors.tileBlue,
          AppColors.iconBlue, 52640),
      _Category('Food & drinks', Icons.restaurant_outlined, AppColors.tileMint,
          AppColors.iconMint, 46500),
      _Category('Others', Icons.grid_view_rounded, AppColors.tileGrey,
          AppColors.iconGrey, 40000),
    ],
  ),
  _Period(
    label: '3 months',
    total: 924390,
    compare: '6% vs prior 3 months',
    spendDown: true,
    bars: [
      _Bar('Jun', 312400),
      _Bar('Jul', 325540),
      _Bar('Aug', 286450),
    ],
    moneyIn: 1487600,
    moneyOut: 924390,
    inChange: '+6.2%',
    outChange: '+2.8%',
    changeSuffix: 'last 3 months',
    categories: [
      _Category('Shopping', Icons.shopping_bag_outlined, AppColors.tileLavender,
          AppColors.iconLavender, 305100),
      _Category('Bills & utilities', Icons.receipt_long_outlined,
          AppColors.tileAmber, AppColors.iconAmber, 238700),
      _Category('Transport', Icons.flight_outlined, AppColors.tileBlue,
          AppColors.iconBlue, 140200),
      _Category('Food & drinks', Icons.restaurant_outlined, AppColors.tileMint,
          AppColors.iconMint, 130090),
      _Category('Others', Icons.grid_view_rounded, AppColors.tileGrey,
          AppColors.iconGrey, 110300),
    ],
  ),
];

// ─────────────────────────────────── Helpers ─────────────────────────────────
String _naira(int v) =>
    '₦${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

int _maxBarIndex(_Period p) {
  var best = 0;
  for (var i = 1; i < p.bars.length; i++) {
    if (p.bars[i].value > p.bars[best].value) best = i;
  }
  return best;
}

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(22),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0F1B1F2E),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
  );
}

// ─────────────────────────────────── Screen ──────────────────────────────────
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({
    super.key,
    this.onDetailsTap,
    this.onFilterTap,
    this.onMoreTap,
  });

  /// "Details" link next to Top spending.
  final VoidCallback? onDetailsTap;

  /// The dropdown button in the header.
  final VoidCallback? onFilterTap;

  /// The "..." button on the Total spent card.
  final VoidCallback? onMoreTap;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  int _period = 0;
  int _bar = _maxBarIndex(_periods[0]);

  void _setPeriod(int i) {
    setState(() {
      _period = i;
      _bar = _maxBarIndex(_periods[i]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final p = _periods[_period];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark status-bar icons, because this page has a light background.
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  _Header(
                    onBack: () => Navigator.maybePop(context),
                    onFilter: widget.onFilterTap,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        8,
                        20,
                        68 + 12 + media.padding.bottom + 28,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PeriodTabs(selected: _period, onChanged: _setPeriod),
                          const SizedBox(height: 16),
                          _TotalSpentCard(
                            period: p,
                            activeBar: _bar,
                            onBarTap: (i) => setState(() => _bar = i),
                            onMore: widget.onMoreTap,
                          ),
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _FlowCard(
                                  label: 'Money in',
                                  amount: p.moneyIn,
                                  change: '${p.inChange} ${p.changeSuffix}',
                                  incoming: true,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _FlowCard(
                                  label: 'Money out',
                                  amount: p.moneyOut,
                                  change: '${p.outChange} ${p.changeSuffix}',
                                  incoming: false,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _SectionRow(
                            title: 'Top spending',
                            action: 'Details',
                            onAction: widget.onDetailsTap,
                          ),
                          const SizedBox(height: 14),
                          _TopSpendingCard(period: p),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ZellifyBottomNav(
                currentIndex: 1, // Insights
                onTap: (index) {
                  // Home goes back; Cards replaces this screen.
                  // Other tabs will be connected when those screens exist.
                  if (index == 0) {
                    Navigator.of(context).maybePop();
                  } else if (index == 2) {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ExchangeScreen()),
                    );
                  } else if (index == 3) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const CardsScreen()),
                    );
                  } else if (index == 4) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) => const ProfileScreen()),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────── Components ────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.onBack, this.onFilter});
  final VoidCallback onBack;
  final VoidCallback? onFilter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          _SquareButton(icon: Icons.arrow_back, onTap: onBack),
          Expanded(
            child: Center(
              child: Text('Money insights',
                  style: AppText.style(17, FontWeight.w700, AppColors.ink)),
            ),
          ),
          _SquareButton(
              icon: Icons.keyboard_arrow_down_rounded, onTap: onFilter),
        ],
      ),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, this.onTap, this.size = 40});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _C.iconBtn,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 20, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _C.segmentBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _periods.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: i == selected
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                  child: Text(
                    _periods[i].label,
                    style: AppText.style(
                      12,
                      i == selected ? FontWeight.w700 : FontWeight.w600,
                      i == selected ? AppColors.ink : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TotalSpentCard extends StatelessWidget {
  const _TotalSpentCard({
    required this.period,
    required this.activeBar,
    required this.onBarTap,
    this.onMore,
  });
  final _Period period;
  final int activeBar;
  final ValueChanged<int> onBarTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final down = period.spendDown;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total spent',
                        style: AppText.style(
                            11, FontWeight.w500, AppColors.textMuted)),
                    const SizedBox(height: 6),
                    Text(_naira(period.total),
                        style:
                            AppText.style(30, FontWeight.w800, AppColors.ink)),
                  ],
                ),
              ),
              _SquareButton(
                  icon: Icons.more_horiz_rounded, onTap: onMore, size: 36),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: down ? AppColors.tileMint : AppColors.tilePink,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  down
                      ? Icons.arrow_downward_rounded
                      : Icons.arrow_upward_rounded,
                  size: 11,
                  color: down ? AppColors.iconMint : AppColors.iconPink,
                ),
                const SizedBox(width: 4),
                Text(
                  period.compare,
                  style: AppText.style(10, FontWeight.w700,
                      down ? AppColors.iconMint : AppColors.iconPink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _BarChart(
            bars: period.bars,
            active: activeBar,
            onSelect: onBarTap,
          ),
        ],
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({
    required this.bars,
    required this.active,
    required this.onSelect,
  });
  final List<_Bar> bars;
  final int active;
  final ValueChanged<int> onSelect;

  static const double _maxBarHeight = 96;

  @override
  Widget build(BuildContext context) {
    var maxValue = 1;
    for (final b in bars) {
      if (b.value > maxValue) maxValue = b.value;
    }
    final barWidth = bars.length > 4 ? 10.0 : 22.0;

    return SizedBox(
      height: 146,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // Value bubble above the selected bar.
                    SizedBox(
                      height: 22,
                      child: OverflowBox(
                        maxWidth: 90,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: i == active ? 1 : 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.greenDark,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _naira(bars[i].value),
                              style: AppText.style(
                                  9, FontWeight.w700, AppColors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 350),
                      curve: Curves.easeOutCubic,
                      width: barWidth,
                      height: _maxBarHeight * bars[i].value / maxValue,
                      decoration: BoxDecoration(
                        color: i == active ? _C.barActive : _C.barIdle,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: i == active
                            ? const [
                                BoxShadow(
                                  color: Color(0x553BC69B),
                                  blurRadius: 10,
                                ),
                              ]
                            : const [],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      bars[i].label,
                      style: AppText.style(
                          10,
                          i == active ? FontWeight.w700 : FontWeight.w500,
                          i == active ? AppColors.ink : AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FlowCard extends StatelessWidget {
  const _FlowCard({
    required this.label,
    required this.amount,
    required this.change,
    required this.incoming,
  });
  final String label;
  final int amount;
  final String change;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final fg = incoming ? AppColors.iconMint : AppColors.iconPink;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: incoming ? AppColors.tileMint : AppColors.tilePink,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              incoming ? Icons.south_west_rounded : Icons.north_east_rounded,
              size: 18,
              color: fg,
            ),
          ),
          const SizedBox(height: 14),
          Text(label,
              style: AppText.style(11, FontWeight.w500, AppColors.textMuted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(_naira(amount),
                style: AppText.style(17, FontWeight.w800, AppColors.ink)),
          ),
          const SizedBox(height: 6),
          Text(change, style: AppText.style(10, FontWeight.w700, fg)),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.title, required this.action, this.onAction});
  final String title;
  final String action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Text(title, style: AppText.style(14, FontWeight.w700, AppColors.ink)),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onAction,
            child: Text(action,
                style: AppText.style(11, FontWeight.w600, AppColors.green)),
          ),
        ],
      ),
    );
  }
}

class _TopSpendingCard extends StatelessWidget {
  const _TopSpendingCard({required this.period});
  final _Period period;

  @override
  Widget build(BuildContext context) {
    final cats = period.categories;
    var maxAmount = 1;
    for (final c in cats) {
      if (c.amount > maxAmount) maxAmount = c.amount;
    }

    final rows = <Widget>[];
    for (var i = 0; i < cats.length; i++) {
      if (i > 0) {
        rows.add(Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: AppColors.divider,
        ));
      }
      rows.add(_CategoryRow(
        category: cats[i],
        percent: (cats[i].amount / period.total * 100).round(),
        fill: cats[i].amount / maxAmount * 0.82,
      ));
    }

    return Container(
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.percent,
    required this.fill,
  });
  final _Category category;
  final int percent;
  final double fill; // 0..1 width of the green progress bar

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: category.bg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(category.icon, size: 20, color: category.fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        category.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppText.style(12, FontWeight.w700, AppColors.ink),
                      ),
                    ),
                    Text('$percent%',
                        style: AppText.style(
                            10, FontWeight.w500, AppColors.textMuted)),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: _C.track,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: fill),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => FractionallySizedBox(
                        widthFactor: v.clamp(0.0, 1.0),
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: _C.barActive,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 70,
            child: Text(
              _naira(category.amount),
              textAlign: TextAlign.right,
              style: AppText.style(12, FontWeight.w800, AppColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
