import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore._();
  static final SecureStore instance = SecureStore._();

  static const _storage = FlutterSecureStorage();

  // ================= ENROLLMENT KEYS (NEVER delete on logout) =================
  static const String keyIsEnrolled = 'is_enrolled';
  static const String keyFaceTemplate = 'face_template_b64';

  // ================= AUTH / SESSION KEYS (delete on logout) ==================
  static const String keyAuthToken = 'auth_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyUserId = 'user_id';
  static const String keyCountry = 'country';
  static const String keyBackendUrl = 'backend_url';
  static const String keyLawAgencyName = 'law_agency_name';
  static const String keyLawAgencyEmail = 'law_agency_email';
  static const String keyLawAgencyPhone = 'law_agency_phone';
  static const String keyLawAgencyAddress = 'law_agency_address';

  // --------------------------------------------------------------------------

  Future<void> setBool(String key, bool value) async {
    await _storage.write(key: key, value: value ? '1' : '0');
  }

  Future<bool> getBool(String key) async {
    final v = await _storage.read(key: key);
    return v == '1';
  }

  Future<void> setString(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> getString(String key) async {
    return _storage.read(key: key);
  }

  Future<void> deleteKey(String key) async {
    await _storage.delete(key: key);
  }

  // ================= LOGOUT SAFE =================
  // Keeps enrollment + face template
  Future<void> clearAuthOnly() async {
    await _storage.delete(key: keyAuthToken);
    await _storage.delete(key: keyRefreshToken);
    await _storage.delete(key: keyUserId);
  }

  // ================= MANUAL ENROLLMENT RESET =================
  Future<void> clearEnrollment() async {
    await _storage.delete(key: keyIsEnrolled);
    await _storage.delete(key: keyFaceTemplate);
  }

  // ================= NUCLEAR OPTION (DON'T USE ON LOGOUT) =================
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
