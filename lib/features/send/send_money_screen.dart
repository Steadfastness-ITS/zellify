// lib/features/send/send_money_screen.dart
//
// Send Money screen. Opened from the "Send" button on the Home balance card.
// Uses the same AppColors, AppText and ZellifyBottomNav as the Home screen.
// If your folders differ, only the three imports below need adjusting.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import '../../shared/widgets/zellify_bottom_nav.dart';
import '../exchange/exchange_screen.dart';
import '../profile/profile_guard.dart';

/// Colors that only this screen needs (not in AppColors yet).
class _C {
  static const field = Color(0xFFEDF1EE); // search field
  static const chip = Color(0xFFEBF7F2); // quick-amount chips
  static const iconBtn = Color(0xFFEBEFEC); // back / history buttons
  static const disabled = Color(0xFF92A4A0); // greyed-out Continue button
  static const hint = Color(0xFF9AA3A0); // empty amount "0.00"
  static const error = Color(0xFFD64545);
}

// ─────────────────────────────────── Models ──────────────────────────────────
class SendRecipient {
  const SendRecipient({
    required this.name,
    required this.handle,
    required this.initials,
    required this.bg,
    required this.fg,
    this.isZellifyUser = true,
  });

  final String name;
  final String handle; // e.g. "Zellify ID · 0991 4001"
  final String initials;
  final Color bg;
  final Color fg;
  final bool isZellifyUser;
}

class SendRequest {
  const SendRequest({
    required this.recipient,
    required this.amount,
    this.note = '',
  });

  final SendRecipient recipient;
  final double amount;
  final String note;
}

// Placeholder recents. Replace with real data from your backend later.
const List<SendRecipient> _demoRecipients = [
  SendRecipient(
    name: 'Morenike Ojo',
    handle: 'Zellify ID · 0991 4001',
    initials: 'MO',
    bg: AppColors.tileLavender,
    fg: AppColors.iconLavender,
  ),
  SendRecipient(
    name: 'Tobi Williams',
    handle: 'Zellify ID · 0874 2210',
    initials: 'TW',
    bg: AppColors.tileMint,
    fg: AppColors.iconMint,
  ),
  SendRecipient(
    name: 'Ayo Bello',
    handle: 'Zellify ID · 0762 9034',
    initials: 'AB',
    bg: AppColors.tileAmber,
    fg: AppColors.iconAmber,
  ),
  SendRecipient(
    name: 'Jide Nwosu',
    handle: 'Zellify ID · 0615 7782',
    initials: 'JN',
    bg: AppColors.tileBlue,
    fg: AppColors.iconBlue,
  ),
];

// ─────────────────────────────────── Helpers ─────────────────────────────────
String _withCommas(String digits) => digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );

String _naira(num v, {bool decimals = true}) {
  final parts = v.toStringAsFixed(decimals ? 2 : 0).split('.');
  return '₦${_withCommas(parts[0])}${parts.length > 1 ? '.${parts[1]}' : ''}';
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
    if (whole.length > 9) return oldValue;
    if (whole.isEmpty && parts.length > 1) whole = '0';

    final decimals = parts.length > 1 ? '.${parts[1]}' : '';
    final out = '${_withCommas(whole)}$decimals';
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: out.length),
    );
  }
}

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

// ─────────────────────────────────── Screen ──────────────────────────────────
class SendMoneyScreen extends StatefulWidget {
  const SendMoneyScreen({
    super.key,
    this.balance = 842650.20,
    this.dailyLimit = 500000,
    this.recipients = _demoRecipients,
    this.quickAmounts = const [5000, 10000, 25000, 50000],
    this.onHistoryTap,
    this.onConfirm,
  });

  /// Wallet balance, used to block overspending.
  final double balance;
  final double dailyLimit;
  final List<SendRecipient> recipients;
  final List<int> quickAmounts;

  /// Tapped from the history icon in the header.
  final VoidCallback? onHistoryTap;

  /// Called after the user confirms. Plug your PIN check / API call in here.
  final Future<void> Function(SendRequest request)? onConfirm;

  @override
  State<SendMoneyScreen> createState() => _SendMoneyScreenState();
}

