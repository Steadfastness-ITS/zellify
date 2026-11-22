// lib/features/cards/cards_screen.dart
//
// "My cards" screen (Cards tab). Uses the same AppColors, AppText and
// ZellifyBottomNav as the Home screen.
//
// The card below is MOCK data (`CardData.mock`). When your backend is ready,
// build a CardData from the API response and pass it in:
//   CardsScreen(card: myCardFromApi)
// and use the callbacks (onCardChanged, onAddCard, onRequestPhysical) to save
// changes (freeze, limits, switches) to the server.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import '../../shared/widgets/zellify_bottom_nav.dart';
import '../exchange/exchange_screen.dart';
import '../insights/insights_screen.dart';
import '../profile/profile_screen.dart';
import '../profile/profile_store.dart';

/// Colors that only this screen needs (not in AppColors yet).
class _C {
  static const iconBtn = Color(0xFFEBEFEC); // back / plus buttons
  static const cardStart = Color(0xFF194239); // card gradient (top-left)
  static const cardMid = Color(0xFF13302B);
  static const cardEnd = Color(0xFF0F211E); // card gradient (bottom-right)
  static const cardCircle = Color(0x0F5BE0B5); // soft decorative circles
  static const logo = Color(0xFF5BE0B5); // mint logo square
  static const banner = Color(0xFFE0F4ED); // "Need a physical card?" banner
  static const bannerIcon = Color(0xFF2E8B70);
  static const toggleOff = Color(0xFFD9DEDB);
  static const mcRed = Color(0xFFEE5B3F);
  static const mcAmber = Color(0xFFE9A23B);
}

// ─────────────────────────────────── Model ───────────────────────────────────
class CardData {
  const CardData({
    required this.holder,
    required this.number,
    required this.expiry,
    required this.cvv,
    this.isVirtual = true,
    this.frozen = false,
    this.dailyLimit = 500000,
    this.onlinePayments = true,
    this.international = true,
  });

  final String holder;
  final String number; // 16 digits, no spaces
  final String expiry; // MM/YY
  final String cvv;
  final bool isVirtual;
  final bool frozen;
  final int dailyLimit;
  final bool onlinePayments;
  final bool international;

  /// Mock card used until the backend is connected.
  static const mock = CardData(
    holder: 'STEADFASTNESS',
    number: '5403881234562841',
    expiry: '08/29',
    cvv: '372',
  );

  /// "5403 88•• •••• 2841"
  String get masked =>
      '${number.substring(0, 4)} ${number.substring(4, 6)}•• •••• ${number.substring(12)}';

  /// "5403 8812 3456 2841"
  String get spaced => [
        for (var i = 0; i < number.length; i += 4) number.substring(i, i + 4),
      ].join(' ');

  CardData copyWith({
    String? holder,
    bool? frozen,
    int? dailyLimit,
    bool? onlinePayments,
    bool? international,
  }) {
    return CardData(
      holder: holder ?? this.holder,
      number: number,
      expiry: expiry,
      cvv: cvv,
      isVirtual: isVirtual,
      frozen: frozen ?? this.frozen,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      onlinePayments: onlinePayments ?? this.onlinePayments,
      international: international ?? this.international,
    );
  }
}

// ─────────────────────────────────── Helpers ─────────────────────────────────
String _naira(int v) =>
    '₦${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',')}';

