import 'dart:io';

import 'package:dio/dio.dart';

import '../constants/app_constants.dart';
import '../storage/secure_store.dart';

class ApiClient {
  ApiClient._()
    : dio = Dio(
        BaseOptions(
          baseUrl: AppConstants.backendBaseUrlOverride.isNotEmpty
              ? AppConstants.backendBaseUrlOverride
              : (Platform.isAndroid
                    ? AppConstants.backendBaseUrlAndroid
                    : AppConstants.backendBaseUrlIOS),
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
        ),
      ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (AppConstants.backendBaseUrlOverride.isEmpty) {
            final storedBase = await SecureStore.instance.getString(
              SecureStore.keyBackendUrl,
            );
            if (storedBase != null && storedBase.isNotEmpty) {
              options.baseUrl = storedBase;
            }
          }
          final token = await SecureStore.instance.getString(
            SecureStore.keyAuthToken,
          );
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            await SecureStore.instance.deleteKey(SecureStore.keyAuthToken);
          }
          handler.next(error);
        },
      ),
    );
  }

  static final ApiClient instance = ApiClient._();
  final Dio dio;
}