class _SendMoneyScreenState extends State<SendMoneyScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  SendRecipient? _selected;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (widget.recipients.isNotEmpty) _selected = widget.recipients.first;
    _amountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  double get _amount =>
      double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;

  String? get _error {
    if (_amount > widget.balance) return 'Insufficient balance';
    if (_amount > widget.dailyLimit) {
      return 'Above your daily limit of ${_naira(widget.dailyLimit, decimals: false)}';
    }
    return null;
  }

  bool get _canContinue => _selected != null && _amount > 0 && _error == null;

  void _setAmount(int v) {
    final text = _withCommas(v.toString());
    _amountCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _select(SendRecipient r) {
    setState(() {
      _selected = r;
      _query = '';
      _searchCtrl.clear();
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _pickRecipient() async {
    final picked = await showModalBottomSheet<SendRecipient>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              Text('Choose recipient',
                  style: AppText.style(16, FontWeight.w700, AppColors.ink)),
              const SizedBox(height: 8),
              for (final r in widget.recipients)
                _RecipientTile(
                  recipient: r,
                  selected: r == _selected,
                  onTap: () => Navigator.pop(ctx, r),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _select(picked);
  }

  Future<void> _continue() async {
    FocusScope.of(context).unfocus();

    // Payments need a finished profile (and a transaction PIN).
    if (!await ensureProfileReady(context)) return;
    if (!mounted) return;

    final request = SendRequest(
      recipient: _selected!,
      amount: _amount,
      note: _noteCtrl.text.trim(),
    );

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _ConfirmSheet(request: request),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final pinOk = await showPinSheet(
        context,
        subtitle:
            'Confirm ${_naira(request.amount)} to ${request.recipient.name}',
      );
      if (!pinOk || !mounted) return;
      await widget.onConfirm?.call(request);
      if (mounted) Navigator.of(context).pop(request);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardOpen = media.viewInsets.bottom > 0;
    // Same space the Home screen reserves for the bottom nav.
    final navSpace = keyboardOpen ? 0.0 : 68 + 12 + media.padding.bottom;

    final searching = _query.trim().isNotEmpty;
    final q = _query.trim().toLowerCase();
    final results = widget.recipients
        .where((r) =>
            r.name.toLowerCase().contains(q) ||
            r.handle.toLowerCase().contains(q))
        .toList();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Dark status-bar icons, because this page has a light background.
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
                      _Header(
                        onBack: () => Navigator.maybePop(context),
                        onHistory: widget.onHistoryTap,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SearchField(
                                controller: _searchCtrl,
                                onChanged: (v) => setState(() => _query = v),
                              ),
                              const SizedBox(height: 22),
                              if (searching) ...[
                                const _SectionTitle('Results'),
                                const SizedBox(height: 8),
                                if (results.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 24),
                                    child: Center(
                                      child: Text(
                                        'No matching recipient found',
                                        style: AppText.style(13,
                                            FontWeight.w500, AppColors.textMuted),
                                      ),
                                    ),
                                  )
                                else
                                  for (final r in results)
                                    _RecipientTile(
                                      recipient: r,
                                      selected: r == _selected,
                                      onTap: () => _select(r),
                                    ),
                              ] else ...[
                                const _SectionTitle('Recent people'),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    for (final r in widget.recipients.take(4))
                                      _RecentPerson(
                                        recipient: r,
                                        selected: r == _selected,
                                        onTap: () => _select(r),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 22),
                                _buildTransferCard(),
                                const SizedBox(height: 16),
                                Center(
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.shield_outlined,
                                          size: 16, color: AppColors.green),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Free transfer · Daily limit ${_naira(widget.dailyLimit, decimals: false)}',
                                        style: AppText.style(12,
                                            FontWeight.w500, AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                        child: _ContinueButton(
                          enabled: _canContinue,
                          onPressed: _continue,
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
                    currentIndex: 0, // Send is opened from Home
                    onTap: (index) {
                      // Home goes back; the centre button opens Exchange.
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
          ),
        ),
      ),
    );
  }

  Widget _buildTransferCard() {
    final hasAmount = _amountCtrl.text.isNotEmpty;
    final amountColor = hasAmount ? AppColors.ink : _C.hint;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Label('SEND TO'),
          const SizedBox(height: 12),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _pickRecipient,
            child: Row(
              children: [
                _selected == null
                    ? Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: _C.field,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(Icons.person_add_alt_1_outlined,
                            color: AppColors.textMuted),
                      )
                    : _Avatar(recipient: _selected!, size: 52, brand: true),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selected?.name ?? 'Select recipient',
                        style:
                            AppText.style(15, FontWeight.w700, AppColors.ink),
                      ),
                      if (_selected != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          _selected!.handle,
                          style: AppText.style(
                              12, FontWeight.w500, AppColors.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: AppColors.divider),
          ),
          const _Label('AMOUNT'),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('₦', style: AppText.style(34, FontWeight.w600, amountColor)),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [_AmountFormatter()],
                  cursorColor: AppColors.greenDark,
                  style: AppText.style(40, FontWeight.w800, AppColors.ink),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: AppText.style(40, FontWeight.w800, _C.hint),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!, style: AppText.style(12, FontWeight.w600, _C.error)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < widget.quickAmounts.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: _QuickChip(
                    label: _naira(widget.quickAmounts[i], decimals: false),
                    active: _amount == widget.quickAmounts[i].toDouble(),
                    onTap: () => _setAmount(widget.quickAmounts[i]),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const _Label('NOTE (OPTIONAL)'),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            cursorColor: AppColors.greenDark,
            style: AppText.style(14, FontWeight.w500, AppColors.ink),
            decoration: InputDecoration(
              counterText: '',
              hintText: "What's it for?",
              hintStyle:
                  AppText.style(14, FontWeight.w500, AppColors.textMuted),
              filled: true,
              fillColor: AppColors.pageBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────── Components ────────────────────────────────
class _Header extends StatelessWidget {
  const _Header({required this.onBack, this.onHistory});
  final VoidCallback onBack;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          _SquareIconButton(icon: Icons.arrow_back, onTap: onBack),
          Expanded(
            child: Center(
              child: Text('Send money',
                  style: AppText.style(17, FontWeight.w700, AppColors.ink)),
            ),
          ),
          _SquareIconButton(icon: Icons.history, onTap: onHistory),
        ],
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

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

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      cursorColor: AppColors.greenDark,
      style: AppText.style(14, FontWeight.w500, AppColors.ink),
      decoration: InputDecoration(
        hintText: 'Search name, bank or account',
        hintStyle: AppText.style(14, FontWeight.w500, AppColors.textMuted),
        prefixIcon:
            Icon(Icons.search, size: 20, color: AppColors.textMuted),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close,
                    size: 18, color: AppColors.textMuted),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
        filled: true,
        fillColor: _C.field,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: AppText.style(14, FontWeight.w700, AppColors.ink));
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: AppText.style(10, FontWeight.w700, AppColors.textMuted));
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.recipient,
    required this.size,
    this.brand = false,
  });
  final SendRecipient recipient;
  final double size;

  /// Shows the dark "Z" Zellify badge instead of pastel initials.
  final bool brand;

  @override
  Widget build(BuildContext context) {
    final useBrand = brand && recipient.isZellifyUser;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: useBrand ? AppColors.greenDark : recipient.bg,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(
        useBrand ? 'Z' : recipient.initials,
        style: AppText.style(
          size * 0.34,
          FontWeight.w800,
          useBrand ? AppColors.mint : recipient.fg,
        ),
      ),
    );
  }
}

class _RecentPerson extends StatelessWidget {
  const _RecentPerson({
    required this.recipient,
    required this.selected,
    required this.onTap,
  });
  final SendRecipient recipient;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 62,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: selected ? AppColors.greenDark : Colors.transparent,
                  width: 1.6,
                ),
              ),
              child: _Avatar(recipient: recipient, size: 52),
            ),
            const SizedBox(height: 6),
            Text(
              recipient.name.split(' ').first,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.style(
                11,
                selected ? FontWeight.w700 : FontWeight.w500,
                AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.recipient,
    required this.selected,
    required this.onTap,
  });
  final SendRecipient recipient;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _Avatar(recipient: recipient, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(recipient.name,
                      style: AppText.style(14, FontWeight.w700, AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(recipient.handle,
                      style: AppText.style(
                          12, FontWeight.w500, AppColors.textMuted)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, size: 20, color: AppColors.green),
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.greenDark : _C.chip,
          borderRadius: BorderRadius.circular(12),
        ),
        child: FittedBox(
          child: Text(
            label,
            style: AppText.style(
              12,
              FontWeight.w700,
              active ? AppColors.white : AppColors.greenDark,
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.enabled, required this.onPressed});
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.greenDark,
          disabledBackgroundColor: _C.disabled,
          foregroundColor: AppColors.white,
          disabledForegroundColor: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Continue',
                style: AppText.style(16, FontWeight.w700, AppColors.white)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ),
    );
  }
}

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

// ─────────────────────────────── Confirmation sheet ──────────────────────────
class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.request});
  final SendRequest request;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 20),
            Text('Confirm transfer',
                style: AppText.style(16, FontWeight.w700, AppColors.ink)),
            const SizedBox(height: 14),
            Text(_naira(request.amount),
                style: AppText.style(34, FontWeight.w800, AppColors.ink)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.pageBg,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  _ReviewRow('To', request.recipient.name),
                  _ReviewRow('Account', request.recipient.handle),
                  const _ReviewRow('Fee', 'Free'),
                  if (request.note.isNotEmpty) _ReviewRow('Note', request.note),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.greenDark,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text('Confirm & send',
                    style: AppText.style(16, FontWeight.w700, AppColors.white)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style:
                      AppText.style(14, FontWeight.w600, AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.style(13, FontWeight.w500, AppColors.textMuted)),
          const SizedBox(width: 16),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: AppText.style(13, FontWeight.w700, AppColors.ink)),
          ),
        ],
      ),
    );
  }
}
