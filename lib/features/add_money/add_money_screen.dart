// lib/features/add_money/add_money_screen.dart
//
// Add money: a mix of what Opay, PalmPay and Kuda offer, in Zellify's style.
//   1. Bank transfer  : your own account number (your phone number, like Opay and
//                       PalmPay). Free and instant from any bank app.
//   2. Add with card  : Visa / Mastercard / Verve, fee shown before you pay.
//   3. Request money  : a ready-to-send message asking someone to pay you.
//   4. Cash at agent  : how cash-in works at a Zellify agent.
//   + recent top-ups.
//
// MOCK PARTS (replace when your backend is ready):
//   - kPartnerBank and the account number (needs a real partner bank / NUBAN)
//   - the card payment: a real app must use your payment gateway's checkout
//     (Paystack, Flutterwave...). Never send raw card numbers to your own server.
//   - "Demo: simulate an incoming transfer": your bank partner should call
//     your backend when a transfer arrives.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import '../../shared/widgets/zellify_bottom_nav.dart';
import '../exchange/exchange_screen.dart';
import '../exchange/exchange_store.dart';
import '../profile/profile_guard.dart';
import '../profile/profile_store.dart';

/// MOCK: the bank that holds the account numbers.
const String kPartnerBank = 'Zellify Microfinance Bank';

const double _kMinTopUp = 100;
const double _kCardPct = 0.015;

class _C {
  static const field = Color(0xFFF4F6F4);
  static const iconBtn = Color(0xFFEBEFEC);
  static const danger = Color(0xFFD64545);
  static const handle = Color(0xFFD9DEDB);
  static const disabled = Color(0xFF92A4A0);
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]}, $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String _naira(double v, {int decimals = 0}) =>
    money(Currency.ngn, v, decimals: decimals);

/// Fee for paying by card: 1.5%, plus ₦100 from ₦2,500, capped at ₦2,000.
double cardFee(double amount) {
  if (amount <= 0) return 0;
  if (amount < 2500) return r2(amount * _kCardPct);
  return r2(min(amount * _kCardPct + 100, 2000));
}

bool _luhn(String digits) {
  if (digits.length < 13) return false;
  var sum = 0;
  var alt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var n = int.parse(digits[i]);
    if (alt) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    alt = !alt;
  }
  return sum % 10 == 0;
}

String _brand(String digits) {
  if (digits.startsWith('4')) return 'Visa';
  if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(digits)) return 'Mastercard';
  if (RegExp(r'^(506|507|650)').hasMatch(digits)) return 'Verve';
  return '';
}

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

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder,
    {bool dismissible = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(child: builder(ctx)),
    ),
  );
}

// ─────────────────────────────── Input formatters ────────────────────────────
class _AmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return newValue.copyWith(text: '');
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(raw)) return oldValue;
    final parts = raw.split('.');
    var whole = parts[0].replaceAll(RegExp(r'^0+(?=\d)'), '');
    if (whole.length > 9) return oldValue;
    if (whole.isEmpty && parts.length > 1) whole = '0';
    final out =
        '${groupDigits(whole)}${parts.length > 1 ? '.${parts[1]}' : ''}';
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final d = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = d.length > 19 ? d.substring(0, 19) : d;
    final out = [
      for (var i = 0; i < digits.length; i += 4)
        digits.substring(i, min(i + 4, digits.length)),
    ].join(' ');
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final d = newValue.text.replaceAll(RegExp(r'\D'), '');
    final digits = d.length > 4 ? d.substring(0, 4) : d;
    final out = digits.length > 2
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : digits;
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

InputDecoration _dec(String hint, {String? prefix, Widget? suffix}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: AppText.style(14, FontWeight.w500, AppColors.textMuted),
    prefixIcon: prefix == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Center(
              widthFactor: 1,
              child: Text(prefix,
                  style: AppText.style(14, FontWeight.w700, AppColors.ink)),
            ),
          ),
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: suffix,
    counterText: '',
    filled: true,
    fillColor: _C.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );
}

// ─────────────────────────────────── Screen ──────────────────────────────────
class AddMoneyScreen extends StatefulWidget {
  const AddMoneyScreen({super.key});

