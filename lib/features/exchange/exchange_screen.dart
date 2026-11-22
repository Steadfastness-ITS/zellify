// lib/features/exchange/exchange_screen.dart
//
// Exchange (the centre button of the bottom nav): naira <-> USD / GBP / EUR.
//
// What makes it different from a typical bank / BDC / street exchange:
//   - Real mid-market rate, a visible 0.5% fee, NO hidden spread
//   - "You save" comparison against a typical bank margin
//   - Rate locked for 60 seconds on a quote (no surprises at confirm)
//   - Multi-currency wallets: hold dollars, pounds and euros as a hedge
//   - Trend + plain-language insight ("good time to buy / sell")
//   - Rate alerts and auto-save plans (recurring dollar-cost averaging)
//   - Every exchange needs a finished profile + transaction PIN, and respects
//     your tier's daily limit
//
// Rates are SIMULATED until you connect a live FX provider (see exchange_store.dart).

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import '../../shared/widgets/zellify_bottom_nav.dart';
import '../cards/cards_screen.dart';
import '../insights/insights_screen.dart';
import '../profile/profile_guard.dart';
import '../profile/profile_screen.dart';
import '../profile/profile_store.dart';
import 'exchange_store.dart';

class _C {
  static const field = Color(0xFFF4F6F4);
  static const iconBtn = Color(0xFFEBEFEC);
  static const track = Color(0xFFE1E7E3);
  static const danger = Color(0xFFD64545);
  static const handle = Color(0xFFD9DEDB);
  static const disabled = Color(0xFF92A4A0);
}

const _purposes = ['Savings', 'Tuition', 'Travel', 'Business', 'Family support'];

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

(Color, Color) _tone(Currency c) {
  switch (c) {
    case Currency.ngn:
      return (AppColors.tileMint, AppColors.iconMint);
    case Currency.usd:
      return (AppColors.tileBlue, AppColors.iconBlue);
    case Currency.gbp:
      return (AppColors.tileLavender, AppColors.iconLavender);
    case Currency.eur:
      return (AppColors.tileAmber, AppColors.iconAmber);
  }
}

String _fmtPlain(double v) {
  final p = v.toStringAsFixed(2).split('.');
  return '${groupDigits(p[0])}.${p[1]}';
}

String _dateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]}, $h:$m ${d.hour >= 12 ? 'PM' : 'AM'}';
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

/// Formats typed digits as 1,250,000.50 while the user types.
class _AmountFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.replaceAll(',', '');
    if (raw.isEmpty) return newValue.copyWith(text: '');
    if (!RegExp(r'^\d*\.?\d{0,2}$').hasMatch(raw)) return oldValue;
    final parts = raw.split('.');
    var whole = parts[0].replaceAll(RegExp(r'^0+(?=\d)'), '');
    if (whole.length > 10) return oldValue;
    if (whole.isEmpty && parts.length > 1) whole = '0';
    final out =
        '${groupDigits(whole)}${parts.length > 1 ? '.${parts[1]}' : ''}';
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
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

