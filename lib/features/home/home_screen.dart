import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import '../../shared/widgets/zellify_bottom_nav.dart';
import '../add_money/add_money_screen.dart';
import '../cards/cards_screen.dart';
import '../exchange/exchange_screen.dart';
import '../exchange/exchange_store.dart';
import '../insights/insights_screen.dart';
import '../profile/profile_guard.dart';
import '../profile/profile_screen.dart';
import '../profile/profile_store.dart';
import '../send/send_money_screen.dart';

// ---------------------------------------------------------------------------
// HOME SCREEN
// The page is built from small pieces (widgets), from top to bottom:
//   _Header  ->  _QuickActionsCard  ->  _PromoBanner  ->  Recent activity
// ---------------------------------------------------------------------------

/// Space between the status bar and the greeting row (photo, name, bell).
const double _headerTopGap = 18;

/// Height of the green header WITHOUT the phone's status bar.
/// 18 (top gap) + 40 (avatar row) + 22 (gap) + 160 (balance card) + 10 (bottom gap)
const double _headerBodyHeight = 250;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  double _offset = 0; // how far the page has been scrolled
  bool _balanceVisible = true;
  final int _tab = 0; // 0 = Home (we will make this change when more screens exist)

  @override
  void initState() {
    super.initState();
    // Load the saved profile (name, photo...) and refresh when it changes.
    ProfileStore.instance.load();
    ProfileStore.instance.addListener(_onProfileChanged);
    // Wallet balances (changes after an exchange or a transfer).
    ExchangeStore.instance.load();
    ExchangeStore.instance.addListener(_onProfileChanged);
    _scroll.addListener(() {
      final o = _scroll.offset < 0 ? 0.0 : _scroll.offset;
      if (o != _offset) {
        setState(() => _offset = o);
      }
    });
  }

  @override
  void dispose() {
    ProfileStore.instance.removeListener(_onProfileChanged);
    ExchangeStore.instance.removeListener(_onProfileChanged);
    _scroll.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  /// Bottom navigation taps. Index 0 = Home (already here), 1 = Insights,
  /// 2 = Exchange (centre button), 3 = Cards, 4 = Me (Profile).
  void _onNavTap(int index) {
    if (index == 1) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const InsightsScreen()),
      );
    } else if (index == 2) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ExchangeScreen()),
      );
    } else if (index == 3) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CardsScreen()),
      );
    } else if (index == 4) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
    }
  }

  /// Opens the Add money screen (tapped from the "Add money" button).
  Future<void> _openAddMoney() async {
    // Adding money needs a finished profile (it gives you your account number).
    if (!await ensureProfileReady(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const AddMoneyScreen()),
    );
  }

  /// Opens the Send Money screen (tapped from the "Send" button).
  Future<void> _openSendMoney() async {
    // Payments need a finished profile and a transaction PIN.
    if (!await ensureProfileReady(context)) return;
    if (!mounted) return;
    final limit = ProfileStore.instance.profile?.dailyLimit ?? 500000;
    final sent = await Navigator.of(context).push<SendRequest>(
      MaterialPageRoute(
        builder: (_) => SendMoneyScreen(
          dailyLimit: limit.toDouble(),
          balance: ExchangeStore.instance.ngn,
        ),
      ),
    );
    // Takes the money out of the naira wallet (replace with your real transfer).
    if (sent != null) await ExchangeStore.instance.debitNgn(sent.amount);
    // Temporary feedback until the real transfer is connected.
    if (sent != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sending ₦${sent.amount.toStringAsFixed(2)} to ${sent.recipient.name}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top;

    // White status-bar icons while the green header is behind them,
    // dark icons once the header has scrolled away.
    final lightStatusIcons = _offset < _headerBodyHeight - 12;
    final overlay = (lightStatusIcons
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);

    // 0 -> 1 while the header scrolls away (drives the soft fade on the card).
    final wash = ((_offset - 100) / 100).clamp(0.0, 1.0).toDouble();

    return Scaffold(
      backgroundColor: AppColors.pageBg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: overlay,
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scroll,
              padding: EdgeInsets.only(bottom: 68 + 12 + media.padding.bottom + 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(
                    safeTop: safeTop,
                    wash: wash,
                    balanceVisible: _balanceVisible,
                    onToggleBalance: () =>
                        setState(() => _balanceVisible = !_balanceVisible),
                    onSend: _openSendMoney,
                    onAddMoney: _openAddMoney,
                    name: ProfileStore.instance.displayName,
                    initials: ProfileStore.instance.initials,
                    avatar: ProfileStore.instance.profile?.avatarBytes,
                    onAvatarTap: () => _onNavTap(4),
                  ),
                  const SizedBox(height: 6),
                  const _QuickActionsCard(),
                  const SizedBox(height: 20),
                  const _PromoBanner(),
                  const SizedBox(height: 15),
                  const _SectionHeader(title: 'Recent activity', action: 'View all'),
                  const SizedBox(height: 18),
                  const _RecentActivityCard(),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: ZellifyBottomNav(
                currentIndex: _tab,
                // Home, Insights and Cards exist for now. We will connect the
                // other tabs when we build those screens.
                onTap: _onNavTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HEADER (green area: greeting, bell, balance card)
// ---------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header({
    required this.safeTop,
    required this.wash,
    required this.balanceVisible,
    required this.onToggleBalance,
    required this.onSend,
    required this.onAddMoney,
    required this.name,
    required this.initials,
    required this.avatar,
    required this.onAvatarTap,
  });

  final double safeTop;
  final double wash;
  final bool balanceVisible;
  final VoidCallback onToggleBalance;
  final VoidCallback onSend;
  final VoidCallback onAddMoney;
  final String name; // first name shown in the greeting
  final String initials;
  final Uint8List? avatar; // profile photo, if the user added one
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, safeTop + _headerTopGap, 20, 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.headerStart,
            AppColors.headerMid,
            AppColors.headerEnd,
          ],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GreetingRow(
            name: name,
            initials: initials,
            avatar: avatar,
            onTap: onAvatarTap,
          ),
          const SizedBox(height: 22),
          _BalanceCard(
            wash: wash,
            balanceVisible: balanceVisible,
            onToggleBalance: onToggleBalance,
            onSend: onSend,
            onAddMoney: onAddMoney,
          ),
        ],
      ),
    );
  }
}

