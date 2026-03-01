import '../../../core/network/api_client.dart';
import '../../../core/network/auth_session_service.dart';
import '../../../core/network/endpoints.dart';
import '../../../core/storage/secure_store.dart';

class TemplateService {
  TemplateService._();
  static final TemplateService instance = TemplateService._();

  Future<void> uploadTemplate() async {
    final templateB64 = await SecureStore.instance.getString(SecureStore.keyFaceTemplate);
    if (templateB64 == null || templateB64.isEmpty) {
      throw Exception('No local template found');
    }

    await AuthSessionService.instance.ensureSession();

    await ApiClient.instance.dio.post(
      Endpoints.enrollTemplate,
      data: {
        'templateB64': templateB64,
        'embeddingSize': 192,
        'model': 'mobilefacenet',
      },
    );
  }
}
