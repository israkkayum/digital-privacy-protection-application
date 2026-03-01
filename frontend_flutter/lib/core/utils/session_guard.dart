import 'package:firebase_auth/firebase_auth.dart';
import '../storage/secure_store.dart';

class SessionGuard {
  static bool get isLoggedInSync => FirebaseAuth.instance.currentUser != null;

  static Future<bool> isLoggedIn() async {
    return FirebaseAuth.instance.currentUser != null;
  }

  // ================= Enrollment =================

  static Future<bool> isEnrolled() async {
    return await SecureStore.instance.getBool(SecureStore.keyIsEnrolled);
  }

  static Future<void> setEnrolled(bool value) async {
    await SecureStore.instance.setBool(SecureStore.keyIsEnrolled, value);
  }

  static Future<void> saveTemplateBase64(String b64) async {
    await SecureStore.instance.setString(SecureStore.keyFaceTemplate, b64);
  }

  static Future<String?> loadTemplateBase64() async {
    return SecureStore.instance.getString(SecureStore.keyFaceTemplate);
  }

  // ================= Clear enrollment (manual reset) =================

  static Future<void> clearEnrollment() async {
    await SecureStore.instance.clearEnrollment();
  }
}