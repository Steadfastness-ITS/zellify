// lib/features/exchange/exchange_store.dart
//
// Data behind the Exchange screen:
//   - Currency      NGN, USD, GBP, EUR
//   - FxRates       SIMULATED live rates + 90 days of history (replace with a real FX API)
//   - ExchangeStore multi-currency wallets, exchange history, rate alerts and
//                   auto-convert plans, all saved on the device
//
// WHERE TO PLUG IN YOUR BACKEND LATER
//   - Rates:     replace FxRates._tick() / _buildHistory() with your provider
//   - Execute:   ExchangeStore.execute() = call your "convert" endpoint here
//   - Alerts and plans should run on the server (push notifications, schedulers)

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../profile/profile_store.dart';

// ─────────────────────────────── Settings (mock) ─────────────────────────────
/// Zellify fee: 0.5% of the amount you send. The rate itself is the real
/// mid-market rate (no hidden spread).
const double kFeeRate = 0.005;

/// Assumed margin of a typical bank / BDC (used only for the "you save" badge).
const double kBankMargin = 0.035;

/// Smallest exchange, in naira (or the naira equivalent).
const double kMinNgn = 1000;

/// How long a quoted rate is locked.
const int kQuoteSeconds = 60;

// ─────────────────────────────── Currency & format ───────────────────────────
enum Currency {
  ngn('NGN', '₦', 'Nigerian naira'),
  usd('USD', '\$', 'US dollar'),
  gbp('GBP', '£', 'British pound'),
  eur('EUR', '€', 'Euro');

  const Currency(this.code, this.symbol, this.label);
  final String code;
  final String symbol;
  final String label;

  static const List<Currency> foreign = [usd, gbp, eur];
}

String groupDigits(String digits) => digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );

/// money(Currency.usd, 1234.5) -> "$1,234.50"
String money(Currency c, double v, {int decimals = 2}) {
  final parts = v.abs().toStringAsFixed(decimals).split('.');
  final frac = parts.length > 1 ? '.${parts[1]}' : '';
  return '${v < 0 ? '-' : ''}${c.symbol}${groupDigits(parts[0])}$frac';
}

double r2(double v) => (v * 100).round() / 100;

// ───────────────────────────────── Live rates ────────────────────────────────
/// SIMULATED rates. mid(c) = naira for 1 unit of foreign currency.
class FxRates extends ChangeNotifier {
  FxRates._() {
    for (final c in Currency.foreign) {
      _history[c] = _buildHistory(c);
      _mid[c] = _history[c]!.last;
      _prev[c] = _mid[c]!;
    }
  }
  static final FxRates instance = FxRates._();

  static const Map<Currency, double> _base = {
    Currency.usd: 1521.40,
    Currency.gbp: 2034.75,
    Currency.eur: 1768.20,
  };

  final Map<Currency, double> _mid = {};
  final Map<Currency, double> _prev = {};
  final Map<Currency, List<double>> _history = {};
  final Random _rng = Random();
  Timer? _timer;
  int _users = 0;

  double mid(Currency c) => _mid[c] ?? 1;

  /// Positive if the last tick went up, negative if down.
  double lastMove(Currency c) => (_mid[c] ?? 0) - (_prev[c] ?? 0);

  /// Last [days] daily points (oldest first). The last point is today's rate.
  List<double> history(Currency c, int days) {
    final h = _history[c] ?? const <double>[];
    final slice = h.length <= days ? h : h.sublist(h.length - days);
    return [...slice.take(max(0, slice.length - 1)), mid(c)];
  }

  /// Start ticking while a screen is looking at the rates.
  void start() {
    if (_users++ == 0) {
      _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
    }
  }

