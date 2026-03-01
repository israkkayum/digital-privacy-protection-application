import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_session_service.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/storage/secure_store.dart';
import '../../reports/data/report_generator.dart';
import '../../../core/constants/app_constants.dart';
import 'scan_models.dart';

class ScanService {
  ScanService._();
  static final ScanService instance = ScanService._();

  Future<T> _withAuthRetry<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) rethrow;
      await AuthSessionService.instance.ensureSession(forceRefresh: true);
      return fn();
    }
  }

  Future<ScanJob> createLinkJob({required String url}) async {
    final platform = ReportGenerator.detectPlatform(url).toLowerCase();
    if (platform != 'youtube' &&
        platform != 'facebook' &&
        platform != 'tiktok') {
      throw Exception('Only YouTube, Facebook, and TikTok are supported');
    }

    final storedCountry = await SecureStore.instance.getString(
      SecureStore.keyCountry,
    );
    final country = (storedCountry == null || storedCountry.isEmpty)
        ? AppConstants.defaultCountry
        : storedCountry;

    try {
      return await _withAuthRetry(() async {
        await AuthSessionService.instance.ensureSession();
        final response = await ApiClient.instance.dio.post(
          Endpoints.scanLink,
          data: {'platform': platform, 'url': url, 'country': country},
        );
        return ScanJob.fromJson(response.data as Map<String, dynamic>);
      });
    } on DioException catch (e) {
      throw Exception(_friendlyApiError(e));
    }
  }

  Future<ScanJob> createUploadJob({
    required String filePath,
    required String fileName,
  }) async {
    final storedCountry = await SecureStore.instance.getString(
      SecureStore.keyCountry,
    );
    final country = (storedCountry == null || storedCountry.isEmpty)
        ? AppConstants.defaultCountry
        : storedCountry;

    try {
      return await _withAuthRetry(() async {
        await AuthSessionService.instance.ensureSession();
        final formData = FormData.fromMap({
          'country': country,
          'video': await MultipartFile.fromFile(filePath, filename: fileName),
        });

        final response = await ApiClient.instance.dio.post(
          Endpoints.scanUpload,
          data: formData,
        );

        return ScanJob.fromJson(response.data as Map<String, dynamic>);
      });
    } on DioException catch (e) {
      throw Exception(_friendlyApiError(e));
    }
  }

  Future<ScanStatus> fetchStatus(String jobId) async {
    return _withAuthRetry(() async {
      await AuthSessionService.instance.ensureSession();
      final response = await ApiClient.instance.dio.get(
        '${Endpoints.scanStatus}/$jobId',
      );
      return ScanStatus.fromJson(response.data as Map<String, dynamic>);
    });
  }

  String _friendlyApiError(DioException e) {
    final statusCode = e.response?.statusCode;
    final data = e.response?.data;

    if (statusCode == 503 &&
        data is Map<String, dynamic> &&
        data['error'] == 'inference_unavailable') {
      final inference = data['inference'];
      final url = inference is Map<String, dynamic>
          ? (inference['url'] as String?)
          : null;
      final details = inference is Map<String, dynamic>
          ? (inference['details'] as String?)
          : null;

      final buffer = StringBuffer(
        'Scan service is unavailable because face inference is offline.',
      );
      if (url != null && url.isNotEmpty) {
        buffer.write('\nInference URL: $url');
      }
      if (details != null && details.isNotEmpty) {
        buffer.write('\nDetails: $details');
      }
      buffer.write('\nStart the Python inference server, then retry.');
      return buffer.toString();
    }

    if (data is Map<String, dynamic>) {
      final message = data['message'] ?? data['error'];
      if (message is String && message.isNotEmpty) {
        if (message == 'video_too_large') {
          return 'Uploaded video is too large.';
        }
        if (message == 'unsupported_video_format') {
          return 'Unsupported video format. Use mp4/mov/m4v/webm.';
        }
        if (message == 'invalid_platform_url') {
          return 'URL does not match selected platform. Use a valid YouTube/Facebook/TikTok link.';
        }
        return message;
      }
    }

    return e.message ?? 'Request failed';
  }
}
