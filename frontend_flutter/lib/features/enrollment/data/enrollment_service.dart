import '../../../core/storage/secure_store.dart';
import 'face_cropper.dart';
import 'face_embedder.dart';

class EnrollmentService {
  EnrollmentService._();
  static final instance = EnrollmentService._();

  /// Takes pose image paths (front/left/right/up/down) and returns template base64.
  Future<String> buildTemplateBase64(List<String> posePaths) async {
    final embeddings = <List<double>>[];

    for (final path in posePaths) {
      final faceJpg = await FaceCropper.instance.cropFaceJpgBytes(path);
      final emb = await FaceEmbedder.instance.embedJpgBytes(faceJpg);
      embeddings.add(emb);
    }

    final template = FaceEmbedder.instance.averageTemplate(embeddings);
    return FaceEmbedder.instance.toBase64(template);
  }

  Future<void> saveTemplateAndMarkEnrolled(String templateB64) async {
    await SecureStore.instance.setString(SecureStore.keyFaceTemplate, templateB64);
    await SecureStore.instance.setBool(SecureStore.keyIsEnrolled, true);
  }

  Future<String?> loadTemplateB64() async {
    return SecureStore.instance.getString(SecureStore.keyFaceTemplate);
  }
}