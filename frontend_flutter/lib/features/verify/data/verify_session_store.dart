import 'dart:convert';

import '../../../core/storage/secure_store.dart';

class VerifyLogEntry {
  final DateTime timestamp;
  final double score;
  final bool ok;
  final String reason;
  final String? userId;
  final String? device;
  final int retries;

  VerifyLogEntry({
    required this.timestamp,
    required this.score,
    required this.ok,
    required this.reason,
    required this.retries,
    this.userId,
    this.device,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.millisecondsSinceEpoch,
        'score': score,
        'ok': ok,
        'reason': reason,
        'userId': userId,
        'device': device,
        'retries': retries,
      };

  static VerifyLogEntry fromJson(Map<String, dynamic> json) {
    return VerifyLogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int? ?? 0),
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      ok: json['ok'] as bool? ?? false,
      reason: json['reason'] as String? ?? 'unknown',
      retries: json['retries'] as int? ?? 0,
      userId: json['userId'] as String?,
      device: json['device'] as String?,
    );
  }
}

class VerifySessionStore {
  VerifySessionStore._();
  static final VerifySessionStore instance = VerifySessionStore._();

  static const int maxFails = 3;
  static const Duration lockoutDuration = Duration(seconds: 30);
  static const int maxLogs = 20;

  static const String _keyFailCount = 'verify_fail_count';
  static const String _keyLockoutUntil = 'verify_lockout_until';
  static const String _keyLogs = 'verify_logs';

  Future<int> getFailCount() async {
    final v = await SecureStore.instance.getString(_keyFailCount);
    return int.tryParse(v ?? '') ?? 0;
  }

  Future<void> _setFailCount(int v) async {
    await SecureStore.instance.setString(_keyFailCount, v.toString());
  }

  Future<DateTime?> getLockoutUntil() async {
    final v = await SecureStore.instance.getString(_keyLockoutUntil);
    if (v == null) return null;
    final ms = int.tryParse(v);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> _setLockoutUntil(DateTime? until) async {
    if (until == null) {
      await SecureStore.instance.deleteKey(_keyLockoutUntil);
      return;
    }
    await SecureStore.instance.setString(_keyLockoutUntil, until.millisecondsSinceEpoch.toString());
  }

  Future<bool> isLockedOut() async {
    final until = await getLockoutUntil();
    if (until == null) return false;
    if (until.isBefore(DateTime.now())) {
      await _setLockoutUntil(null);
      return false;
    }
    return true;
  }

  Future<DateTime?> registerFailure() async {
    final count = (await getFailCount()) + 1;
    if (count >= maxFails) {
      final until = DateTime.now().add(lockoutDuration);
      await _setLockoutUntil(until);
      await _setFailCount(0);
      return until;
    }
    await _setFailCount(count);
    return null;
  }

  Future<void> registerSuccess() async {
    await _setFailCount(0);
    await _setLockoutUntil(null);
  }

  Future<void> addLog(VerifyLogEntry entry) async {
    final raw = await SecureStore.instance.getString(_keyLogs);
    final list = <VerifyLogEntry>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            list.add(VerifyLogEntry.fromJson(item));
          } else if (item is Map) {
            list.add(VerifyLogEntry.fromJson(item.cast<String, dynamic>()));
          }
        }
      } catch (_) {}
    }

    list.insert(0, entry);
    if (list.length > maxLogs) {
      list.removeRange(maxLogs, list.length);
    }

    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await SecureStore.instance.setString(_keyLogs, encoded);
  }
}