  void stop() {
    _users = max(0, _users - 1);
    if (_users == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _tick() {
    for (final c in Currency.foreign) {
      final cur = _mid[c]!;
      _prev[c] = cur;
      final pull = (_base[c]! / cur - 1) * 0.05; // drifts back toward the base
      final noise = (_rng.nextDouble() - 0.5) * 0.0016;
      _mid[c] = r2(cur * (1 + pull + noise));
    }
    notifyListeners();
  }

  List<double> _buildHistory(Currency c) {
    final rng = Random(c.index * 7919 + 13);
    final base = _base[c]!;
    var v = base * (1 + (rng.nextDouble() - 0.5) * 0.04);
    final raw = <double>[];
    for (var i = 0; i < 90; i++) {
      v *= 1 + (rng.nextDouble() - 0.5) * 0.012 + (base / v - 1) * 0.03;
      raw.add(v);
    }
    final scale = base / raw.last; // make today's point equal the base rate
    return [for (final x in raw) r2(x * scale)];
  }
}

// ──────────────────────────────────── Models ─────────────────────────────────
class FxQuote {
  FxQuote({
    required this.foreign,
    required this.buying,
    required this.send,
    required this.get,
    required this.fee,
    required this.rate,
  }) : createdAt = DateTime.now();

  final Currency foreign;
  final bool buying; // true = NGN -> foreign, false = foreign -> NGN
  final double send;
  final double get;
  final double fee; // in the currency you send
  final double rate; // naira per 1 foreign
  final DateTime createdAt;

  Currency get fromCur => buying ? Currency.ngn : foreign;
  Currency get toCur => buying ? foreign : Currency.ngn;

  /// Naira value of the exchange (used for limits).
  double get ngnValue => buying ? send : get + (fee * rate);
}

class ExchangeRecord {
  ExchangeRecord({
    required this.id,
    required this.time,
    required this.from,
    required this.to,
    required this.fromAmount,
    required this.toAmount,
    required this.rate,
    required this.fee,
    required this.purpose,
    required this.auto,
  });

  final String id;
  final DateTime time;
  final Currency from;
  final Currency to;
  final double fromAmount;
  final double toAmount;
  final double rate;
  final double fee;
  final String purpose;
  final bool auto;

  double get ngnValue => from == Currency.ngn ? fromAmount : toAmount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'from': from.name,
        'to': to.name,
        'fromAmount': fromAmount,
        'toAmount': toAmount,
        'rate': rate,
        'fee': fee,
        'purpose': purpose,
        'auto': auto,
      };

  factory ExchangeRecord.fromJson(Map<String, dynamic> j) => ExchangeRecord(
        id: j['id'] as String,
        time: DateTime.parse(j['time'] as String),
        from: Currency.values.byName(j['from'] as String),
        to: Currency.values.byName(j['to'] as String),
        fromAmount: (j['fromAmount'] as num).toDouble(),
        toAmount: (j['toAmount'] as num).toDouble(),
        rate: (j['rate'] as num).toDouble(),
        fee: (j['fee'] as num).toDouble(),
        purpose: (j['purpose'] as String?) ?? 'Savings',
        auto: (j['auto'] as bool?) ?? false,
      );
}

/// Money added to the naira wallet (bank transfer, card...).
class TopUpRecord {
  TopUpRecord({
    required this.id,
    required this.time,
    required this.amount,
    required this.fee,
    required this.method,
  });

  final String id;
  final DateTime time;
  final double amount; // credited to the wallet
  final double fee; // paid on top (card fee), 0 for bank transfers
  final String method; // 'Card' or 'Bank transfer'

  Map<String, dynamic> toJson() => {
        'id': id,
        'time': time.toIso8601String(),
        'amount': amount,
        'fee': fee,
        'method': method,
      };

  factory TopUpRecord.fromJson(Map<String, dynamic> j) => TopUpRecord(
        id: j['id'] as String,
        time: DateTime.parse(j['time'] as String),
        amount: (j['amount'] as num).toDouble(),
        fee: (j['fee'] as num).toDouble(),
        method: (j['method'] as String?) ?? 'Bank transfer',
      );
}

class RateAlert {
  RateAlert({
    required this.id,
    required this.currency,
    required this.above,
    required this.target,
    this.triggered = false,
  });

  final String id;
  final Currency currency;
  final bool above; // true: notify when rate rises to target
  final double target;
  bool triggered;

  Map<String, dynamic> toJson() => {
        'id': id,
        'currency': currency.name,
        'above': above,
        'target': target,
        'triggered': triggered,
      };

