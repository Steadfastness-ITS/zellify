// lib/features/profile/profile_store.dart
//
// Everything about the user's profile lives here: the data model, saving it on
// the device, and the transaction PIN.
//
// Saved on the device with shared_preferences (so it stays after you close or
// refresh the app):
//   - the finished profile
//   - a draft while the user is still filling in the setup steps
//   - the transaction PIN, stored only as a salted SHA-256 hash (never plain)
//
// BACKEND NOTE: when your backend is ready, call your API from saveProfile()
// and verifyPin() and keep this class as the local cache. A PIN check that
// only happens on the phone is NOT enough security for real money.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shown on Home / Profile until the user types their own name in setup.
const String kDefaultFirstName = 'Steadfastness';

const List<String> kNigerianStates = [
  'Abia', 'Adamawa', 'Akwa Ibom', 'Anambra', 'Bauchi', 'Bayelsa', 'Benue',
  'Borno', 'Cross River', 'Delta', 'Ebonyi', 'Edo', 'Ekiti', 'Enugu',
  'FCT - Abuja', 'Gombe', 'Imo', 'Jigawa', 'Kaduna', 'Kano', 'Katsina',
  'Kebbi', 'Kogi', 'Kwara', 'Lagos', 'Nasarawa', 'Niger', 'Ogun', 'Ondo',
  'Osun', 'Oyo', 'Plateau', 'Rivers', 'Sokoto', 'Taraba', 'Yobe', 'Zamfara',
];

const List<String> kOccupations = [
  'Employed',
  'Self-employed',
  'Business owner',
  'Freelancer',
  'Civil servant',
  'Student',
  'Retired',
  'Unemployed',
];

const List<String> kGenders = ['Male', 'Female', 'Prefer not to say'];

/// Turns "0701 234 5678", "+234 701 234 5678" or "7012345678" into "7012345678".
String normalizePhone(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('234')) d = d.substring(3);
  if (d.startsWith('0')) d = d.substring(1);
  return d;
}

/// True for PINs like 0000, 1111, 1234, 4321.
bool isWeakPin(String pin) {
  if (RegExp(r'^(\d)\1{3}$').hasMatch(pin)) return true;
  const weak = ['0123', '1234', '2345', '3456', '4567', '5678', '6789',
    '3210', '4321', '5432', '6543', '7654', '8765', '9876'];
  return weak.contains(pin);
}

// ─────────────────────────────────── Model ───────────────────────────────────
class UserProfile {
  UserProfile({
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.username = '',
    this.gender = '',
    this.dob,
    this.phone = '',
    this.email = '',
    this.state = '',
    this.city = '',
    this.street = '',
    this.bvn = '',
    this.nin = '',
    this.occupation = '',
    this.avatarB64,
    this.verified = false,
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String username; // Zellify tag, without the "@"
  final String gender;
  final DateTime? dob;
  final String phone; // 10 digits, no leading 0 (e.g. 7012345678)
  final String email;
  final String state;
  final String city;
  final String street;
  final String bvn; // 11 digits
  final String nin; // 11 digits, optional (unlocks Tier 3)
  final String occupation;
  final String? avatarB64; // profile photo, base64
  final bool verified; // MOCK until a backend does real KYC checks

  Uint8List? _bytes;

  Uint8List? get avatarBytes {
    final b = avatarB64;
    if (b == null || b.isEmpty) return null;
    return _bytes ??= base64Decode(b);
  }

  String get fullName => [firstName, lastName]
      .where((s) => s.trim().isNotEmpty)
      .join(' ')
      .trim();

  String get cardHolder => fullName.toUpperCase();

  String get initials {
    final a = firstName.trim();
    final b = lastName.trim();
    if (a.isNotEmpty && b.isNotEmpty) return '${a[0]}${b[0]}'.toUpperCase();
    if (a.isNotEmpty) return a.substring(0, a.length >= 2 ? 2 : 1).toUpperCase();
    return '?';
  }

  /// "0701 234 5678"
  String get phoneDisplay {
    if (phone.length != 10) return phone;
    return '0${phone.substring(0, 3)} ${phone.substring(3, 6)} ${phone.substring(6)}';
  }

  /// Every required field is filled in correctly.
  bool get hasRequired =>
      firstName.trim().length >= 2 &&
      lastName.trim().length >= 2 &&
      username.length >= 3 &&
      dob != null &&
      gender.isNotEmpty &&
      RegExp(r'^[789][01]\d{8}$').hasMatch(phone) &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email) &&
      state.isNotEmpty &&
      city.trim().isNotEmpty &&
      street.trim().isNotEmpty &&
      RegExp(r'^\d{11}$').hasMatch(bvn) &&
      occupation.isNotEmpty &&
      avatarBytes != null;

  /// 2 = profile with BVN, 3 = NIN added too. 0 = not set up.
  int get tier => !hasRequired ? 0 : (RegExp(r'^\d{11}$').hasMatch(nin) ? 3 : 2);

  /// Daily transfer limit for the tier (example values, set real ones in your backend).
  int get dailyLimit => tier == 3 ? 10000000 : (tier == 2 ? 500000 : 0);

  UserProfile copyWith({
    String? firstName,
    String? middleName,
    String? lastName,
    String? username,
    String? gender,
    DateTime? dob,
    String? phone,
    String? email,
    String? state,
    String? city,
    String? street,
    String? bvn,
    String? nin,
    String? occupation,
    String? avatarB64,
    bool clearAvatar = false,
    bool? verified,
  }) {
    return UserProfile(
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      username: username ?? this.username,
      gender: gender ?? this.gender,
      dob: dob ?? this.dob,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      state: state ?? this.state,
      city: city ?? this.city,
      street: street ?? this.street,
      bvn: bvn ?? this.bvn,
      nin: nin ?? this.nin,
      occupation: occupation ?? this.occupation,
      avatarB64: clearAvatar ? null : (avatarB64 ?? this.avatarB64),
      verified: verified ?? this.verified,
    );
  }

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'username': username,
        'gender': gender,
        'dob': dob == null
            ? null
            : '${dob!.year.toString().padLeft(4, '0')}-${dob!.month.toString().padLeft(2, '0')}-${dob!.day.toString().padLeft(2, '0')}',
        'phone': phone,
        'email': email,
        'state': state,
        'city': city,
        'street': street,
        'bvn': bvn,
        'nin': nin,
        'occupation': occupation,
        'avatar': avatarB64,
        'verified': verified,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    String s(String k) => (j[k] as String?) ?? '';
    return UserProfile(
      firstName: s('firstName'),
      middleName: s('middleName'),
      lastName: s('lastName'),
      username: s('username'),
      gender: s('gender'),
      dob: j['dob'] == null ? null : DateTime.tryParse(j['dob'] as String),
      phone: s('phone'),
      email: s('email'),
      state: s('state'),
      city: s('city'),
      street: s('street'),
      bvn: s('bvn'),
      nin: s('nin'),
      occupation: s('occupation'),
      avatarB64: j['avatar'] as String?,
      verified: (j['verified'] as bool?) ?? false,
    );
  }
}

