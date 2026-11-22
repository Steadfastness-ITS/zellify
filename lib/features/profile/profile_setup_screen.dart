// lib/features/profile/profile_setup_screen.dart
//
// Profile setup (4 steps) and "Personal information" editing (3 steps).
//   1. Personal details  : photo (camera / gallery), names, date of birth, gender, @username
//   2. Contact & address : phone, email, state, city, street address
//   3. Identity (KYC)    : BVN, NIN (optional), occupation
//   4. Secure your account: 4-digit transaction PIN + terms   (setup only)
//
// Progress is saved as a draft after every step, and the finished profile is
// saved on the device. Returns `true` to the previous screen when finished.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/app_colors.dart';
import '../../core/app_text.dart';
import 'profile_store.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _reservedUsernames = {
  'admin', 'zellify', 'support', 'help', 'official', 'root', 'staff',
};

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key, this.editing = false});

  /// true = opened from Profile > Personal information (no PIN step).
  final bool editing;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final ProfileStore _store = ProfileStore.instance;
  final ImagePicker _picker = ImagePicker();
  final ScrollController _scroll = ScrollController();
  final List<GlobalKey<FormState>> _keys =
      List.generate(4, (_) => GlobalKey<FormState>());

  late final bool _isEdit = widget.editing && _store.isComplete;
  int get _steps => _isEdit ? 3 : 4;
  int _step = 0;

  final _first = TextEditingController();
  final _middle = TextEditingController();
  final _last = TextEditingController();
  final _dob = TextEditingController();
  final _gender = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _state = TextEditingController();
  final _city = TextEditingController();
  final _street = TextEditingController();
  final _bvn = TextEditingController();
  final _nin = TextEditingController();
  final _occupation = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();

  DateTime? _dobValue;
  String? _avatarB64;
  Uint8List? _avatarBytes;
  bool _photoError = false;
  bool _usernameTouched = false;
  bool _terms = false;
  bool _termsError = false;
  bool _saving = false;
  bool _obscurePin = true;

  static const _titles = [
    'Personal details',
    'Contact & address',
    'Identity',
    'Secure your account',
  ];
  static const _subtitles = [
    'Tell us who you are. Use your name exactly as it appears on your ID.',
    'How can we reach you, and where do you live?',
    'Required by law to keep your money safe.',
    'Create a 4-digit PIN to approve every payment.',
  ];

  @override
  void initState() {
    super.initState();
    final p = _store.profile ?? _store.draft;
    _first.text = (p != null && p.firstName.isNotEmpty)
        ? p.firstName
        : (p == null ? kDefaultFirstName : '');
    if (p != null) {
      _middle.text = p.middleName;
      _last.text = p.lastName;
      _username.text = p.username;
      _usernameTouched = p.username.isNotEmpty;
      _gender.text = p.gender;
      _dobValue = p.dob;
      if (p.dob != null) _dob.text = _fmtDate(p.dob!);
      _phone.text = p.phone;
      _email.text = p.email;
      _state.text = p.state;
      _city.text = p.city;
      _street.text = p.street;
      _bvn.text = p.bvn;
      _nin.text = p.nin;
      _occupation.text = p.occupation;
      _avatarB64 = p.avatarB64;
      _avatarBytes = p.avatarBytes;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _first, _middle, _last, _dob, _gender, _username, _phone, _email,
      _state, _city, _street, _bvn, _nin, _occupation, _pin, _pin2,
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // ───────────────────────────── helpers ─────────────────────────────
  String _fmtDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  UserProfile _collect() => UserProfile(
        firstName: _first.text.trim(),
        middleName: _middle.text.trim(),
        lastName: _last.text.trim(),
        username: _username.text.trim().toLowerCase(),
        gender: _gender.text,
        dob: _dobValue,
        phone: normalizePhone(_phone.text),
        email: _email.text.trim().toLowerCase(),
        state: _state.text,
        city: _city.text.trim(),
        street: _street.text.trim(),
        bvn: _bvn.text.trim(),
        nin: _nin.text.trim(),
        occupation: _occupation.text,
        avatarB64: _avatarB64,
      );

  void _suggestUsername() {
    if (_usernameTouched) return;
    final a = _first.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final b = _last.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    _username.text = [a, b].where((s) => s.isNotEmpty).join('.');
  }

  // ───────────────────────────── photo ─────────────────────────────
  Future<void> _pickPhoto() async {
    FocusScope.of(context).unfocus();
    final choice = await showModalBottomSheet<String>(
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
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9DEDB),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('Profile photo',
                  style: AppText.style(16, FontWeight.w800, AppColors.ink)),
              const SizedBox(height: 8),
              _SheetOption(
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
                onTap: () => Navigator.pop(ctx, 'camera'),
              ),
              _SheetOption(
                icon: Icons.photo_library_outlined,
                label: 'Choose from gallery',
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (_avatarBytes != null)
                _SheetOption(
                  icon: Icons.delete_outline_rounded,
                  label: 'Remove photo',
                  danger: true,
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'remove') {
      setState(() {
        _avatarB64 = null;
        _avatarBytes = null;
      });
      return;
    }

    try {
      final file = await _picker.pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 720,
        maxHeight: 720,
        imageQuality: 80,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _avatarBytes = bytes;
        _avatarB64 = base64Encode(bytes);
        _photoError = false;
      });
    } catch (_) {
      if (!mounted) return;
      _toast(choice == 'camera'
          ? 'Could not open the camera. Check camera permission and try again.'
          : 'Could not open your gallery. Check photo permission and try again.');
    }
  }

  // ───────────────────────────── pickers ─────────────────────────────
  Future<void> _pickDob() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final latest = DateTime(now.year - 18, now.month, now.day);
    final initial = _dobValue ?? DateTime(now.year - 25, 6, 15);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(latest) ? latest : initial,
      firstDate: DateTime(1900),
      lastDate: latest,
      helpText: 'Date of birth',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.greenDark,
            onPrimary: AppColors.white,
            onSurface: AppColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _dobValue = picked;
      _dob.text = _fmtDate(picked);
    });
  }

  Future<void> _pickOption(
    TextEditingController target,
    String title,
    List<String> options,
  ) async {
    FocusScope.of(context).unfocus();
    final height = MediaQuery.of(context).size.height;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: height * 0.7),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD9DEDB),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(title,
                    style: AppText.style(16, FontWeight.w800, AppColors.ink)),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final o in options)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(o,
                              style: AppText.style(
                                  14,
                                  o == target.text
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  AppColors.ink)),
                          trailing: o == target.text
                              ? Icon(Icons.check_circle,
                                  size: 20, color: AppColors.green)
                              : null,
                          onTap: () => Navigator.pop(ctx, o),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null) setState(() => target.text = picked);
  }

  // ───────────────────────────── navigation ─────────────────────────────
  Future<void> _next() async {
    FocusScope.of(context).unfocus();

    final formOk = _keys[_step].currentState?.validate() ?? false;
    var extraOk = true;
    if (_step == 0 && _avatarBytes == null) {
      setState(() => _photoError = true);
      extraOk = false;
    }
    final isLast = _step == _steps - 1;
    if (isLast && !_isEdit && !_terms) {
      setState(() => _termsError = true);
      extraOk = false;
    }
    if (!formOk || !extraOk) return;

    if (!isLast) {
      await _store.saveDraft(_collect()); // never lose progress
      if (!mounted) return;
      setState(() => _step++);
      if (_scroll.hasClients) _scroll.jumpTo(0);
      return;
    }

    setState(() => _saving = true);
    try {
      await _store.saveProfile(_collect(), newPin: _isEdit ? null : _pin.text);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save your profile. Please try again.');
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (!_isEdit) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: AppColors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.greenDark,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 34, color: AppColors.white),
                ),
                const SizedBox(height: 18),
                Text('Profile set up!',
                    style: AppText.style(18, FontWeight.w800, AppColors.ink)),
                const SizedBox(height: 8),
                Text(
                  'You can now send money and make payments with your transaction PIN.',
                  textAlign: TextAlign.center,
                  style: AppText.style(12, FontWeight.w500, AppColors.textMuted,
                      height: 1.5),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.greenDark,
                      foregroundColor: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text('Continue',
                        style:
                            AppText.style(14, FontWeight.w700, AppColors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      _toast('Profile updated');
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ───────────────────────────── UI ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isLast = _step == _steps - 1;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark
          .copyWith(statusBarColor: Colors.transparent),
      child: PopScope(
        canPop: _step == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _step > 0) _back();
        },
        child: Scaffold(
          backgroundColor: AppColors.pageBg,
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                    child: Row(
                      children: [
                        _SquareButton(icon: Icons.arrow_back, onTap: _back),
                        Expanded(
                          child: Center(
                            child: Text(
                              _isEdit ? 'Personal information' : 'Set up profile',
                              style: AppText.style(
                                  17, FontWeight.w700, AppColors.ink),
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Row(
                      children: [
                        for (var i = 0; i < _steps; i++) ...[
                          if (i > 0) const SizedBox(width: 6),
                          Expanded(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 4,
                              decoration: BoxDecoration(
                                color: i <= _step
                                    ? AppColors.greenDark
                                    : const Color(0xFFE1E7E3),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Step ${_step + 1} of $_steps',
                              style: AppText.style(
                                  11, FontWeight.w700, AppColors.green)),
                          const SizedBox(height: 6),
                          Text(_titles[_step],
                              style: AppText.style(
                                  22, FontWeight.w800, AppColors.ink)),
                          const SizedBox(height: 6),
                          Text(_subtitles[_step],
                              style: AppText.style(
                                  12, FontWeight.w500, AppColors.textMuted,
                                  height: 1.5)),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0F1B1F2E),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: KeyedSubtree(
                                key: ValueKey(_step),
                                child: Form(
                                  key: _keys[_step],
                                  child: _stepBody(),
                                ),
                              ),
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
                        onPressed: _saving ? null : _next,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.greenDark,
                          disabledBackgroundColor: const Color(0xFF92A4A0),
                          foregroundColor: AppColors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppColors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    isLast
                                        ? (_isEdit
                                            ? 'Save changes'
                                            : 'Finish setup')
                                        : 'Continue',
                                    style: AppText.style(
                                        16, FontWeight.w700, AppColors.white),
                                  ),
                                  if (!isLast) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.arrow_forward, size: 18),
                                  ],
                                ],
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _personalStep();
      case 1:
        return _contactStep();
      case 2:
        return _identityStep();
      default:
        return _securityStep();
    }
  }

  // ── Step 1 ──
  Widget _personalStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.tileMint,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _photoError
                              ? const Color(0xFFD64545)
                              : Colors.transparent,
                          width: 1.6,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: _avatarBytes != null
                            ? Image.memory(_avatarBytes!,
                                width: 96, height: 96, fit: BoxFit.cover)
                            : Icon(Icons.person_outline_rounded,
                                size: 40, color: AppColors.iconMint),
                      ),
                    ),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.greenDark,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.white, width: 3),
                        ),
                        child: const Icon(Icons.photo_camera_rounded,
                            size: 15, color: AppColors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _photoError
                    ? 'A profile photo is required'
                    : 'Add a clear photo of your face',
                style: AppText.style(
                  11.5,
                  FontWeight.w600,
                  _photoError ? const Color(0xFFD64545) : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _Labeled(
          'First name',
          TextFormField(
            controller: _first,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: _fieldStyle,
            decoration: _dec('e.g. Steadfastness'),
            onChanged: (_) => _suggestUsername(),
            validator: _nameValidator,
          ),
        ),
        _Labeled(
          'Middle name (optional)',
          TextFormField(
            controller: _middle,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: _fieldStyle,
            decoration: _dec('Middle name'),
          ),
        ),
        _Labeled(
          'Last name',
          TextFormField(
            controller: _last,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: _fieldStyle,
            decoration: _dec('Last name'),
            onChanged: (_) => _suggestUsername(),
            validator: _nameValidator,
          ),
        ),
        _Labeled(
          'Date of birth',
          TextFormField(
            controller: _dob,
            readOnly: true,
            onTap: _pickDob,
            style: _fieldStyle,
            decoration: _dec('Select date',
                suffix: Icon(Icons.calendar_today_outlined,
                    size: 18, color: AppColors.textMuted)),
            validator: (v) => (v ?? '').isEmpty
                ? 'Select your date of birth (18+ only)'
                : null,
          ),
        ),
        _Labeled(
          'Gender',
          TextFormField(
            controller: _gender,
            readOnly: true,
            onTap: () => _pickOption(_gender, 'Gender', kGenders),
            style: _fieldStyle,
            decoration: _dec('Select gender',
                suffix: Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted)),
            validator: (v) => (v ?? '').isEmpty ? 'Select your gender' : null,
          ),
        ),
        _Labeled(
          'Zellify tag (username)',
          TextFormField(
            controller: _username,
            textInputAction: TextInputAction.done,
            autocorrect: false,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
              LengthLimitingTextInputFormatter(20),
            ],
            style: _fieldStyle,
            decoration: _dec('yourname', prefixText: '@'),
            onChanged: (_) => _usernameTouched = true,
            validator: (v) {
              final u = (v ?? '').trim().toLowerCase();
              if (u.length < 3) return 'At least 3 characters';
              if (u.startsWith('.') || u.startsWith('_')) {
                return 'Start with a letter or number';
              }
              if (_reservedUsernames.contains(u)) {
                return 'That tag is not available';
              }
              return null;
            },
          ),
          note: 'People can send you money with this tag.',
        ),
      ],
    );
  }

  // ── Step 2 ──
  Widget _contactStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Labeled(
          'Phone number',
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9 +]')),
              LengthLimitingTextInputFormatter(17),
            ],
            style: _fieldStyle,
            decoration: _dec('701 234 5678', prefixText: '+234  '),
            validator: (v) {
              final n = normalizePhone(v ?? '');
              if (n.isEmpty) return 'Enter your phone number';
              if (!RegExp(r'^[789][01]\d{8}$').hasMatch(n)) {
                return 'Enter a valid Nigerian mobile number';
              }
              return null;
            },
          ),
          note: "We'll verify this number with a code once your backend is connected.",
        ),
        _Labeled(
          'Email address',
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            style: _fieldStyle,
            decoration: _dec('you@example.com'),
            validator: (v) {
              final e = (v ?? '').trim();
              if (e.isEmpty) return 'Enter your email address';
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(e)) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
        ),
        _Labeled(
          'State',
          TextFormField(
            controller: _state,
            readOnly: true,
            onTap: () => _pickOption(_state, 'State', kNigerianStates),
            style: _fieldStyle,
            decoration: _dec('Select state',
                suffix: Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted)),
            validator: (v) => (v ?? '').isEmpty ? 'Select your state' : null,
          ),
        ),
        _Labeled(
          'City / LGA',
          TextFormField(
            controller: _city,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            style: _fieldStyle,
            decoration: _dec('e.g. Ikeja'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Enter your city or LGA' : null,
          ),
        ),
        _Labeled(
          'Street address',
          TextFormField(
            controller: _street,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            style: _fieldStyle,
            decoration: _dec('House number and street'),
            validator: (v) => (v ?? '').trim().length < 5
                ? 'Enter your full street address'
                : null,
          ),
        ),
      ],
    );
  }

  // ── Step 3 ──
  Widget _identityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Labeled(
          'Bank Verification Number (BVN)',
          TextFormField(
            controller: _bvn,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            style: _fieldStyle,
            decoration: _dec('11 digits'),
            validator: (v) => RegExp(r'^\d{11}$').hasMatch((v ?? '').trim())
                ? null
                : 'BVN must be 11 digits',
          ),
          note: 'Dial *565*0# on your registered phone to get it. Your BVN cannot be used to move your money.',
        ),
        _Labeled(
          'National ID number (NIN), optional',
          TextFormField(
            controller: _nin,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(11),
            ],
            style: _fieldStyle,
            decoration: _dec('11 digits'),
            validator: (v) {
              final n = (v ?? '').trim();
              if (n.isEmpty) return null;
              return RegExp(r'^\d{11}$').hasMatch(n)
                  ? null
                  : 'NIN must be 11 digits';
            },
          ),
          note: 'Add your NIN to unlock higher limits (Tier 3).',
        ),
        _Labeled(
          'Occupation',
          TextFormField(
            controller: _occupation,
            readOnly: true,
            onTap: () => _pickOption(_occupation, 'Occupation', kOccupations),
            style: _fieldStyle,
            decoration: _dec('Select occupation',
                suffix: Icon(Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textMuted)),
            validator: (v) =>
                (v ?? '').isEmpty ? 'Select your occupation' : null,
          ),
        ),
      ],
    );
  }

  // ── Step 4 ──
  Widget _securityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Labeled(
          'Transaction PIN',
          TextFormField(
            controller: _pin,
            obscureText: _obscurePin,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            style: _fieldStyle,
            decoration: _dec(
              '4 digits',
              suffix: IconButton(
                icon: Icon(
                  _obscurePin
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                onPressed: () => setState(() => _obscurePin = !_obscurePin),
              ),
            ),
            validator: (v) {
              final p = v ?? '';
              if (p.length != 4) return 'PIN must be 4 digits';
              if (isWeakPin(p)) return 'Choose a less obvious PIN';
              return null;
            },
          ),
          note: 'Avoid 1234, 0000 or your birth year.',
        ),
        _Labeled(
          'Confirm PIN',
          TextFormField(
            controller: _pin2,
            obscureText: _obscurePin,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            style: _fieldStyle,
            decoration: _dec('Re-enter PIN'),
            validator: (v) => v == _pin.text ? null : "PINs don't match",
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() {
            _terms = !_terms;
            _termsError = false;
          }),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: _terms ? AppColors.greenDark : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: _terms
                        ? AppColors.greenDark
                        : (_termsError
                            ? const Color(0xFFD64545)
                            : const Color(0xFFC4CCC8)),
                    width: 1.6,
                  ),
                ),
                child: _terms
                    ? const Icon(Icons.check_rounded,
                        size: 15, color: AppColors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'I confirm my details are correct and I agree to the Terms of Use and Privacy Policy.',
                  style: AppText.style(
                    11.5,
                    FontWeight.w500,
                    _termsError ? const Color(0xFFD64545) : AppColors.textMuted,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.tileMint,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline_rounded,
                  size: 18, color: AppColors.iconMint),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your PIN is stored only as a scrambled hash on this device. Never share it with anyone, including Zellify staff.',
                  style: AppText.style(
                      11, FontWeight.w500, AppColors.textMuted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── shared field bits ──
  TextStyle get _fieldStyle =>
      AppText.style(14, FontWeight.w600, AppColors.ink);

  String? _nameValidator(String? v) {
    final n = (v ?? '').trim();
    if (n.length < 2) return 'Enter at least 2 letters';
    if (!RegExp(r"^[A-Za-z][A-Za-z\-' ]*$").hasMatch(n)) {
      return 'Use letters only';
    }
    return null;
  }

  InputDecoration _dec(String hint, {Widget? suffix, String? prefixText}) {
    OutlineInputBorder border(Color c, [double w = 0]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: w == 0
              ? BorderSide.none
              : BorderSide(color: c, width: w),
        );
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.style(14, FontWeight.w500, AppColors.textMuted),
      prefixIcon: prefixText == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 14, right: 4),
              child: Center(
                widthFactor: 1,
                child: Text(prefixText.trim(),
                    style: AppText.style(14, FontWeight.w700, AppColors.ink)),
              ),
            ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      suffixIcon: suffix,
      counterText: '',
      filled: true,
      fillColor: AppColors.pageBg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(AppColors.greenDark, 1.2),
      errorBorder: border(const Color(0xFFD64545), 1.2),
      focusedErrorBorder: border(const Color(0xFFD64545), 1.2),
      errorStyle:
          AppText.style(11, FontWeight.w500, const Color(0xFFD64545)),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.field, {this.note});
  final String label;
  final Widget field;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.style(11, FontWeight.w700, AppColors.textMuted)),
          const SizedBox(height: 8),
          field,
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!,
                style: AppText.style(
                    10.5, FontWeight.w500, AppColors.textMuted, height: 1.45)),
          ],
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
      color: const Color(0xFFEBEFEC),
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

class _SheetOption extends StatelessWidget {
  const _SheetOption({
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
    final color = danger ? const Color(0xFFD64545) : AppColors.ink;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 14),
            Text(label, style: AppText.style(14, FontWeight.w600, color)),
          ],
        ),
      ),
    );
  }
}