class _GreetingRow extends StatelessWidget {
  const _GreetingRow({
    required this.name,
    required this.initials,
    required this.avatar,
    required this.onTap,
  });

  final String name;
  final String initials;
  final Uint8List? avatar;
  final VoidCallback onTap;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          // Avatar: the user's photo, or their initials (tap to open Profile)
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.mint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: avatar != null
                    ? Image.memory(avatar!,
                        width: 40, height: 40, fit: BoxFit.cover)
                    : Text(
                        initials,
                        style: AppText.style(
                            13, FontWeight.w700, AppColors.greenDark),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: AppText.style(12, FontWeight.w400, AppColors.onDarkMuted,
                      height: 1.3),
                ),
                Text(
                  name,
                  style: AppText.style(16, FontWeight.w700, AppColors.white,
                      height: 1.3),
                ),
              ],
            ),
          ),
          // Notification bell with an orange dot
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.glass,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    size: 20,
                    color: AppColors.white,
                  ),
                ),
                Positioned(
                  top: 9,
                  right: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.notificationDot,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.wash,
    required this.balanceVisible,
    required this.onToggleBalance,
    required this.onSend,
    required this.onAddMoney,
  });

  final double wash;
  final bool balanceVisible;
  final VoidCallback onToggleBalance;
  final VoidCallback onSend;
  final VoidCallback onAddMoney;

  @override
  Widget build(BuildContext context) {
    // The soft fade that appears on the card while it scrolls off the top.
    // Change `enableScrollFade` to false if you ever want to switch it off.
    const bool enableScrollFade = true;
    final fadeOpacity = (wash * 1.2).clamp(0.0, 1.0).toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.glassBorder, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "Available balance (eye)" ............ "₦1,200 cashback"
                SizedBox(
                  height: 20,
                  child: Row(
                    children: [
                      Text(
                        'Available balance',
                        style: AppText.style(
                            12, FontWeight.w500, AppColors.onDarkMuted),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: onToggleBalance,
                        child: Icon(
                          balanceVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 14,
                          color: AppColors.onDarkMuted,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        height: 20,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: const Color(0x2E7FE3C0),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.local_activity_outlined,
                              size: 11,
                              color: AppColors.mintLight,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '₦1,200 cashback',
                              style: AppText.style(
                                  10, FontWeight.w700, AppColors.mintLight),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // The big balance
                Text(
                  balanceVisible ? ExchangeStore.instance.ngnText : '₦ ••••••••',
                  style: AppText.style(30, FontWeight.w800, AppColors.white,
                      height: 1.2, letterSpacing: -0.5),
                ),
                const SizedBox(height: 22),
                // Send / Add money / More
                Row(
                  children: [
                    Expanded(
                      child: _HeaderAction(
                        label: 'Send',
                        icon: Icons.north_east_rounded,
                        onTap: onSend,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeaderAction(
                        label: 'Add money',
                        icon: Icons.south_west_rounded,
                        onTap: onAddMoney,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: _HeaderAction(
                        label: 'More',
                        icon: Icons.more_horiz_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (enableScrollFade && wash > 0)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Color.fromRGBO(244, 246, 243, fadeOpacity),
                        const Color.fromRGBO(244, 246, 243, 0),
                      ],
                      stops: [0.0, 0.4 + 0.5 * wash],
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

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.label, required this.icon, this.onTap});

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.glassSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: AppColors.mintLight),
            const SizedBox(width: 5),
            Text(
              label,
              style: AppText.style(12, FontWeight.w700, AppColors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// QUICK ACTIONS (2 rows x 4 icons)
// ---------------------------------------------------------------------------
class _QuickAction {
  const _QuickAction(this.label, this.icon, this.bg, this.fg);

  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
}

const List<_QuickAction> _quickActions = [
  _QuickAction('Airtime', Icons.smartphone_outlined, AppColors.tileMint,
      AppColors.iconMint),
  _QuickAction('Data', Icons.signal_cellular_alt_rounded,
      AppColors.tileLavender, AppColors.iconLavender),
  _QuickAction('Electricity', Icons.lightbulb_outline, AppColors.tileAmber,
      AppColors.iconAmber),
  _QuickAction(
      'TV', Icons.tv_outlined, AppColors.tileBlue, AppColors.iconBlue),
  _QuickAction(
      'Betting', Icons.sports_soccer, AppColors.tilePink, AppColors.iconPink),
  _QuickAction(
      'Internet', Icons.wifi_rounded, AppColors.tileBlue, AppColors.iconBlue),
  _QuickAction('Gift cards', Icons.card_giftcard_outlined,
      AppColors.tileLavender, AppColors.iconLavender),
  _QuickAction(
      'More', Icons.grid_view_rounded, AppColors.tileGrey, AppColors.iconGrey),
];

class _QuickActionsCard extends StatelessWidget {
  const _QuickActionsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 22,
            child: Row(
              children: [
                Text(
                  'Quick actions',
                  style: AppText.style(14, FontWeight.w700, AppColors.ink),
                ),
                const Spacer(),
                Text(
                  'See all',
                  style: AppText.style(11, FontWeight.w600, AppColors.green),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _actionRow(_quickActions.sublist(0, 4)),
          const SizedBox(height: 18),
          _actionRow(_quickActions.sublist(4, 8)),
        ],
      ),
    );
  }

  Widget _actionRow(List<_QuickAction> items) {
    return Row(
      children: [
        for (final item in items) Expanded(child: _QuickActionItem(item: item)),
      ],
    );
  }
}

class _QuickActionItem extends StatelessWidget {
  const _QuickActionItem({required this.item});

  final _QuickAction item;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: item.bg,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icon, size: 20, color: item.fg),
          ),
          const SizedBox(height: 8),
          Text(
            item.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: AppText.style(10, FontWeight.w500, AppColors.textLabel,
                height: 1.4),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// PROMO BANNER ("Make your money work harder.")
// ---------------------------------------------------------------------------
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {},
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.promoBg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 15,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.promoPurple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'NEW',
                      style: AppText.style(8, FontWeight.w800, AppColors.white,
                          letterSpacing: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Make your money\nwork harder.',
                    style: AppText.style(17, FontWeight.w800, AppColors.ink,
                        height: 1.2),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Save up to 18% p.a. in Fixed Vault',
                    style: AppText.style(10, FontWeight.w500, AppColors.promoSub,
                        height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 78,
              height: 78,
              decoration: const BoxDecoration(
                color: AppColors.promoCircle,
                shape: BoxShape.circle,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    size: 28,
                    color: AppColors.promoPurple,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '18%',
                    style: AppText.style(
                        12, FontWeight.w800, AppColors.promoPurple),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// RECENT ACTIVITY
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action});

  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            Text(
              title,
              style: AppText.style(14, FontWeight.w700, AppColors.ink),
            ),
            const Spacer(),
            Text(
              action,
              style: AppText.style(11, FontWeight.w600, AppColors.green),
            ),
          ],
        ),
      ),
    );
  }
}

class _Transaction {
  const _Transaction({
    required this.name,
    required this.subtitle,
    required this.amount,
    required this.isCredit,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  final String name;
  final String subtitle;
  final String amount;
  final bool isCredit; // true = money in (shown in green)
  final IconData icon;
  final Color bg;
  final Color fg;
}

const List<_Transaction> _transactions = [
  _Transaction(
    name: 'Market Square',
    subtitle: 'Today · Card payment',
    amount: '-₦18,450',
    isCredit: false,
    icon: Icons.shopping_bag_outlined,
    bg: AppColors.tileLavender,
    fg: AppColors.iconLavender,
  ),
  _Transaction(
    name: 'Tobi Williams',
    subtitle: 'Today · Money received',
    amount: '+₦75,000',
    isCredit: true,
    icon: Icons.south_west_rounded,
    bg: AppColors.tileMint,
    fg: AppColors.iconMint,
  ),
  _Transaction(
    name: 'EKEDC Electricity',
    subtitle: 'Yesterday · Bill payment',
    amount: '-₦12,000',
    isCredit: false,
    icon: Icons.lightbulb_outline,
    bg: AppColors.tileAmber,
    fg: AppColors.iconAmber,
  ),
];

class _RecentActivityCard extends StatelessWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < _transactions.length; i++) {
      if (i > 0) {
        rows.add(
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: AppColors.divider,
          ),
        );
      }
      rows.add(_TransactionRow(tx: _transactions[i]));
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.tx});

  final _Transaction tx;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tx.bg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(tx.icon, size: 20, color: tx.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.name,
                    style: AppText.style(13, FontWeight.w700, AppColors.ink,
                        height: 1.3),
                  ),
                  Text(
                    tx.subtitle,
                    style: AppText.style(
                        10.5, FontWeight.w500, AppColors.textMuted,
                        height: 1.4),
                  ),
                ],
              ),
            ),
            Text(
              tx.amount,
              style: AppText.style(
                13,
                FontWeight.w800,
                tx.isCredit ? AppColors.green : AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared look for the white cards (rounded corners + soft shadow)
// ---------------------------------------------------------------------------
BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(20),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0F1B1F2E),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
  );
}
