import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';

import '../storage/secure_store.dart';
import 'api_client.dart';
import 'endpoints.dart';

class AuthSessionService {
  AuthSessionService._();
  static final AuthSessionService instance = AuthSessionService._();

  Future<String?> ensureSession({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await SecureStore.instance.deleteKey(SecureStore.keyAuthToken);
    }

    final existing = await SecureStore.instance.getString(
      SecureStore.keyAuthToken,
    );
    if (existing != null && existing.isNotEmpty) return existing;

    final user = FirebaseAuth.instance.currentUser;
    final idToken = user == null ? null : await user.getIdToken();

    final dio = ApiClient.instance.dio;
    final headers = <String, dynamic>{};
    if (idToken == null || idToken.isEmpty) {
      headers['X-Dev-UserId'] = user?.uid ?? user?.email ?? 'dev_user';
    }

    final response = await dio.post(
      Endpoints.authSession,
      data: {'firebaseIdToken': idToken},
      options: Options(headers: headers),
    );

    final accessToken = response.data['accessToken'] as String?;
    final userId = response.data['userId'] as String?;

    if (accessToken != null) {
      await SecureStore.instance.setString(
        SecureStore.keyAuthToken,
        accessToken,
      );
    }
    if (userId != null) {
      await SecureStore.instance.setString(SecureStore.keyUserId, userId);
    }

    return accessToken;
  }
}
