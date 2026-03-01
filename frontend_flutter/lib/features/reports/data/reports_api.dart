import '../../../core/network/api_client.dart';
import '../../../core/network/auth_session_service.dart';
import '../../../core/network/endpoints.dart';
import 'package:dio/dio.dart';
import 'report_models.dart';

class ReportsApi {
  ReportsApi._();
  static final ReportsApi instance = ReportsApi._();

  Future<List<CountryProfileModel>> fetchCountries() async {
    await AuthSessionService.instance.ensureSession();
    final response = await ApiClient.instance.dio.get(Endpoints.countries);
    final data = response.data as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(CountryProfileModel.fromJson)
        .toList();
  }

  Future<CountryProfileModel> fetchCountry(String countryCode) async {
    await AuthSessionService.instance.ensureSession();
    final response = await ApiClient.instance.dio.get(
      '${Endpoints.countries}/$countryCode',
    );
    return CountryProfileModel.fromJson(
      (response.data as Map).cast<String, dynamic>(),
    );
  }

  Future<ReportRecord> createReport({
    required String countryCode,
    required String platform,
    required String url,
    String? scanId,
    String? notes,
    Map<String, String>? userFields,
  }) async {
    try {
      await AuthSessionService.instance.ensureSession();
      final response = await ApiClient.instance.dio.post(
        Endpoints.reports,
        data: {
          'countryCode': countryCode,
          'platform': platform,
          'url': url,
          if (scanId != null && scanId.isNotEmpty) 'scanId': scanId,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
          if (userFields != null) 'userFields': userFields,
        },
      );
      return ReportRecord.fromJson(
        (response.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw Exception(_friendlyCreateError(e));
    }
  }

  Future<void> sendReport(String reportId) async {
    try {
      await AuthSessionService.instance.ensureSession();
      await ApiClient.instance.dio.post('${Endpoints.reports}/$reportId/send');
    } on DioException catch (e) {
      throw Exception(_friendlySendError(e));
    }
  }

  Future<void> resetReport(String reportId) async {
    await AuthSessionService.instance.ensureSession();
    await ApiClient.instance.dio.post('${Endpoints.reports}/$reportId/reset');
  }

  Future<List<ReportListItem>> fetchReports({bool forceRefresh = false}) async {
    await AuthSessionService.instance.ensureSession();
    final response = await ApiClient.instance.dio.get(
      Endpoints.reports,
      queryParameters: forceRefresh
          ? {'_ts': DateTime.now().millisecondsSinceEpoch}
          : null,
      options: Options(headers: {'Cache-Control': 'no-cache'}),
    );
    final data = response.data as List<dynamic>;
    return data
        .whereType<Map<String, dynamic>>()
        .map(ReportListItem.fromJson)
        .toList();
  }

  Future<ReportRecord> fetchReport(
    String reportId, {
    bool forceRefresh = false,
  }) async {
    await AuthSessionService.instance.ensureSession();
    final response = await ApiClient.instance.dio.get(
      '${Endpoints.reports}/$reportId',
      queryParameters: forceRefresh
          ? {'_ts': DateTime.now().millisecondsSinceEpoch}
          : null,
      options: Options(headers: {'Cache-Control': 'no-cache'}),
    );
    return ReportRecord.fromJson(
      (response.data as Map).cast<String, dynamic>(),
    );
  }

  String _friendlyCreateError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final error = data['error']?.toString() ?? '';
      if (error == 'invalid_platform_url') {
        return 'URL does not match selected platform. Use a valid YouTube/Facebook/TikTok link.';
      }
      if (error == 'scan_required') {
        return 'Scan ID is missing. Please start from Verify -> Scan -> Report.';
      }
      if (error == 'invalid_scan_id' || error == 'scan_not_found') {
        return 'Attached scan is invalid or expired. Re-run scan and try again.';
      }
      if (error == 'required_fields_missing') {
        final missing = (data['missingFields'] as List? ?? const [])
            .map((e) => e.toString())
            .join(', ');
        if (missing.isNotEmpty) {
          return 'Please fill required fields: $missing';
        }
        return 'Please fill all required fields.';
      }
      if (error.isNotEmpty) return error;
    }
    return e.message ?? 'Failed to create report';
  }

  String _friendlySendError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final error = data['error']?.toString() ?? '';
      if (error == 'send_locked') {
        final retryAfter = (data['retryAfterSec'] as num?)?.toInt() ?? 0;
        if (retryAfter > 0) {
          return 'Please wait $retryAfter seconds before retrying.';
        }
        return 'Please wait a few seconds before retrying.';
      }
      if (error == 'already_queued') {
        return 'Report is already queued.';
      }
      if (error == 'report_not_found') {
        return 'Report not found.';
      }
      if (error.isNotEmpty) return error;
    }
    if (e.response?.statusCode == 429) {
      return 'Too many send attempts. Please wait and retry.';
    }
    return e.message ?? 'Failed to send report';
  }
}