  factory RateAlert.fromJson(Map<String, dynamic> j) => RateAlert(
        id: j['id'] as String,
        currency: Currency.values.byName(j['currency'] as String),
        above: j['above'] as bool,
        target: (j['target'] as num).toDouble(),
        triggered: (j['triggered'] as bool?) ?? false,
      );
}

class AutoPlan {
  AutoPlan({
    required this.id,
    required this.currency,
    required this.amountNgn,
    required this.weekly,
    required this.next,
    this.active = true,
  });

  final String id;
  final Currency currency;
  final double amountNgn;
  final bool weekly; // false = monthly
  DateTime next;
  bool active;

  Map<String, dynamic> toJson() => {
        'id': id,
        'currency': currency.name,
        'amountNgn': amountNgn,
        'weekly': weekly,
        'next': next.toIso8601String(),
        'active': active,
      };

  factory AutoPlan.fromJson(Map<String, dynamic> j) => AutoPlan(
        id: j['id'] as String,
        currency: Currency.values.byName(j['currency'] as String),
        amountNgn: (j['amountNgn'] as num).toDouble(),
        weekly: j['weekly'] as bool,
        next: DateTime.parse(j['next'] as String),
        active: (j['active'] as bool?) ?? true,
      );
}

// ──────────────────────────────────── Store ──────────────────────────────────
class ExchangeStore extends ChangeNotifier {
  ExchangeStore._();
  static final ExchangeStore instance = ExchangeStore._();

  static const _kKey = 'zellify_wallet_v1';
  static const double _startingNgn = 842650.20; // mock opening balance

  final Map<Currency, double> _bal = {
    Currency.ngn: _startingNgn,
    Currency.usd: 0,
    Currency.gbp: 0,
    Currency.eur: 0,
  };
  List<ExchangeRecord> history = [];
  List<RateAlert> alerts = [];
  List<AutoPlan> plans = [];
  List<TopUpRecord> topups = [];
  bool _loaded = false;
  Future<void>? _loading;