// ─────────────────────────────────── Store ───────────────────────────────────
class ProfileStore extends ChangeNotifier {
  ProfileStore._();
  static final ProfileStore instance = ProfileStore._();

  static const _kProfile = 'zellify_profile_v1';
  static const _kDraft = 'zellify_profile_draft_v1';
  static const _kPinHash = 'zellify_pin_hash_v1';
  static const _kPinSalt = 'zellify_pin_salt_v1';

  UserProfile? _profile;
  UserProfile? _draft;
  String? _pinHash;
  String? _pinSalt;
  bool _loaded = false;
  Future<void>? _loading;

  bool get loaded => _loaded;
  UserProfile? get profile => _profile;
  UserProfile? get draft => _draft;
  bool get hasPin => _pinHash != null && _pinSalt != null;

  /// Profile finished AND a PIN created: payments are allowed.
  bool get isComplete =>
      _profile != null && _profile!.hasRequired && hasPin;

  /// First name for greetings.
  String get displayName {
    final n = _profile?.firstName.trim() ?? '';
    return n.isNotEmpty ? n : kDefaultFirstName;
  }

  String get fullDisplayName {
    final n = _profile?.fullName ?? '';
    return n.isNotEmpty ? n : kDefaultFirstName;
  }

  String get initials {
    final p = _profile;
    if (p != null && p.firstName.trim().isNotEmpty) return p.initials;
    return kDefaultFirstName.substring(0, 2).toUpperCase();
  }

  /// Name printed on the card.
  String get cardHolder {
    final n = _profile?.cardHolder ?? '';
    return n.isNotEmpty ? n : kDefaultFirstName.toUpperCase();
  }

  /// Safe to call many times; it only reads the device once.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _profile = _decode(prefs.getString(_kProfile));
    _draft = _decode(prefs.getString(_kDraft));
    _pinHash = prefs.getString(_kPinHash);
    _pinSalt = prefs.getString(_kPinSalt);
    _loaded = true;
    notifyListeners();
  }

  UserProfile? _decode(String? raw) {
    if (raw == null) return null;
    try {
      return UserProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Keeps half-finished setup so the user never has to start again.
  Future<void> saveDraft(UserProfile draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDraft, jsonEncode(draft.toJson()));
    _draft = draft;
    notifyListeners();
  }

  /// Saves the finished profile. Pass [newPin] the first time (setup).
  Future<void> saveProfile(UserProfile profile, {String? newPin}) async {
    final prefs = await SharedPreferences.getInstance();
    // MOCK: marks the profile verified. Replace with the real KYC result.
    final saved = profile.copyWith(verified: true);
    await prefs.setString(_kProfile, jsonEncode(saved.toJson()));
    await prefs.remove(_kDraft);
    _draft = null;
    if (newPin != null) await _writePin(prefs, newPin);
    _profile = saved;
    notifyListeners();
  }

  /// Sets or changes the PIN. Ask for the old PIN (verifyPin) before calling this.
  Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await _writePin(prefs, pin);
    notifyListeners();
  }

  bool verifyPin(String pin) {
    if (!hasPin) return false;
    return _hash(_pinSalt!, pin) == _pinHash;
  }

  /// Wipes the profile, draft and PIN from this device (for testing).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kProfile);
    await prefs.remove(_kDraft);
    await prefs.remove(_kPinHash);
    await prefs.remove(_kPinSalt);
    _profile = null;
    _draft = null;
    _pinHash = null;
    _pinSalt = null;
    notifyListeners();
  }

  static String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> _writePin(SharedPreferences prefs, String pin) async {
    final rnd = Random.secure();
    final salt =
        base64UrlEncode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    _pinSalt = salt;
    _pinHash = _hash(salt, pin);
    await prefs.setString(_kPinSalt, salt);
    await prefs.setString(_kPinHash, _pinHash!);
  }
}
