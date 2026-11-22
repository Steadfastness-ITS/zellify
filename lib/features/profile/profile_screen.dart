// lib/features/profile/profile_screen.dart
//
// Profile screen (the "Me" tab). Matches the Profile design and reads the
// user's real saved details from ProfileStore (name, photo, @tag, phone, tier).
// Until the profile is set up it shows a "Complete setup" prompt.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import '../../shared/widgets/zellify_bottom_nav.dart';
import '../cards/cards_screen.dart';
import '../exchange/exchange_screen.dart';
import '../insights/insights_screen.dart';
import 'profile_guard.dart';
import 'profile_setup_screen.dart';
import 'profile_store.dart';

/// Your Profile design shows the icon tile of each menu row stretched wide.
/// true  = exactly like the design.
/// false = a normal 40x40 square tile (like Home, Insights and Cards).
const bool _wideIconTiles = true;

// Mock rewards (no rewards backend yet).
const int _rewardPoints = 3450;
const int _nextTierPoints = 4000;

class _C {
  static const iconBtn = Color(0xFFEBEFEC);
  static const avatarBg = Color(0xFFCDF3E6);
  static const badge = Color(0xFF2FAE8F);
  static const chip = Color(0xFFE4F6EF);
  static const rewardStart = Color(0xFF6B4A9C);
  static const rewardEnd = Color(0xFF9366BE);
  static const danger = Color(0xFFD64545);
}

String _naira(int v) =>
    '₦${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