// ─────────────────────────────────── Screen ──────────────────────────────────
class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  final FxRates _rates = FxRates.instance;
  final ExchangeStore _store = ExchangeStore.instance;

  final _sendCtrl = TextEditingController();
  final _getCtrl = TextEditingController();
  final _sendFocus = FocusNode();
  final _getFocus = FocusNode();

  Currency _foreign = Currency.usd;
  bool _buying = true; // true: NGN -> foreign, false: foreign -> NGN
  bool _editingGet = false;
  bool _syncing = false;
  int _range = 1; // 0 = 7D, 1 = 30D, 2 = 90D
  double _swapTurns = 0;

  bool _flash = false;
  double _flashMove = 0;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _rates.start();
    _rates.addListener(_onRates);
    _store.addListener(_onStore);
    _sendCtrl.addListener(_onSendChanged);
    _getCtrl.addListener(_onGetChanged);
    _sendFocus.addListener(() {
      if (_sendFocus.hasFocus) _editingGet = false;
    });
    _getFocus.addListener(() {
      if (_getFocus.hasFocus) _editingGet = true;
    });
    _boot();
  }

  @override
  void dispose() {
    _rates.removeListener(_onRates);
    _rates.stop();
    _store.removeListener(_onStore);
    _flashTimer?.cancel();
    _sendCtrl.dispose();
    _getCtrl.dispose();
    _sendFocus.dispose();
    _getFocus.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _store.load();
    await ProfileStore.instance.load();
    if (!mounted) return;
    final ran = await _store.runDuePlans();
    if (!mounted) return;
    if (ran.isNotEmpty) {
      final r = ran.first;
      _toast(
          'Auto-save ran: ${money(r.from, r.fromAmount)} to ${money(r.to, r.toAmount)}');
    }
    _checkAlerts();
  }

  // ── derived values ──
  double get _rate => _rates.mid(_foreign);
  double get _factor =>
      _buying ? (1 - kFeeRate) / _rate : (1 - kFeeRate) * _rate;
  Currency get _sendCur => _buying ? Currency.ngn : _foreign;
  Currency get _getCur => _buying ? _foreign : Currency.ngn;

  double _parse(String s) => double.tryParse(s.replaceAll(',', '')) ?? 0;
  double get _send => _parse(_sendCtrl.text);

  double get _dailyLimit {
    final l = ProfileStore.instance.profile?.dailyLimit ?? 0;
    return l > 0 ? l.toDouble() : 500000;
  }

  double get _limitLeft => max(0, _dailyLimit - _store.usedTodayNgn);

  String? get _error {
    final s = _send;
    if (s <= 0) return null;
    if (s > _store.balance(_sendCur) + 0.005) {
      return 'Insufficient ${_sendCur.code} balance';
    }
    final ngnEq = _buying ? s : s * _rate;
    if (ngnEq < kMinNgn) {
      return 'Minimum exchange is ${money(Currency.ngn, kMinNgn, decimals: 0)}';
    }
    if (ngnEq > _limitLeft) {
      return _limitLeft <= 0
          ? 'Daily exchange limit reached'
          : 'Above your remaining daily limit of ${money(Currency.ngn, _limitLeft, decimals: 0)}';
    }
    return null;
  }

  bool get _canReview => _send > 0 && _error == null;

  // ── listeners ──
  void _onStore() {
    if (mounted) setState(() {});
  }

  void _onRates() {
    if (!mounted) return;
    _flashTimer?.cancel();
    _recompute();
    setState(() {
      _flash = true;
      _flashMove = _rates.lastMove(_foreign);
    });
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flash = false);
    });
    _checkAlerts();
  }

  Future<void> _checkAlerts() async {
    final hit = await _store.checkAlerts();
    if (!mounted || hit.isEmpty) return;
    final a = hit.first;
    _toast(
        '${a.currency.code} reached ${money(Currency.ngn, a.target)}. Your rate alert is hit.');
  }

  void _setText(TextEditingController c, String t) {
    c.value = TextEditingValue(
      text: t,
      selection: TextSelection.collapsed(offset: t.length),
    );
  }

  /// Keeps the two amount boxes in step with each other.
  void _recompute() {
    _syncing = true;
    if (_editingGet) {
      final g = _parse(_getCtrl.text);
      _setText(_sendCtrl, _getCtrl.text.isEmpty ? '' : _fmtPlain(g / _factor));
    } else {
      final s = _parse(_sendCtrl.text);
      _setText(_getCtrl, _sendCtrl.text.isEmpty ? '' : _fmtPlain(s * _factor));
    }
    _syncing = false;
  }

  void _onSendChanged() {
    if (_syncing || _editingGet) return;
    _recompute();
    setState(() {});
  }

  void _onGetChanged() {
    if (_syncing || !_editingGet) return;
    _recompute();
    setState(() {});
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── actions ──
  void _swap() {
    FocusScope.of(context).unfocus();
    final newSend = _getCtrl.text;
    setState(() {
      _buying = !_buying;
      _swapTurns += 0.5;
      _editingGet = false;
    });
    _syncing = true;
    _setText(_sendCtrl, newSend);
    _syncing = false;
    _recompute();
    setState(() {});
  }

  void _selectForeign(Currency c) {
    if (c == _foreign) return;
    setState(() => _foreign = c);
    _recompute();
    setState(() {});
  }

  void _setSend(double v) {
    _editingGet = false;
    _syncing = true;
    _setText(_sendCtrl, v <= 0 ? '' : _fmtPlain(v));
    _syncing = false;
    _recompute();
    setState(() {});
  }

  void _useMax() {
    final bal = _store.balance(_sendCur);
    final cap = _buying ? _limitLeft : _limitLeft / _rate;
    final v = (min(bal, cap) * 100).floor() / 100;
    _setSend(v);
  }

  /// Opens the currency list for one side of the converter.
  /// Naira is always on one side: pick a foreign currency and naira moves to
  /// the other side; pick naira and the other side becomes a foreign currency.
  Future<void> _pickCurrency({required bool forSend}) async {
    FocusScope.of(context).unfocus();
    final current = forSend ? _sendCur : _getCur;
    final picked = await _sheet<Currency>(
      context,
      (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Handle(),
            const SizedBox(height: 18),
            Text(forSend ? 'Exchange from' : 'Exchange to',
                style: AppText.style(16, FontWeight.w800, AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              'One side is always naira. Pick a foreign currency and naira moves to the other side.',
              style: AppText.style(
                  11, FontWeight.w500, AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 8),
            for (final c in Currency.values)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.pop(ctx, c),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      _Badge(currency: c, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${c.code} · ${c.label}',
                                style: AppText.style(
                                    13, FontWeight.w700, AppColors.ink)),
                            const SizedBox(height: 2),
                            Text(
                                c == Currency.ngn
                                    ? 'Naira wallet'
                                    : '1 ${c.code} = ${money(Currency.ngn, _rates.mid(c))}',
                                style: AppText.style(11, FontWeight.w500,
                                    AppColors.textMuted)),
                          ],
                        ),
                      ),
                      Text(money(c, _store.balance(c)),
                          style: AppText.style(
                              12, FontWeight.w700, AppColors.ink)),
                      if (c == current) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check_circle,
                            size: 18, color: AppColors.green),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != current) _applyPick(forSend, picked);
  }

  /// Turns "side + currency" into the screen's direction:
  ///   send NGN  -> buying a foreign currency
  ///   send FX   -> selling it for naira
  ///   get  FX   -> buying it with naira
  ///   get  NGN  -> selling the foreign currency
  void _applyPick(bool forSend, Currency c) {
    final oldSend = _sendCur;
    setState(() {
      if (c != Currency.ngn) _foreign = c;
      _buying = c == Currency.ngn ? forSend : !forSend;
      _editingGet = false;
    });
    // A different "You send" currency makes the old amount meaningless.
    if (_sendCur != oldSend) {
      _syncing = true;
      _sendCtrl.clear();
      _getCtrl.clear();
      _syncing = false;
    }
    _recompute();
    setState(() {});
  }

  FxQuote _makeQuote() =>
      _store.quote(foreign: _foreign, buying: _buying, send: _send);

  Future<void> _review() async {
    FocusScope.of(context).unfocus();

    // Every exchange needs a finished profile and a transaction PIN.
    if (!await ensureProfileReady(context)) return;
    if (!mounted || !_canReview) return;

    final confirmed = await _sheet<_Confirmed>(
      context,
      (_) => _ReviewSheet(makeQuote: _makeQuote),
    );
    if (confirmed == null || !mounted) return;

    final q = confirmed.quote;
    final pinOk = await showPinSheet(
      context,
      subtitle:
          'Confirm ${money(q.fromCur, q.send)} to ${money(q.toCur, q.get)}',
    );
    if (!pinOk || !mounted) return;

    final rec = await _store.execute(q, purpose: confirmed.purpose);
    if (!mounted) return;
    if (rec == null) {
      _toast('Not enough ${q.fromCur.code} balance for this exchange');
      return;
    }

    _setSend(0);
    await _sheet<void>(context, (_) => _SuccessSheet(record: rec));
  }

  // ─────────────────────────────── UI ───────────────────────────────
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    final navSpace = keyboardOpen ? 0.0 : 68 + 12 + media.padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: AppColors.pageBg,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: navSpace),
                child: SafeArea(
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
                                child: Text('Exchange',
                                    style: AppText.style(
                                        17, FontWeight.w700, AppColors.ink)),
                              ),
                            ),
                            _SquareButton(
                              icon: Icons.history,
                              onTap: () => _sheet<void>(
                                context,
                                (_) => _HistorySheet(records: _store.history),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _walletRow(),
                              const SizedBox(height: 16),
                              _converterCard(),
                              const SizedBox(height: 14),
                              if (_send > 0) ...[
                                _breakdownCard(),
                                const SizedBox(height: 14),
                              ],
                              _trendCard(),
                              const SizedBox(height: 14),
                              _toolsRow(),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  'Rates are simulated until a live FX provider is connected.',
                                  textAlign: TextAlign.center,
                                  style: AppText.style(10, FontWeight.w500,
                                      AppColors.textMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _canReview ? _review : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.greenDark,
                              disabledBackgroundColor: _C.disabled,
                              foregroundColor: AppColors.white,
                              disabledForegroundColor: AppColors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Review exchange',
                                    style: AppText.style(
                                        16, FontWeight.w700, AppColors.white)),
                                const SizedBox(width: 8),
                                const Icon(Icons.arrow_forward, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!keyboardOpen)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ZellifyBottomNav(
                    currentIndex: 2, // Exchange
                    onTap: (index) {
                      if (index == 0) {
                        Navigator.of(context).maybePop();
                      } else if (index == 1) {
                        Navigator.of(context).pushReplacement(MaterialPageRoute(
                            builder: (_) => const InsightsScreen()));
                      } else if (index == 3) {
                        Navigator.of(context).pushReplacement(MaterialPageRoute(
                            builder: (_) => const CardsScreen()));
                      } else if (index == 4) {
                        Navigator.of(context).pushReplacement(MaterialPageRoute(
                            builder: (_) => const ProfileScreen()));
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── wallets ──
  Widget _walletRow() {
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: Currency.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final c = Currency.values[i];
          final selected = c == _foreign;
          return GestureDetector(
            onTap: c == Currency.ngn ? null : () => _selectForeign(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 140,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? AppColors.green : Colors.transparent,
                  width: 1.4,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0F1B1F2E),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      _Badge(currency: c, size: 24),
                      const SizedBox(width: 8),
                      Text('${c.code} wallet',
                          style: AppText.style(
                              10.5, FontWeight.w600, AppColors.textMuted)),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(money(c, _store.balance(c)),
                        style:
                            AppText.style(15, FontWeight.w800, AppColors.ink)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── converter ──
  Widget _converterCard() {
    final err = _error;
    final quickValues =
        _buying ? const [50000, 100000, 250000, 500000] : const [50, 100, 250, 500];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Column(
                children: [
                  _AmountBox(
                    label: 'You send',
                    controller: _sendCtrl,
                    focusNode: _sendFocus,
                    pill: _CurrencyPill(
                      currency: _sendCur,
                      onTap: () => _pickCurrency(forSend: true),
                    ),
                    footer: Row(
                      children: [
                        Text(
                            'Balance ${money(_sendCur, _store.balance(_sendCur))}',
                            style: AppText.style(
                                10.5, FontWeight.w500, AppColors.textMuted)),
                        const Spacer(),
                        GestureDetector(
                          onTap: _useMax,
                          child: Text('Max',
                              style: AppText.style(
                                  11, FontWeight.w800, AppColors.green)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _AmountBox(
                    label: 'You get',
                    controller: _getCtrl,
                    focusNode: _getFocus,
                    pill: _CurrencyPill(
                      currency: _getCur,
                      onTap: () => _pickCurrency(forSend: false),
                    ),
                    footer: Text(
                      'Arrives instantly in your ${_getCur.code} wallet',
                      style: AppText.style(
                          10.5, FontWeight.w500, AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _swap,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.greenDark,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.white, width: 3),
                  ),
                  child: AnimatedRotation(
                    turns: _swapTurns,
                    duration: const Duration(milliseconds: 250),
                    child: const Icon(Icons.swap_vert_rounded,
                        size: 20, color: AppColors.white),
                  ),
                ),
              ),
            ],
          ),
          if (err != null) ...[
            const SizedBox(height: 10),
            Text(err, style: AppText.style(11.5, FontWeight.w600, _C.danger)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in quickValues)
                _QuickChip(
                  label: money(_sendCur, v.toDouble(), decimals: 0),
                  active: _send == v.toDouble(),
                  onTap: () => _setSend(v.toDouble()),
                ),
            ],
          ),
          const SizedBox(height: 14),
          // Live rate
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _flash
                  ? (_flashMove >= 0
                      ? AppColors.tileMint
                      : AppColors.tilePink)
                  : _C.field,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  _flashMove >= 0
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 18,
                  color: _flashMove >= 0
                      ? AppColors.iconMint
                      : AppColors.iconPink,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '1 ${_foreign.code} = ${money(Currency.ngn, _rate)}',
                          style: AppText.style(
                              13, FontWeight.w800, AppColors.ink)),
                      const SizedBox(height: 2),
                      Text('Mid-market rate. No hidden spread.',
                          style: AppText.style(
                              10.5, FontWeight.w500, AppColors.textMuted)),
                    ],
                  ),
                ),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text('Live',
                    style: AppText.style(
                        10.5, FontWeight.w700, AppColors.green)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── breakdown ──
  double _saving(FxQuote q) {
    if (q.buying) {
      final bankGet = q.send / (q.rate * (1 + kBankMargin));
      return (q.get - bankGet) * q.rate;
    }
    return q.get - q.send * q.rate * (1 - kBankMargin);
  }

  Widget _breakdownCard() {
    final q = _makeQuote();
    final saving = _saving(q);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Breakdown',
              style: AppText.style(14, FontWeight.w800, AppColors.ink)),
          const SizedBox(height: 8),
          _KV('You send', money(q.fromCur, q.send)),
          _KV('Fee (${(kFeeRate * 100).toStringAsFixed(1)}%)',
              '-${money(q.fromCur, q.fee)}'),
          _KV('Rate', '1 ${_foreign.code} = ${money(Currency.ngn, q.rate)}'),
          const Divider(height: 18),
          _KV('You get', money(q.toCur, q.get), bold: true),
          if (saving > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.tileMint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.savings_outlined,
                      size: 18, color: AppColors.iconMint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You save about ${money(Currency.ngn, saving, decimals: 0)} compared with a typical bank or BDC rate (assumed ${(kBankMargin * 100).toStringAsFixed(1)}% margin).',
                      style: AppText.style(
                          10.5, FontWeight.w600, AppColors.iconMint,
                          height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── trend + insight ──
  _Insight _insight() {
    final h = _rates.history(_foreign, 30);
    final avg = h.reduce((a, b) => a + b) / h.length;
    final pct = (_rate - avg) / avg * 100;
    final abs = pct.abs().toStringAsFixed(1);
    final good = _buying ? pct <= -1 : pct >= 1;
    final bad = _buying ? pct >= 1 : pct <= -1;
    if (good) {
      return _Insight(
        _buying
            ? '${_foreign.code} is $abs% below its 30-day average. A good time to buy.'
            : '${_foreign.code} is $abs% above its 30-day average. A good time to sell.',
        AppColors.iconMint,
        AppColors.tileMint,
        Icons.thumb_up_alt_outlined,
      );
    }
    if (bad) {
      return _Insight(
        _buying
            ? '${_foreign.code} is $abs% above its 30-day average. You could wait, or set a rate alert.'
            : '${_foreign.code} is $abs% below its 30-day average. Consider waiting for a better rate.',
        AppColors.iconAmber,
        AppColors.tileAmber,
        Icons.hourglass_bottom_rounded,
      );
    }
    return _Insight(
      '${_foreign.code} is close to its 30-day average (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%).',
      AppColors.iconBlue,
      AppColors.tileBlue,
      Icons.horizontal_rule_rounded,
    );
  }

  Widget _trendCard() {
    final days = const [7, 30, 90][_range];
    final pts = _rates.history(_foreign, days);
    final lo = pts.reduce(min);
    final hi = pts.reduce(max);
    final avg = pts.reduce((a, b) => a + b) / pts.length;
    final up = pts.last >= pts.first;
    final ins = _insight();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${_foreign.code} / NGN trend',
                    style: AppText.style(14, FontWeight.w800, AppColors.ink)),
              ),
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _range = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _range == i ? AppColors.greenDark : _C.field,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      const ['7D', '30D', '90D'][i],
                      style: AppText.style(
                        10.5,
                        FontWeight.w700,
                        _range == i ? AppColors.white : AppColors.textMuted,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: CustomPaint(
              painter: _SparkPainter(
                points: pts,
                line: up ? AppColors.green : AppColors.iconPink,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Stat('Low', money(Currency.ngn, lo, decimals: 0)),
              _Stat('Average', money(Currency.ngn, avg, decimals: 0)),
              _Stat('High', money(Currency.ngn, hi, decimals: 0)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ins.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(ins.icon, size: 18, color: ins.fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(ins.text,
                      style: AppText.style(11, FontWeight.w600, ins.fg,
                          height: 1.45)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── smart tools ──
  Widget _toolsRow() {
    final active = _store.alerts.where((a) => !a.triggered).length;
    final plans = _store.plans.where((p) => p.active).length;
    return Row(
      children: [
        Expanded(
          child: _ToolCard(
            icon: Icons.notifications_active_outlined,
            bg: AppColors.tileLavender,
            fg: AppColors.iconLavender,
            title: 'Rate alert',
            subtitle: active == 0
                ? 'Get flagged at your target rate'
                : '$active active',
            onTap: () => _sheet<void>(
              context,
              (_) => _AlertsSheet(currency: _foreign, buying: _buying),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ToolCard(
            icon: Icons.autorenew_rounded,
            bg: AppColors.tileMint,
            fg: AppColors.iconMint,
            title: 'Auto-save',
            subtitle: plans == 0
                ? 'Convert on a schedule'
                : '$plans plan${plans == 1 ? '' : 's'} running',
            onTap: () => _sheet<void>(
              context,
              (_) => _PlansSheet(currency: _foreign),
            ),
          ),
        ),
      ],
    );
  }
}

class _Insight {
  const _Insight(this.text, this.fg, this.bg, this.icon);
  final String text;
  final Color fg;
  final Color bg;
  final IconData icon;
}

// ───────────────────────────────── Small widgets ─────────────────────────────
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

class _Badge extends StatelessWidget {
  const _Badge({required this.currency, required this.size});
  final Currency currency;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _tone(currency);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        currency.symbol,
        style: AppText.style(size * 0.5, FontWeight.w800, fg),
      ),
    );
  }
}

class _CurrencyPill extends StatelessWidget {
  const _CurrencyPill({required this.currency, this.onTap});
  final Currency currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Badge(currency: currency, size: 24),
            const SizedBox(width: 8),
            Text(currency.code,
                style: AppText.style(13, FontWeight.w800, AppColors.ink)),
            if (onTap != null) ...[
              const SizedBox(width: 2),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: AppColors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _AmountBox extends StatelessWidget {
  const _AmountBox({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.pill,
    required this.footer,
  });
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Widget pill;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
      decoration: BoxDecoration(
        color: _C.field,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.style(11, FontWeight.w700, AppColors.textMuted)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_AmountFormatter()],
                  cursorColor: AppColors.greenDark,
                  style: AppText.style(24, FontWeight.w800, AppColors.ink),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: AppText.style(
                        24, FontWeight.w800, const Color(0xFF9AA3A0)),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              pill,
            ],
          ),
          const SizedBox(height: 8),
          footer,
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip(
      {required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? AppColors.greenDark : const Color(0xFFEBF7F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: AppText.style(
            12,
            FontWeight.w700,
            active ? AppColors.white : AppColors.greenDark,
          ),
        ),
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v, {this.bold = false});
  final String k;
  final String v;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(k,
              style: AppText.style(
                  12, FontWeight.w500, AppColors.textMuted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: AppText.style(
                bold ? 15 : 12.5,
                bold ? FontWeight.w800 : FontWeight.w700,
                AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label,
            style: AppText.style(10, FontWeight.w500, AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(value, style: AppText.style(12, FontWeight.w700, AppColors.ink)),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color bg;
  final Color fg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 12),
            Text(title,
                style: AppText.style(13, FontWeight.w800, AppColors.ink)),
            const SizedBox(height: 3),
            Text(subtitle,
                maxLines: 2,
                style: AppText.style(
                    10.5, FontWeight.w500, AppColors.textMuted, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final List<String> options;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EDEA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    options[i],
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

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: value ? AppColors.greenDark : _C.handle,
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
    );
  }
}

InputDecoration _fieldDec(String hint, {String? prefix}) {
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
    filled: true,
    fillColor: _C.field,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
  );
}

// ─────────────────────────────────── Chart ───────────────────────────────────
class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.points, required this.line});
  final List<double> points;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final lo = points.reduce(min);
    final hi = points.reduce(max);
    final span = (hi - lo) == 0 ? 1.0 : (hi - lo);
    const pad = 8.0;
    final dx = size.width / (points.length - 1);
    Offset at(int i) => Offset(
          i * dx,
          pad + (size.height - pad * 2) * (1 - (points[i] - lo) / span),
        );

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final p0 = at(i - 1);
      final p1 = at(i);
      final mx = (p0.dx + p1.dx) / 2;
      path.cubicTo(mx, p0.dy, mx, p1.dy, p1.dx, p1.dy);
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [line.withAlpha(60), line.withAlpha(0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final end = at(points.length - 1);
    canvas.drawCircle(end, 6, Paint()..color = line.withAlpha(50));
    canvas.drawCircle(end, 3.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) =>
      old.points != points || old.line != line;
}

// ─────────────────────────────────── Sheets ──────────────────────────────────
class _Confirmed {
  const _Confirmed(this.quote, this.purpose);
  final FxQuote quote;
  final String purpose;
}

/// Shows the locked quote with a 60-second countdown.
class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.makeQuote});
  final FxQuote Function() makeQuote;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late FxQuote _q = widget.makeQuote();
  Timer? _timer;
  int _left = kQuoteSeconds;
  String _purpose = _purposes.first;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _left = kQuoteSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = max(0, _left - 1));
      if (_left == 0) t.cancel();
    });
  }

  void _refresh() {
    setState(() => _q = widget.makeQuote());
    _startTimer();
  }

  @override
  Widget build(BuildContext context) {
    final expired = _left == 0;
    return Padding(
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
                child: Text('Review exchange',
                    style: AppText.style(16, FontWeight.w800, AppColors.ink)),
              ),
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: _left / kQuoteSeconds,
                      strokeWidth: 3,
                      color: expired ? _C.danger : AppColors.green,
                      backgroundColor: _C.track,
                    ),
                    Text('$_left',
                        style: AppText.style(11, FontWeight.w800,
                            expired ? _C.danger : AppColors.ink)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            expired ? 'This rate has expired.' : 'Your rate is locked for $_left s.',
            style: AppText.style(11, FontWeight.w600,
                expired ? _C.danger : AppColors.textMuted),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(money(_q.toCur, _q.get),
                style: AppText.style(32, FontWeight.w800, AppColors.ink)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('you will receive',
                style:
                    AppText.style(11, FontWeight.w500, AppColors.textMuted)),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              color: AppColors.pageBg,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                _KV('You send', money(_q.fromCur, _q.send)),
                _KV('Rate',
                    '1 ${_q.foreign.code} = ${money(Currency.ngn, _q.rate)}'),
                _KV('Fee', money(_q.fromCur, _q.fee)),
                const _KV('Arrives', 'Instantly'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Purpose (for your records)',
              style:
                  AppText.style(11, FontWeight.w700, AppColors.textMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in _purposes)
                _QuickChip(
                  label: p,
                  active: p == _purpose,
                  onTap: () => setState(() => _purpose = p),
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: expired
                  ? _refresh
                  : () => Navigator.pop(context, _Confirmed(_q, _purpose)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.greenDark,
                foregroundColor: AppColors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(expired ? 'Refresh rate' : 'Confirm & exchange',
                  style: AppText.style(15, FontWeight.w700, AppColors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessSheet extends StatelessWidget {
  const _SuccessSheet({required this.record});
  final ExchangeRecord record;

  @override
  Widget build(BuildContext context) {
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
          Text('Exchange complete',
              style: AppText.style(18, FontWeight.w800, AppColors.ink)),
          const SizedBox(height: 8),
          Text(
            '${money(record.from, record.fromAmount)} is now ${money(record.to, record.toAmount)} in your ${record.to.code} wallet.',
            textAlign: TextAlign.center,
            style: AppText.style(12, FontWeight.w500, AppColors.textMuted,
                height: 1.5),
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
                  style: AppText.style(15, FontWeight.w700, AppColors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySheet extends StatelessWidget {
  const _HistorySheet({required this.records});
  final List<ExchangeRecord> records;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Handle(),
            const SizedBox(height: 18),
            Text('Exchange history',
                style: AppText.style(16, FontWeight.w800, AppColors.ink)),
            const SizedBox(height: 10),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('No exchanges yet',
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
                  itemBuilder: (context, i) {
                    final r = records[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
                            child: Icon(Icons.swap_horiz_rounded,
                                size: 20, color: AppColors.iconMint),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${r.from.code} to ${r.to.code}',
                                    style: AppText.style(
                                        13, FontWeight.w700, AppColors.ink)),
                                const SizedBox(height: 2),
                                Text(
                                    '${_dateTime(r.time)} · ${r.auto ? 'Auto-save' : r.purpose}',
                                    style: AppText.style(10.5, FontWeight.w500,
                                        AppColors.textMuted)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('-${money(r.from, r.fromAmount)}',
                                  style: AppText.style(
                                      12, FontWeight.w700, AppColors.ink)),
                              const SizedBox(height: 2),
                              Text('+${money(r.to, r.toAmount)}',
                                  style: AppText.style(
                                      12, FontWeight.w700, AppColors.green)),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AlertsSheet extends StatefulWidget {
  const _AlertsSheet({required this.currency, required this.buying});
  final Currency currency;
  final bool buying;

  @override
  State<_AlertsSheet> createState() => _AlertsSheetState();
}

class _AlertsSheetState extends State<_AlertsSheet> {
  final ExchangeStore _store = ExchangeStore.instance;
  final _ctrl = TextEditingController();
  late bool _above = !widget.buying; // buying: wait for a drop, selling: wait for a rise
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl.text = _fmtPlain(_suggest());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _now => FxRates.instance.mid(widget.currency);
  double _suggest() => r2(_now * (_above ? 1.02 : 0.98));

  Future<void> _add() async {
    final t = double.tryParse(_ctrl.text.replaceAll(',', '')) ?? 0;
    if (t <= 0) {
      setState(() => _error = 'Enter a target rate');
      return;
    }
    if (_above && t <= _now) {
      setState(() => _error =
          'Pick a rate above the current ${money(Currency.ngn, _now)}');
      return;
    }
    if (!_above && t >= _now) {
      setState(() => _error =
          'Pick a rate below the current ${money(Currency.ngn, _now)}');
      return;
    }
    await _store.addAlert(RateAlert(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      currency: widget.currency,
      above: _above,
      target: t,
    ));
    if (!mounted) return;
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.currency.code;
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Handle(),
            const SizedBox(height: 18),
            Text('Rate alert',
                style: AppText.style(16, FontWeight.w800, AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              'Set the rate you want for $code. We flag it the moment it is reached while you have Exchange open. (Push alerts need your backend.)',
              style: AppText.style(
                  11, FontWeight.w500, AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            _Segmented(
              options: const ['Falls to', 'Rises to'],
              selected: _above ? 1 : 0,
              onChanged: (i) => setState(() {
                _above = i == 1;
                _ctrl.text = _fmtPlain(_suggest());
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            Text('Now: 1 $code = ${money(Currency.ngn, _now)}',
                style:
                    AppText.style(11, FontWeight.w600, AppColors.textMuted)),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_AmountFormatter()],
              style: AppText.style(15, FontWeight.w700, AppColors.ink),
              decoration: _fieldDec('Target rate', prefix: '₦'),
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
                onPressed: _add,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.greenDark,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('Add alert',
                    style: AppText.style(14, FontWeight.w700, AppColors.white)),
              ),
            ),
            if (_store.alerts.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Your alerts',
                  style: AppText.style(13, FontWeight.w800, AppColors.ink)),
              const SizedBox(height: 6),
              for (final a in _store.alerts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        a.triggered
                            ? Icons.notifications_active
                            : Icons.notifications_none_rounded,
                        size: 20,
                        color: a.triggered
                            ? AppColors.green
                            : AppColors.textMuted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${a.currency.code} ${a.above ? 'rises to' : 'falls to'} ${money(Currency.ngn, a.target)}',
                          style: AppText.style(
                              12.5, FontWeight.w700, AppColors.ink),
                        ),
                      ),
                      Text(a.triggered ? 'Reached' : 'Watching',
                          style: AppText.style(
                              10.5,
                              FontWeight.w700,
                              a.triggered
                                  ? AppColors.green
                                  : AppColors.textMuted)),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () async {
                          await _store.removeAlert(a.id);
                          if (mounted) setState(() {});
                        },
                        child: Icon(Icons.delete_outline_rounded,
                            size: 20, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlansSheet extends StatefulWidget {
  const _PlansSheet({required this.currency});
  final Currency currency;

  @override
  State<_PlansSheet> createState() => _PlansSheetState();
}

class _PlansSheetState extends State<_PlansSheet> {
  final ExchangeStore _store = ExchangeStore.instance;
  final _ctrl = TextEditingController();
  late Currency _cur = widget.currency;
  bool _weekly = true;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _day(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  Future<void> _start() async {
    final amt = double.tryParse(_ctrl.text.replaceAll(',', '')) ?? 0;
    if (amt < kMinNgn) {
      setState(() => _error =
          'Minimum is ${money(Currency.ngn, kMinNgn, decimals: 0)} per run');
      return;
    }
    final now = DateTime.now();
    await _store.addPlan(AutoPlan(
      id: now.microsecondsSinceEpoch.toString(),
      currency: _cur,
      amountNgn: amt,
      weekly: _weekly,
      next: _weekly
          ? now.add(const Duration(days: 7))
          : DateTime(now.year, now.month + 1, now.day),
    ));
    if (!mounted) return;
    _ctrl.clear();
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Handle(),
            const SizedBox(height: 18),
            Text('Auto-save in foreign currency',
                style: AppText.style(16, FontWeight.w800, AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              'Protect your savings from naira swings. Buy a fixed amount on a schedule, so you never have to time the market.',
              style: AppText.style(
                  11, FontWeight.w500, AppColors.textMuted, height: 1.5),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                for (final c in Currency.foreign) ...[
                  Expanded(
                    child: _QuickChip(
                      label: c.code,
                      active: c == _cur,
                      onTap: () => setState(() => _cur = c),
                    ),
                  ),
                  if (c != Currency.foreign.last) const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_AmountFormatter()],
              style: AppText.style(15, FontWeight.w700, AppColors.ink),
              decoration: _fieldDec('Amount in naira each time', prefix: '₦'),
            ),
            const SizedBox(height: 12),
            _Segmented(
              options: const ['Weekly', 'Monthly'],
              selected: _weekly ? 0 : 1,
              onChanged: (i) => setState(() => _weekly = i == 0),
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
                onPressed: _start,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.greenDark,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('Start plan',
                    style: AppText.style(14, FontWeight.w700, AppColors.white)),
              ),
            ),
            if (_store.plans.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Your plans',
                  style: AppText.style(13, FontWeight.w800, AppColors.ink)),
              const SizedBox(height: 6),
              for (final p in _store.plans)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      _Badge(currency: p.currency, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${money(Currency.ngn, p.amountNgn, decimals: 0)} to ${p.currency.code}',
                                style: AppText.style(
                                    12.5, FontWeight.w700, AppColors.ink)),
                            const SizedBox(height: 2),
                            Text(
                                '${p.weekly ? 'Weekly' : 'Monthly'} · next ${_day(p.next)}',
                                style: AppText.style(10.5, FontWeight.w500,
                                    AppColors.textMuted)),
                          ],
                        ),
                      ),
                      _Toggle(
                        value: p.active,
                        onChanged: (v) async {
                          await _store.setPlanActive(p, v);
                          if (mounted) setState(() {});
                        },
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () async {
                          await _store.removePlan(p.id);
                          if (mounted) setState(() {});
                        },
                        child: Icon(Icons.delete_outline_rounded,
                            size: 20, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 10),
            Text(
              'Plans run when you open Exchange in this demo. A real backend should run them automatically.',
              style: AppText.style(
                  10, FontWeight.w500, AppColors.textMuted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