BoxDecoration _cardDecoration({double radius = 22}) {
  return BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(radius),
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
class CardsScreen extends StatefulWidget {
  const CardsScreen({
    super.key,
    this.card,
    this.onCardChanged,
    this.onAddCard,
    this.onRequestPhysical,
  });

  /// Leave null to use the mock card (named after the saved profile).
  final CardData? card;

  /// Called whenever the user freezes / unfreezes or changes a setting.
  final ValueChanged<CardData>? onCardChanged;

  /// The "+" button in the header.
  final VoidCallback? onAddCard;

  /// The "Need a physical card?" banner.
  final VoidCallback? onRequestPhysical;

  @override
  State<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends State<CardsScreen> {
  late CardData _card = widget.card ??
      CardData.mock.copyWith(holder: ProfileStore.instance.cardHolder);

  void _update(CardData next) {
    setState(() => _card = next);
    widget.onCardChanged?.call(next);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showDetails() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _DetailsSheet(card: _card),
    );
  }

  Future<void> _showSettings() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _SettingsSheet(card: _card, onChanged: _update),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

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
                    onAdd: widget.onAddCard ??
                        () => _toast('Adding new cards is coming soon'),
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
                          _VirtualCard(card: _card),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _ActionTile(
                                  label: _card.frozen ? 'Unfreeze' : 'Freeze',
                                  icon: _card.frozen
                                      ? Icons.lock_open_outlined
                                      : Icons.lock_outline_rounded,
                                  bg: AppColors.tileMint,
                                  fg: AppColors.iconMint,
                                  onTap: () => _update(
                                      _card.copyWith(frozen: !_card.frozen)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ActionTile(
                                  label: 'Details',
                                  icon: Icons.visibility_outlined,
                                  bg: AppColors.tileLavender,
                                  fg: AppColors.iconLavender,
                                  onTap: _showDetails,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _ActionTile(
                                  label: 'Settings',
                                  icon: Icons.settings_outlined,
                                  bg: AppColors.tileBlue,
                                  fg: AppColors.iconBlue,
                                  onTap: _showSettings,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          _CardDetailsCard(card: _card, onRowTap: _showSettings),
                          const SizedBox(height: 16),
                          _PhysicalCardBanner(
                            onTap: widget.onRequestPhysical ??
                                () => _toast('Physical cards are coming soon'),
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
                currentIndex: 3, // Cards
                onTap: (index) {
                  // Home goes back; Insights replaces this screen.
                  // Other tabs will be connected when those screens exist.
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
  const _Header({required this.onBack, required this.onAdd});
  final VoidCallback onBack;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          _SquareButton(icon: Icons.arrow_back, onTap: onBack),
          Expanded(
            child: Center(
              child: Text('My cards',
                  style: AppText.style(17, FontWeight.w700, AppColors.ink)),
            ),
          ),
          _SquareButton(icon: Icons.add, onTap: onAdd),
        ],
      ),
    );
  }
}

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

// ── The green virtual card ───────────────────────────────────────────────────
class _VirtualCard extends StatelessWidget {
  const _VirtualCard({required this.card});
  final CardData card;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_C.cardStart, _C.cardMid, _C.cardEnd],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33173D36),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: AspectRatio(
          aspectRatio: 1.62,
          child: Stack(
            children: [
              // Decorative circles
              const Positioned(
                right: -48,
                top: -62,
                child: _Circle(size: 190),
              ),
              const Positioned(
                left: -46,
                bottom: -78,
                child: _Circle(size: 150),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Logo + VIRTUAL pill
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _C.logo,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            Icons.bolt_rounded,
                            size: 20,
                            color: AppColors.greenDark,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0x0FFFFFFF),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0x33FFFFFF),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            card.frozen
                                ? 'FROZEN'
                                : (card.isVirtual ? 'VIRTUAL' : 'PHYSICAL'),
                            style: AppText.style(
                                9, FontWeight.w700, AppColors.white,
                                letterSpacing: 1),
                          ),
                        ),
                      ],
                    ),
                    // Contactless + number
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.contactless_outlined,
                            size: 22, color: Color(0xCCFFFFFF)),
                        const SizedBox(height: 10),
                        Text(
                          card.masked,
                          style: AppText.style(
                              18, FontWeight.w700, AppColors.white,
                              letterSpacing: 1.4),
                        ),
                      ],
                    ),
                    // Holder / expiry / Mastercard
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          flex: 5,
                          child: _CardField(
                              label: 'CARD HOLDER', value: card.holder),
                        ),
                        Expanded(
                          flex: 4,
                          child:
                              _CardField(label: 'EXPIRES', value: card.expiry),
                        ),
                        const _MastercardMark(),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Frozen cards turn grey.
    if (!card.frozen) return body;
    return ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.grey, BlendMode.saturation),
      child: body,
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: _C.cardCircle,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _CardField extends StatelessWidget {
  const _CardField({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppText.style(7.5, FontWeight.w600, const Color(0x99FFFFFF),
              letterSpacing: 0.8),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.style(11, FontWeight.w700, AppColors.white),
        ),
      ],
    );
  }
}

