// lib/features/profile/profile_guard.dart
//
// Two helpers used before any payment or transfer:
//
//   if (!await ensureProfileReady(context)) return;
//       -> if the profile isn't set up yet, asks the user to set it up first.
//
//   final ok = await showPinSheet(context, subtitle: 'Confirm ₦5,000 to Tobi');
//       -> asks for the 4-digit transaction PIN.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import 'profile_setup_screen.dart';
import 'profile_store.dart';

const _sheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
);

/// Returns true only when the profile (and PIN) is complete. Otherwise it
/// offers the setup screen and returns true if the user finishes it.
Future<bool> ensureProfileReady(BuildContext context) async {
  final store = ProfileStore.instance;
  await store.load();
  if (store.isComplete) return true;
  if (!context.mounted) return false;

  final go = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.white,
    shape: _sheetShape,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _Handle(),
            const SizedBox(height: 22),
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.tileMint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(Icons.person_outline_rounded,
                  size: 28, color: AppColors.iconMint),
            ),
            const SizedBox(height: 16),
            Text('Set up your profile first',
                textAlign: TextAlign.center,
                style: AppText.style(17, FontWeight.w800, AppColors.ink)),
            const SizedBox(height: 8),
            Text(
              'Sending money and paying bills need a verified profile and a transaction PIN. It only takes a minute.',
              textAlign: TextAlign.center,
              style: AppText.style(12, FontWeight.w500, AppColors.textMuted,
                  height: 1.5),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.greenDark,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: Text('Set up profile',
                    style: AppText.style(15, FontWeight.w700, AppColors.white)),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Not now',
                  style: AppText.style(
                      13, FontWeight.w600, AppColors.textMuted)),
            ),
          ],
        ),
      ),
    ),
  );

  if (go != true || !context.mounted) return false;
  final done = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
  );
  return done == true && store.isComplete;
}

/// Asks for the transaction PIN. Returns true when it is correct.
Future<bool> showPinSheet(
  BuildContext context, {
  String title = 'Enter transaction PIN',
  String subtitle = '',
}) async {
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: _sheetShape,
    builder: (_) =>
        _PinSheet(mode: _PinMode.verify, title: title, subtitle: subtitle),
  );
  return result == true;
}

/// Lets the user choose a new 4-digit PIN (type it, then confirm it).
/// Returns the new PIN, or null if cancelled.
Future<String?> showNewPinSheet(
  BuildContext context, {
  String title = 'Create new PIN',
}) async {
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: _sheetShape,
    builder: (_) =>
        _PinSheet(mode: _PinMode.create, title: title, subtitle: ''),
  );
  return result is String ? result : null;
}

class _Handle extends StatelessWidget {
  const _Handle();

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

enum _PinMode { verify, create }

class _PinSheet extends StatefulWidget {
  const _PinSheet({
    required this.mode,
    required this.title,
    required this.subtitle,
  });
  final _PinMode mode;
  final String title;
  final String subtitle;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  // Kept across openings so closing the sheet doesn't reset the lock.
  static int _fails = 0;
  static DateTime? _lockedUntil;

  final FocusNode _focus = FocusNode();
  String _pin = '';
  String _first = '';
  bool _confirming = false;
  String? _error;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  String get _heading =>
      widget.mode == _PinMode.create && _confirming
          ? 'Confirm new PIN'
          : widget.title;

  void _add(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _error = null;
      _pin += d;
    });
    if (_pin.length == 4) _submit();
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    final store = ProfileStore.instance;

    if (widget.mode == _PinMode.verify) {
      final now = DateTime.now();
      if (_lockedUntil != null && now.isBefore(_lockedUntil!)) {
        final s = _lockedUntil!.difference(now).inSeconds + 1;
        setState(() {
          _pin = '';
          _error = 'Too many attempts. Try again in ${s}s';
        });
        return;
      }
      if (store.verifyPin(_pin)) {
        _fails = 0;
        Navigator.pop(context, true);
        return;
      }
      HapticFeedback.heavyImpact();
      _fails++;
      String message;
      if (_fails >= 5) {
        _fails = 0;
        _lockedUntil = now.add(const Duration(seconds: 30));
        message = 'Too many attempts. Try again in 30s';
      } else {
        final left = 5 - _fails;
        message = 'Wrong PIN. $left attempt${left == 1 ? '' : 's'} left';
      }
      setState(() {
        _pin = '';
        _error = message;
      });
      return;
    }

    // create mode
    if (!_confirming) {
      if (isWeakPin(_pin)) {
        setState(() {
          _pin = '';
          _error = 'Choose a less obvious PIN';
        });
        return;
      }
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
      });
    } else if (_pin == _first) {
      Navigator.pop(context, _pin);
    } else {
      setState(() {
        _pin = '';
        _first = '';
        _confirming = false;
        _error = "PINs don't match. Start again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is! KeyDownEvent) return;
        final c = event.character;
        if (c != null && RegExp(r'^\d$').hasMatch(c)) {
          _add(c);
        } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
          _back();
        }
      },
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _Handle(),
              const SizedBox(height: 22),
              Text(_heading,
                  style: AppText.style(17, FontWeight.w800, AppColors.ink)),
              if (widget.subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(widget.subtitle,
                    textAlign: TextAlign.center,
                    style: AppText.style(
                        12, FontWeight.w500, AppColors.textMuted)),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 4; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 9),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _pin.length
                            ? AppColors.greenDark
                            : Colors.transparent,
                        border: Border.all(
                          color: i < _pin.length
                              ? AppColors.greenDark
                              : const Color(0xFFC4CCC8),
                          width: 1.6,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(
                height: 34,
                child: Center(
                  child: Text(
                    _error ?? '',
                    textAlign: TextAlign.center,
                    style: AppText.style(
                        11.5, FontWeight.w600, const Color(0xFFD64545)),
                  ),
                ),
              ),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['', '0', 'del'],
              ])
                Row(
                  children: [
                    for (final k in row)
                      Expanded(
                        child: _Key(
                          label: k,
                          onTap: k.isEmpty
                              ? null
                              : () {
                                  if (k == 'del') {
                                    _back();
                                  } else {
                                    _add(k);
                                  }
                                },
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Center(
          child: label == 'del'
              ? Icon(Icons.backspace_outlined, size: 22, color: AppColors.ink)
              : Text(label,
                  style: AppText.style(24, FontWeight.w700, AppColors.ink)),
        ),
      ),
    );
  }
}