BoxDecoration _cardDecoration() {
  return BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(24),
    boxShadow: const [
      BoxShadow(
        color: Color(0x0F1B1F2E),
        blurRadius: 16,
        offset: Offset(0, 4),
      ),
    ],
  );
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileStore _store = ProfileStore.instance;

  @override
  void initState() {
    super.initState();
    _store.load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _openSetup() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(editing: _store.isComplete),
      ),
    );
  }

  // ── Account limits ──
  Future<void> _showLimits() {
    final tier = _store.profile?.tier ?? 0;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 18),
              Text('Account limits',
                  style: AppText.style(16, FontWeight.w800, AppColors.ink)),
              const SizedBox(height: 14),
              _TierRow(
                title: 'Tier 2',
                detail: 'Profile + BVN',
                limit: '${_naira(500000)} / day',
                current: tier == 2,
              ),
              const SizedBox(height: 10),
              _TierRow(
                title: 'Tier 3',
                detail: 'Add your NIN',
                limit: '${_naira(10000000)} / day',
                current: tier == 3,
              ),
              const SizedBox(height: 14),
              Text(
                tier == 3
                    ? "You're on the highest tier."
                    : tier == 2
                        ? 'Add your NIN in Personal information to reach Tier 3.'
                        : 'Complete your profile to unlock transfers.',
                style: AppText.style(
                    11.5, FontWeight.w500, AppColors.textMuted, height: 1.5),
              ),
              const SizedBox(height: 6),
              Text(
                'These limits are examples. Set the real ones in your backend.',
                style: AppText.style(
                    10.5, FontWeight.w500, AppColors.textMuted, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Security ──
  Future<void> _showSecurity() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 18),
              Text('Security',
                  style: AppText.style(16, FontWeight.w800, AppColors.ink)),
              const SizedBox(height: 8),
              if (_store.hasPin)
                _SheetAction(
                  icon: Icons.pin_outlined,
                  label: 'Change transaction PIN',
                  onTap: () {
                    Navigator.pop(ctx);
                    _changePin();
                  },
                ),
              _SheetAction(
                icon: Icons.delete_outline_rounded,
                label: 'Reset profile data on this device',
                danger: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmReset();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changePin() async {
    final ok = await showPinSheet(context, title: 'Enter current PIN');
    if (!ok || !mounted) return;
    final next = await showNewPinSheet(context, title: 'Create new PIN');
    if (next == null || !mounted) return;
    await _store.setPin(next);
    if (mounted) _toast('Transaction PIN updated');
  }

  Future<void> _confirmReset() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset profile?',
            style: AppText.style(16, FontWeight.w800, AppColors.ink)),
        content: Text(
          'This deletes your saved profile, photo and PIN from this device. You will need to set up again before sending money.',
          style: AppText.style(12, FontWeight.w500, AppColors.textMuted,
              height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: AppText.style(13, FontWeight.w600, AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Reset',
                style: AppText.style(13, FontWeight.w700, _C.danger)),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _store.reset();
    if (mounted) _toast('Profile reset');
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        body: ListenableBuilder(
          listenable: _store,
          builder: (context, _) {
            return Stack(
              children: [
                SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Row(
                          children: [
                            _SquareButton(
                              icon: Icons.arrow_back,
                              onTap: () => Navigator.maybePop(context),
                            ),
                            Expanded(
                              child: Center(
                                child: Text('Profile',
                                    style: AppText.style(
                                        17, FontWeight.w700, AppColors.ink)),
                              ),
                            ),
                            _SquareButton(
                              icon: Icons.settings_outlined,
                              onTap: _showSecurity,
                            ),
                          ],
                        ),
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
                              _NameCard(store: _store, onSetup: _openSetup),
                              const SizedBox(height: 16),
                              const _RewardsCard(),
                              const SizedBox(height: 16),
                              _SectionCard(
                                title: 'ACCOUNT',
                                children: [
                                  _MenuRow(
                                    icon: Icons.person_outline_rounded,
                                    bg: AppColors.tileMint,
                                    fg: AppColors.iconMint,
                                    title: 'Personal information',
                                    subtitle: 'Name, email and phone',
                                    onTap: _openSetup,
                                  ),
                                  _MenuRow(
                                    icon: Icons.account_balance_outlined,
                                    bg: AppColors.tileBlue,
                                    fg: AppColors.iconBlue,
                                    title: 'Bank accounts',
                                    subtitle: 'Manage linked accounts',
                                    onTap: () => _toast(
                                        'Linking bank accounts is coming soon'),
                                  ),
                                  _MenuRow(
                                    icon: Icons.verified_user_outlined,
                                    bg: AppColors.tileLavender,
                                    fg: AppColors.iconLavender,
                                    title: 'Account limits',
                                    subtitle: 'View transaction tiers',
                                    onTap: _showLimits,
                                    last: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              _SectionCard(
                                title: 'SECURITY & SUPPORT',
                                children: [
                                  _MenuRow(
                                    icon: Icons.fingerprint_rounded,
                                    bg: AppColors.tileMint,
                                    fg: AppColors.iconMint,
                                    title: 'Security',
                                    subtitle: 'PIN, biometrics and devices',
                                    onTap: _showSecurity,
                                  ),
                                  _MenuRow(
                                    icon: Icons.headset_mic_outlined,
                                    bg: AppColors.tileBlue,
                                    fg: AppColors.iconBlue,
                                    title: 'Help & support',
                                    subtitle: 'Chat with us or read FAQs',
                                    onTap: () =>
                                        _toast('Support chat is coming soon'),
                                    last: true,
                                  ),
                                ],
                              ),
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
                    currentIndex: 4, // Me
                    onTap: (index) {
                      if (index == 0) {
                        Navigator.of(context).maybePop();
                      } else if (index == 2) {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const ExchangeScreen()),
                        );
                      } else if (index == 1) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const InsightsScreen()),
                        );
                      } else if (index == 3) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const CardsScreen()),
                        );
                      }
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ───────────────────────────────── Components ────────────────────────────────
class _SquareButton extends StatelessWidget {
  const _SquareButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _C.iconBtn,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 20, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _NameCard extends StatelessWidget {
  const _NameCard({required this.store, required this.onSetup});
  final ProfileStore store;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final p = store.profile;
    final done = store.isComplete && p != null;

    final name = done ? p!.fullName : store.fullDisplayName;
    final subtitle =
        done ? '@${p!.username} · ${p.phoneDisplay}' : 'Profile not set up yet';
    final chipText = done
        ? 'Tier ${p!.tier}${p.verified ? ' verified' : ''}'
        : 'Setup required';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 84,
                height: 84,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _C.avatarBg,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: p?.avatarBytes != null
                      ? Image.memory(p!.avatarBytes!,
                          width: 84, height: 84, fit: BoxFit.cover)
                      : Text(
                          store.initials,
                          style: AppText.style(
                              24, FontWeight.w800, AppColors.greenDark),
                        ),
                ),
              ),
              if (done)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: _C.badge,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.white, width: 3),
                    ),
                    child: const Icon(Icons.check_rounded,
                        size: 13, color: AppColors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(name,
              textAlign: TextAlign.center,
              style: AppText.style(17, FontWeight.w800, AppColors.ink)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: AppText.style(11, FontWeight.w500, AppColors.textMuted)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: done ? _C.chip : AppColors.tileAmber,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  done ? Icons.shield_outlined : Icons.info_outline_rounded,
                  size: 14,
                  color: done ? AppColors.green : AppColors.iconAmber,
                ),
                const SizedBox(width: 6),
                Text(
                  chipText,
                  style: AppText.style(11, FontWeight.w700,
                      done ? AppColors.green : AppColors.iconAmber),
                ),
              ],
            ),
          ),
          if (!done) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onSetup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.greenDark,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('Complete setup',
                    style: AppText.style(14, FontWeight.w700, AppColors.white)),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Required before you can send money or pay bills.',
              textAlign: TextAlign.center,
              style:
                  AppText.style(10.5, FontWeight.w500, AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _RewardsCard extends StatelessWidget {
  const _RewardsCard();

  @override
  Widget build(BuildContext context) {
    final left = _nextTierPoints - _rewardPoints;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.rewardStart, _C.rewardEnd],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Zellify Rewards',
                  style: AppText.style(12, FontWeight.w700, AppColors.white)),
              const Spacer(),
              Text(
                '${_rewardPoints.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')} pts',
                style: AppText.style(12, FontWeight.w700, AppColors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0x4DFFFFFF),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _rewardPoints / _nextTierPoints,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xE6FFFFFF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$left points to unlock Gold benefits',
            style: AppText.style(10, FontWeight.w500, const Color(0xCCFFFFFF)),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: AppText.style(9.5, FontWeight.w700, AppColors.textMuted,
                letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.last = false,
  });
  final IconData icon;
  final Color bg;
  final Color fg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: Row(
          children: [
            Container(
              width: _wideIconTiles ? 124 : 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.style(12, FontWeight.w700, AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.style(
                          10, FontWeight.w500, AppColors.textMuted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Sheet pieces ────────────────────────────────
class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFD9DEDB),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? _C.danger : AppColors.ink;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 14),
            Expanded(
              child:
                  Text(label, style: AppText.style(14, FontWeight.w600, color)),
            ),
          ],
        ),
      ),
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.title,
    required this.detail,
    required this.limit,
    required this.current,
  });
  final String title;
  final String detail;
  final String limit;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: current ? AppColors.tileMint : AppColors.pageBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: current ? AppColors.green : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title,
                        style:
                            AppText.style(13, FontWeight.w800, AppColors.ink)),
                    if (current) ...[
                      const SizedBox(width: 8),
                      Text('Current',
                          style: AppText.style(
                              10, FontWeight.w700, AppColors.green)),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(detail,
                    style: AppText.style(
                        10.5, FontWeight.w500, AppColors.textMuted)),
              ],
            ),
          ),
          Text(limit,
              style: AppText.style(12, FontWeight.w700, AppColors.ink)),
        ],
      ),
    );
  }
}