class _MastercardMark extends StatelessWidget {
  const _MastercardMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 28,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: _C.mcRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 0,
            child: Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0xE6E9A23B),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Freeze / Details / Settings tiles ────────────────────────────────────────
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: _cardDecoration(radius: 20),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 20, color: fg),
            ),
            const SizedBox(height: 10),
            Text(label,
                style: AppText.style(11, FontWeight.w700, AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

// ── "Card details" list ──────────────────────────────────────────────────────
class _CardDetailsCard extends StatelessWidget {
  const _CardDetailsCard({required this.card, required this.onRowTap});
  final CardData card;
  final VoidCallback onRowTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Card details',
              style: AppText.style(15, FontWeight.w800, AppColors.ink)),
          const SizedBox(height: 6),
          _DetailRow(
            label: 'Spending limit',
            value: '${_naira(card.dailyLimit)} / day',
            valueColor: AppColors.ink,
            onTap: onRowTap,
          ),
          _DetailRow(
            label: 'Online payments',
            value: card.onlinePayments ? 'Enabled' : 'Disabled',
            valueColor:
                card.onlinePayments ? AppColors.green : AppColors.textMuted,
            onTap: onRowTap,
          ),
          _DetailRow(
            label: 'International',
            value: card.international ? 'Enabled' : 'Disabled',
            valueColor:
                card.international ? AppColors.green : AppColors.textMuted,
            onTap: onRowTap,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.onTap,
  });
  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.divider, width: 1),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: AppText.style(
                      12, FontWeight.w500, AppColors.textMuted)),
            ),
            Text(value, style: AppText.style(12, FontWeight.w700, valueColor)),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── "Need a physical card?" banner ───────────────────────────────────────────
class _PhysicalCardBanner extends StatelessWidget {
  const _PhysicalCardBanner({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        decoration: BoxDecoration(
          color: _C.banner,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Need a physical card?',
                      style:
                          AppText.style(13, FontWeight.w800, AppColors.ink)),
                  const SizedBox(height: 4),
                  Text('Get it delivered in 3–5 days.',
                      style: AppText.style(
                          10.5, FontWeight.w500, AppColors.textMuted)),
                ],
              ),
            ),
            Transform.rotate(
              angle: -0.14,
              child: Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _C.bannerIcon,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.credit_card_outlined,
                    size: 26, color: AppColors.white),
              ),
            ),
            const SizedBox(width: 10),
            Icon(Icons.chevron_right, size: 22, color: AppColors.ink),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────── Bottom sheets ───────────────────────────────
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

/// Full card details with Show / Hide and Copy (mock data for now).
class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({required this.card});
  final CardData card;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  bool _revealed = false;

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text('Card details',
                      style:
                          AppText.style(16, FontWeight.w800, AppColors.ink)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _revealed = !_revealed),
                  child: Row(
                    children: [
                      Icon(
                        _revealed
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 16,
                        color: AppColors.green,
                      ),
                      const SizedBox(width: 6),
                      Text(_revealed ? 'Hide' : 'Show',
                          style: AppText.style(
                              12, FontWeight.w700, AppColors.green)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SheetRow(
              label: 'Card number',
              value: _revealed ? c.spaced : c.masked,
              onCopy: () => _copy('Card number', c.number),
            ),
            _SheetRow(label: 'Card holder', value: c.holder),
            _SheetRow(label: 'Expiry date', value: c.expiry),
            _SheetRow(
              label: 'CVV',
              value: _revealed ? c.cvv : '•••',
              onCopy: () => _copy('CVV', c.cvv),
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({
    required this.label,
    required this.value,
    this.onCopy,
    this.last = false,
  });
  final String label;
  final String value;
  final VoidCallback? onCopy;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style:
                    AppText.style(12, FontWeight.w500, AppColors.textMuted)),
          ),
          Text(value, style: AppText.style(13, FontWeight.w700, AppColors.ink)),
          if (onCopy != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: onCopy,
              child: Icon(Icons.copy_rounded,
                  size: 16, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Daily limit + online / international switches.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.card, required this.onChanged});
  final CardData card;
  final ValueChanged<CardData> onChanged;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  static const _limits = [100000, 250000, 500000, 1000000];
  late CardData _c = widget.card;

  void _update(CardData next) {
    setState(() => _c = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 18),
            Text('Card settings',
                style: AppText.style(16, FontWeight.w800, AppColors.ink)),
            const SizedBox(height: 16),
            Text('Daily spending limit',
                style:
                    AppText.style(12, FontWeight.w500, AppColors.textMuted)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in _limits)
                  GestureDetector(
                    onTap: () => _update(_c.copyWith(dailyLimit: l)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _c.dailyLimit == l
                            ? AppColors.greenDark
                            : _C.banner,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _naira(l),
                        style: AppText.style(
                          12,
                          FontWeight.w700,
                          _c.dailyLimit == l
                              ? AppColors.white
                              : AppColors.greenDark,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _ToggleRow(
              label: 'Online payments',
              value: _c.onlinePayments,
              onChanged: (v) => _update(_c.copyWith(onlinePayments: v)),
            ),
            _ToggleRow(
              label: 'International payments',
              value: _c.international,
              onChanged: (v) => _update(_c.copyWith(international: v)),
              last: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.last = false,
  });
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: AppText.style(13, FontWeight.w600, AppColors.ink)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(3),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value ? AppColors.greenDark : _C.toggleOff,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