  @override
  State<AddMoneyScreen> createState() => _AddMoneyScreenState();
}

class _AddMoneyScreenState extends State<AddMoneyScreen> {
  final ExchangeStore _store = ExchangeStore.instance;
  final ProfileStore _profile = ProfileStore.instance;

  @override
  void initState() {
    super.initState();
    _store.load();
    _profile.load();
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String get _accountNumber => _profile.profile?.phone ?? '';
  String get _accountName => _profile.profile?.cardHolder ?? '';

  String get _detailsText =>
      'Bank: $kPartnerBank\nAccount number: $_accountNumber\nAccount name: $_accountName';

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    _toast('$label copied');
  }

  Future<void> _openCard() async {
    final tier = _profile.profile?.tier ?? 2;
    final max = tier == 3 ? 1000000.0 : 200000.0;
    await _sheet<void>(
      context,
      (_) => _CardSheet(maxAmount: max),
      dismissible: false,
    );
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
          listenable: Listenable.merge([_store, _profile]),
          builder: (context, _) {
            final ready = _profile.isComplete;
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
                                child: Text('Add money',
                                    style: AppText.style(
                                        17, FontWeight.w700, AppColors.ink)),
                              ),
                            ),
                            _SquareButton(
                              icon: Icons.history,
                              onTap: () => _sheet<void>(
                                context,
                                (_) => _HistorySheet(records: _store.topups),
                              ),
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
                              Row(
                                children: [
                                  Text('Naira wallet',
                                      style: AppText.style(11, FontWeight.w500,
                                          AppColors.textMuted)),
                                  const Spacer(),
                                  Text(_store.ngnText,
                                      style: AppText.style(14, FontWeight.w800,
                                          AppColors.ink)),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _BankTransferCard(
                                ready: ready,
                                accountNumber: _accountNumber,
                                accountName: _accountName,
                                onCopyNumber: () =>
                                    _copy('Account number', _accountNumber),
                                onCopyAll: () =>
                                    _copy('Account details', _detailsText),
                                onRequest: () => _sheet<void>(
                                  context,
                                  (_) => _RequestSheet(
                                      message: _requestMessage),
                                ),
                                onSetup: () async {
                                  await ensureProfileReady(context);
                                },
                              ),
                              const SizedBox(height: 16),
                              _MethodsCard(
                                onCard: _openCard,
                                onRequest: () => _sheet<void>(
                                  context,
                                  (_) => _RequestSheet(
                                      message: _requestMessage),
                                ),
                                onAgent: () => _sheet<void>(
                                  context,
                                  (_) => _AgentSheet(phone: _accountNumber),
                                ),
                                ready: ready,
                              ),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.tileMint,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.shield_outlined,
                                        size: 18, color: AppColors.iconMint),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Only add money using your own Zellify account number. Zellify staff will never ask you to send money to a personal account.',
                                        style: AppText.style(
                                            10.5,
                                            FontWeight.w600,
                                            AppColors.iconMint,
                                            height: 1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_store.topups.isNotEmpty) ...[
                                const SizedBox(height: 22),
                                Row(
                                  children: [
                                    Text('Recent top-ups',
                                        style: AppText.style(14, FontWeight.w800,
                                            AppColors.ink)),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () => _sheet<void>(
                                        context,
                                        (_) => _HistorySheet(
                                            records: _store.topups),
                                      ),
                                      child: Text('View all',
                                          style: AppText.style(11,
                                              FontWeight.w600, AppColors.green)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  decoration: _cardDecoration(),
                                  child: Column(
                                    children: [
                                      for (var i = 0;
                                          i < min(3, _store.topups.length);
                                          i++) ...[
                                        if (i > 0)
                                          Container(
                                            height: 1,
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 16),
                                            color: AppColors.divider,
                                          ),
                                        _TopUpRow(record: _store.topups[i]),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 18),
                              Center(
                                child: GestureDetector(
                                  onTap: ready
                                      ? () => _sheet<void>(
                                            context,
                                            (_) => const _SimulateSheet(),
                                          )
                                      : null,
                                  child: Text(
                                    'Demo: simulate an incoming bank transfer',
                                    style: AppText.style(10.5, FontWeight.w600,
                                        AppColors.textMuted),
                                  ),
                                ),
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
                    currentIndex: 0, // opened from Home
                    onTap: (index) {
                      if (index == 0) {
                        Navigator.of(context).maybePop();
                      } else if (index == 2) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                              builder: (_) => const ExchangeScreen()),
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

  String get _requestMessage =>
      'Hi! Please send money to my Zellify account.\n\n$_detailsText';
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

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: _C.handle,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      );
}

class _BankTransferCard extends StatelessWidget {
  const _BankTransferCard({
    required this.ready,
    required this.accountNumber,
    required this.accountName,
    required this.onCopyNumber,
    required this.onCopyAll,
    required this.onRequest,
    required this.onSetup,
  });
  final bool ready;
  final String accountNumber;
  final String accountName;
  final VoidCallback onCopyNumber;
  final VoidCallback onCopyAll;
  final VoidCallback onRequest;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.headerStart,
            AppColors.headerMid,
            AppColors.headerEnd,
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.account_balance_outlined,
                    size: 18, color: AppColors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Bank transfer',
                    style: AppText.style(14, FontWeight.w800, AppColors.white)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0x2E7FE3C0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('Free · Instant',
                    style: AppText.style(
                        10, FontWeight.w700, AppColors.mintLight)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (!ready) ...[
            Text(
              'Complete your profile to get your Zellify account number.',
              style: AppText.style(
                  12, FontWeight.w500, AppColors.onDarkMuted,
                  height: 1.5),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onSetup,
              child: Container(
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.glassSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('Set up profile',
                    style: AppText.style(12, FontWeight.w700, AppColors.white)),
              ),
            ),
          ] else ...[
            Text('Your Zellify account number',
                style: AppText.style(
                    11, FontWeight.w500, AppColors.onDarkMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    accountNumber,
                    style: AppText.style(28, FontWeight.w800, AppColors.white,
                        letterSpacing: 1.5),
                  ),
                ),
                GestureDetector(
                  onTap: onCopyNumber,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.glass,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.copy_rounded,
                        size: 17, color: AppColors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.glassBorder),
            const SizedBox(height: 14),
            _DetailLine('Bank', kPartnerBank),
            const SizedBox(height: 8),
            _DetailLine('Account name', accountName),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _GlassButton(
                      icon: Icons.copy_all_rounded,
                      label: 'Copy details',
                      onTap: onCopyAll),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _GlassButton(
                      icon: Icons.send_to_mobile_rounded,
                      label: 'Request money',
                      onTap: onRequest),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k,
            style: AppText.style(11, FontWeight.w500, AppColors.onDarkMuted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(v,
              textAlign: TextAlign.right,
              style: AppText.style(12, FontWeight.w700, AppColors.white)),
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.glassSoft,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: AppColors.mintLight),
            const SizedBox(width: 6),
            Text(label,
                style: AppText.style(11.5, FontWeight.w700, AppColors.white)),
          ],
        ),
      ),
    );
  }
}

class _MethodsCard extends StatelessWidget {
  const _MethodsCard({
    required this.onCard,
    required this.onRequest,
    required this.onAgent,
    required this.ready,
  });
  final VoidCallback onCard;
  final VoidCallback onRequest;
  final VoidCallback onAgent;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('MORE WAYS TO ADD MONEY',
              style: AppText.style(9.5, FontWeight.w700, AppColors.textMuted,
                  letterSpacing: 1.2)),
          const SizedBox(height: 6),
          _MethodRow(
            icon: Icons.credit_card_outlined,
            bg: AppColors.tileBlue,
            fg: AppColors.iconBlue,
            title: 'Add with card',
            subtitle: 'Visa, Mastercard or Verve · 1.5% fee',
            onTap: onCard,
          ),
          _MethodRow(
            icon: Icons.request_quote_outlined,
            bg: AppColors.tileLavender,
            fg: AppColors.iconLavender,
            title: 'Request money',
            subtitle: 'Ask someone to send you money',
            onTap: ready ? onRequest : () {},
          ),
          _MethodRow(
            icon: Icons.storefront_outlined,
            bg: AppColors.tileAmber,
            fg: AppColors.iconAmber,
            title: 'Cash deposit',
            subtitle: 'Pay in cash at a Zellify agent',
            onTap: onAgent,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _MethodRow extends StatelessWidget {
  const _MethodRow({
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
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
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
                      style: AppText.style(12.5, FontWeight.w700, AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppText.style(
                          10.5, FontWeight.w500, AppColors.textMuted)),
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

class _TopUpRow extends StatelessWidget {
  const _TopUpRow({required this.record});
  final TopUpRecord record;

  @override
  Widget build(BuildContext context) {
    final card = record.method == 'Card';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.tileMint,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              card ? Icons.credit_card_outlined : Icons.south_west_rounded,
              size: 20,
              color: AppColors.iconMint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card ? 'Added with card' : 'Bank transfer received',
                    style: AppText.style(12.5, FontWeight.w700, AppColors.ink)),
                const SizedBox(height: 2),
                Text(_dateTime(record.time),
                    style: AppText.style(
                        10.5, FontWeight.w500, AppColors.textMuted)),
              ],
            ),
          ),
          Text('+${_naira(record.amount, decimals: 2)}',
              style: AppText.style(12.5, FontWeight.w800, AppColors.green)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────── Sheets ──────────────────────────────────
class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.records});
  final List<TopUpRecord> records;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Handle(),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Top-up history',
                  style: AppText.style(16, FontWeight.w800, AppColors.ink)),
            ),
            const SizedBox(height: 6),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('No top-ups yet',
                      style: AppText.style(
                          13, FontWeight.w500, AppColors.textMuted)),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: records.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.divider),
                  itemBuilder: (_, i) => _TopUpRow(record: records[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RequestSheet extends StatelessWidget {
  const _RequestSheet({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Handle(),
          const SizedBox(height: 18),
          Text('Request money',
              style: AppText.style(16, FontWeight.w800, AppColors.ink)),
          const SizedBox(height: 4),
          Text(
            'Copy this message and paste it in WhatsApp, SMS or email.',
            style:
                AppText.style(11, FontWeight.w500, AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _C.field,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(message,
                style: AppText.style(12, FontWeight.w600, AppColors.ink,
                    height: 1.55)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: message));
                Navigator.pop(context);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                      const SnackBar(content: Text('Message copied')));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.greenDark,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Copy message',
                  style: AppText.style(14, FontWeight.w700, AppColors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentSheet extends StatelessWidget {
  const _AgentSheet({required this.phone});
  final String phone;

  @override
  Widget build(BuildContext context) {
    final steps = [
      'Visit any Zellify agent near you.',
      phone.isEmpty
          ? 'Tell them your Zellify phone number.'
          : 'Give them your Zellify number: 0$phone.',
      'Hand over the cash and confirm the amount on your phone.',
      'Your wallet is credited instantly. Keep the receipt.',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Handle(),
          const SizedBox(height: 18),
          Text('Cash deposit at an agent',
              style: AppText.style(16, FontWeight.w800, AppColors.ink)),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.tileAmber,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${i + 1}',
                        style: AppText.style(
                            11, FontWeight.w800, AppColors.iconAmber)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(steps[i],
                        style: AppText.style(
                            12.5, FontWeight.w600, AppColors.ink,
                            height: 1.45)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Text(
            'Agent locator and agent codes will appear here once your agent network is connected.',
            style: AppText.style(
                10.5, FontWeight.w500, AppColors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// MOCK: pretends a bank transfer just arrived, so you can test the wallet.
class _SimulateSheet extends StatefulWidget {
  const _SimulateSheet();

  @override
  State<_SimulateSheet> createState() => _SimulateSheetState();
}

class _SimulateSheetState extends State<_SimulateSheet> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final v = double.tryParse(_ctrl.text.replaceAll(',', '')) ?? 0;
    if (v < _kMinTopUp) {
      setState(() => _error = 'Enter at least ${_naira(_kMinTopUp)}');
      return;
    }
    await ExchangeStore.instance.creditNgn(v, method: 'Bank transfer');
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text('${_naira(v, decimals: 2)} received in your wallet')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Handle(),
          const SizedBox(height: 18),
          Text('Simulate incoming transfer',
              style: AppText.style(16, FontWeight.w800, AppColors.ink)),
          const SizedBox(height: 4),
          Text(
            'Demo only. In the real app, your partner bank tells your backend when a transfer arrives, and the wallet is credited automatically.',
            style: AppText.style(
                11, FontWeight.w500, AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_AmountFormatter()],
            style: AppText.style(15, FontWeight.w700, AppColors.ink),
            decoration: _dec('Amount', prefix: '₦'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: AppText.style(11, FontWeight.w600, _C.danger)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _go,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.greenDark,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: Text('Simulate transfer',
                  style: AppText.style(14, FontWeight.w700, AppColors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card payment ──
enum _CardStep { form, processing, done }

class _CardSheet extends StatefulWidget {
  const _CardSheet({required this.maxAmount});
  final double maxAmount;

  @override
  State<_CardSheet> createState() => _CardSheetState();
}

class _CardSheetState extends State<_CardSheet> {
  final _amount = TextEditingController();
  final _number = TextEditingController();
  final _expiry = TextEditingController();
  final _cvv = TextEditingController();
  _CardStep _step = _CardStep.form;
  bool _touched = false;
  double _paid = 0;
  double _credited = 0;

  @override
  void dispose() {
    _amount.dispose();
    _number.dispose();
    _expiry.dispose();
    _cvv.dispose();
    super.dispose();
  }

  double get _amt => double.tryParse(_amount.text.replaceAll(',', '')) ?? 0;
  double get _fee => cardFee(_amt);
  String get _digits => _number.text.replaceAll(' ', '');

  String? get _amountError {
    if (_amt < _kMinTopUp) return 'Minimum is ${_naira(_kMinTopUp)}';
    if (_amt > widget.maxAmount) {
      return 'Maximum is ${_naira(widget.maxAmount)} per top-up';
    }
    return null;
  }

  String? get _cardError =>
      _luhn(_digits) ? null : 'Enter a valid card number';

  String? get _expiryError {
    final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(_expiry.text);
    if (m == null) return 'Use MM/YY';
    final mm = int.parse(m.group(1)!);
    final yy = 2000 + int.parse(m.group(2)!);
    if (mm < 1 || mm > 12) return 'Invalid month';
    final now = DateTime.now();
    if (yy < now.year || (yy == now.year && mm < now.month)) {
      return 'Card has expired';
    }
    return null;
  }

  String? get _cvvError =>
      (_cvv.text.length == 3 || _cvv.text.length == 4) ? null : 'Invalid CVV';

  bool get _valid =>
      _amountError == null &&
      _cardError == null &&
      _expiryError == null &&
      _cvvError == null;

  Future<void> _pay() async {
    setState(() => _touched = true);
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    final amount = _amt;
    final fee = _fee;
    setState(() => _step = _CardStep.processing);

    // MOCK: your payment gateway would charge the card here.
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    await ExchangeStore.instance.creditNgn(amount, method: 'Card', fee: fee);
    if (!mounted) return;
    setState(() {
      _paid = amount + fee;
      _credited = amount;
      _step = _CardStep.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (_step) {
      case _CardStep.processing:
        return SizedBox(
          height: 260,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                    strokeWidth: 3.2, color: AppColors.promoPurple),
              ),
              const SizedBox(height: 18),
              Text('Processing payment...',
                  style: AppText.style(14, FontWeight.w700, AppColors.ink)),
              const SizedBox(height: 4),
              Text('Please do not close this screen',
                  style: AppText.style(
                      11, FontWeight.w500, AppColors.textMuted)),
            ],
          ),
        );
      case _CardStep.done:
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Handle(),
              const SizedBox(height: 24),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutBack,
                builder: (context, v, child) =>
                    Transform.scale(scale: v, child: child),
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: AppColors.greenDark,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 36, color: AppColors.white),
                ),
              ),
              const SizedBox(height: 18),
              Text('Money added',
                  style: AppText.style(18, FontWeight.w800, AppColors.ink)),
              const SizedBox(height: 8),
              Text(
                '${_naira(_credited, decimals: 2)} is now in your naira wallet.\nYou paid ${_naira(_paid, decimals: 2)} including the fee.',
                textAlign: TextAlign.center,
                style: AppText.style(12, FontWeight.w500, AppColors.textMuted,
                    height: 1.55),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.greenDark,
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text('Done',
                      style:
                          AppText.style(15, FontWeight.w700, AppColors.white)),
                ),
              ),
            ],
          ),
        );
      case _CardStep.form:
        return _form();
    }
  }

  Widget _form() {
    final brand = _brand(_digits);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Handle(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text('Add with card',
                    style: AppText.style(16, FontWeight.w800, AppColors.ink)),
              ),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.close_rounded,
                    size: 22, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Field(
            label: 'Amount',
            error: _touched ? _amountError : null,
            child: TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_AmountFormatter()],
              onChanged: (_) => setState(() {}),
              style: AppText.style(15, FontWeight.w700, AppColors.ink),
              decoration: _dec('0.00', prefix: '₦'),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in const [1000, 5000, 10000, 20000, 50000])
                GestureDetector(
                  onTap: () {
                    _amount.text = groupDigits('$v');
                    setState(() {});
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _amt == v.toDouble()
                          ? AppColors.greenDark
                          : const Color(0xFFEBF7F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _naira(v.toDouble()),
                      style: AppText.style(
                        11.5,
                        FontWeight.w700,
                        _amt == v.toDouble()
                            ? AppColors.white
                            : AppColors.greenDark,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _Field(
            label: brand.isEmpty ? 'Card number' : 'Card number · $brand',
            error: _touched ? _cardError : null,
            child: TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: [_CardNumberFormatter()],
              onChanged: (_) => setState(() {}),
              style: AppText.style(15, FontWeight.w700, AppColors.ink),
              decoration: _dec('0000 0000 0000 0000'),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Field(
                  label: 'Expiry',
                  error: _touched ? _expiryError : null,
                  child: TextField(
                    controller: _expiry,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_ExpiryFormatter()],
                    style: AppText.style(15, FontWeight.w700, AppColors.ink),
                    decoration: _dec('MM/YY'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _Field(
                  label: 'CVV',
                  error: _touched ? _cvvError : null,
                  child: TextField(
                    controller: _cvv,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    style: AppText.style(15, FontWeight.w700, AppColors.ink),
                    decoration: _dec('•••'),
                  ),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.pageBg,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                _Line('Amount', _amt > 0 ? _naira(_amt, decimals: 2) : '₦0.00'),
                _Line('Card fee', _amt > 0 ? _naira(_fee, decimals: 2) : '₦0.00'),
                const Divider(height: 14),
                _Line('You pay',
                    _amt > 0 ? _naira(_amt + _fee, decimals: 2) : '₦0.00',
                    bold: true),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Demo card: 4242 4242 4242 4242, any future date, any CVV. Cards are never saved. A real app uses your gateway\'s secure checkout.',
            style: AppText.style(
                10, FontWeight.w500, AppColors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _pay,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.greenDark,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(
                _amt > 0 ? 'Pay ${_naira(_amt + _fee, decimals: 2)}' : 'Pay',
                style: AppText.style(15, FontWeight.w700, AppColors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.error});
  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.style(11, FontWeight.w700, AppColors.textMuted)),
          const SizedBox(height: 6),
          child,
          if (error != null) ...[
            const SizedBox(height: 5),
            Text(error!, style: AppText.style(11, FontWeight.w600, _C.danger)),
          ],
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.k, this.v, {this.bold = false});
  final String k;
  final String v;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(k,
              style: AppText.style(12, FontWeight.w500, AppColors.textMuted)),
          const Spacer(),
          Text(v,
              style: AppText.style(bold ? 14 : 12.5,
                  bold ? FontWeight.w800 : FontWeight.w700, AppColors.ink)),
        ],
      ),
    );
  }
}