  bool get loaded => _loaded;
  double balance(Currency c) => _bal[c] ?? 0;
  double get ngn => balance(Currency.ngn);
  String get ngnText => money(Currency.ngn, ngn);

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        final b = (j['bal'] as Map<String, dynamic>? ?? {});
        for (final c in Currency.values) {
          if (b[c.name] != null) _bal[c] = (b[c.name] as num).toDouble();
        }
        history = [
          for (final x in (j['history'] as List? ?? []))
            ExchangeRecord.fromJson(x as Map<String, dynamic>),
        ];
        alerts = [
          for (final x in (j['alerts'] as List? ?? []))
            RateAlert.fromJson(x as Map<String, dynamic>),
        ];
        plans = [
          for (final x in (j['plans'] as List? ?? []))
            AutoPlan.fromJson(x as Map<String, dynamic>),
        ];
        topups = [
          for (final x in (j['topups'] as List? ?? []))
            TopUpRecord.fromJson(x as Map<String, dynamic>),
        ];
      } catch (_) {
        // corrupted data: start fresh
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kKey,
      jsonEncode({
        'bal': {for (final c in Currency.values) c.name: _bal[c]},
        'history': [for (final h in history.take(60)) h.toJson()],
        'alerts': [for (final a in alerts) a.toJson()],
        'plans': [for (final p in plans) p.toJson()],
        'topups': [for (final t in topups.take(40)) t.toJson()],
      }),
    );
    notifyListeners();
  }

  /// Wipes wallets, history, alerts and plans (testing).
  Future<void> reset() async {
    for (final c in Currency.values) {
      _bal[c] = c == Currency.ngn ? _startingNgn : 0;
    }
    history = [];
    alerts = [];
    plans = [];
    topups = [];
    await _save();
  }

  // ── quotes & execution ──
  FxQuote quote({
    required Currency foreign,
    required bool buying,
    required double send,
  }) {
    final rate = FxRates.instance.mid(foreign);
    final fee = r2(send * kFeeRate);
    final net = send - fee;
    final get = r2(buying ? net / rate : net * rate);
    return FxQuote(
      foreign: foreign,
      buying: buying,
      send: send,
      get: get,
      fee: fee,
      rate: rate,
    );
  }

  /// Naira already exchanged today (for the daily limit).
  double get usedTodayNgn {
    final now = DateTime.now();
    var sum = 0.0;
    for (final r in history) {
      if (r.time.year == now.year &&
          r.time.month == now.month &&
          r.time.day == now.day) {
        sum += r.ngnValue;
      }
    }
    return sum;
  }

  /// Moves the money between wallets. Returns null if the balance is too low.
  Future<ExchangeRecord?> execute(
    FxQuote q, {
    String purpose = 'Savings',
    bool auto = false,
  }) async {
    if (balance(q.fromCur) + 0.005 < q.send) return null;
    _bal[q.fromCur] = r2(balance(q.fromCur) - q.send);
    _bal[q.toCur] = r2(balance(q.toCur) + q.get);
    final rec = ExchangeRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      time: DateTime.now(),
      from: q.fromCur,
      to: q.toCur,
      fromAmount: q.send,
      toAmount: q.get,
      rate: q.rate,
      fee: q.fee,
      purpose: purpose,
      auto: auto,
    );
    history = [rec, ...history];
    await _save();
    return rec;
  }

  /// Adds money to the naira wallet (Add money screen).
  /// MOCK: a real backend credits the wallet when the transfer / card payment
  /// is confirmed by your bank or payment gateway.
  Future<void> creditNgn(
    double amount, {
    required String method,
    double fee = 0,
  }) async {
    _bal[Currency.ngn] = r2(ngn + amount);
    topups = [
      TopUpRecord(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        time: DateTime.now(),
        amount: amount,
        fee: fee,
        method: method,
      ),
      ...topups,
    ];
    await _save();
  }

  /// Used by the Send screen after a transfer.
  Future<void> debitNgn(double amount) async {
    _bal[Currency.ngn] = r2(max(0, ngn - amount));
    await _save();
  }

  // ── rate alerts ──
  Future<void> addAlert(RateAlert a) async {
    alerts = [a, ...alerts];
    await _save();
  }

  Future<void> removeAlert(String id) async {
    alerts = alerts.where((a) => a.id != id).toList();
    await _save();
  }

  /// Marks alerts whose target was reached and returns them.
  Future<List<RateAlert>> checkAlerts() async {
    final hit = <RateAlert>[];
    for (final a in alerts) {
      if (a.triggered) continue;
      final r = FxRates.instance.mid(a.currency);
      if ((a.above && r >= a.target) || (!a.above && r <= a.target)) {
        a.triggered = true;
        hit.add(a);
      }
    }
    if (hit.isNotEmpty) await _save();
    return hit;
  }

  // ── auto-convert plans ──
  Future<void> addPlan(AutoPlan p) async {
    plans = [p, ...plans];
    await _save();
  }

  Future<void> removePlan(String id) async {
    plans = plans.where((p) => p.id != id).toList();
    await _save();
  }

  Future<void> setPlanActive(AutoPlan p, bool active) async {
    p.active = active;
    await _save();
  }

  /// Runs plans that are due. MOCK: only runs when the Exchange screen opens
  /// (a real backend would run these on a schedule).
  Future<List<ExchangeRecord>> runDuePlans() async {
    final done = <ExchangeRecord>[];
    if (!ProfileStore.instance.isComplete) return done;
    final now = DateTime.now();
    for (final p in plans) {
      if (!p.active || p.next.isAfter(now)) continue;
      final q = quote(foreign: p.currency, buying: true, send: p.amountNgn);
      final rec = await execute(q, purpose: 'Auto-save', auto: true);
      if (rec == null) continue; // not enough naira: try again next time
      done.add(rec);
      p.next = p.weekly
          ? p.next.add(const Duration(days: 7))
          : DateTime(p.next.year, p.next.month + 1, p.next.day);
      if (p.next.isBefore(now)) p.next = now.add(Duration(days: p.weekly ? 7 : 30));
    }
    if (done.isNotEmpty) await _save();
    return done;
  }
}
