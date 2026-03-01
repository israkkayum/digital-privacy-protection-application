import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../../../core/biometrics/face_pipeline_config.dart';
import '../../../core/utils/session_guard.dart';
import 'face_embedder.dart';


class EnrollmentProcessor {
  EnrollmentProcessor._();
  static final instance = EnrollmentProcessor._();

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      minFaceSize: FacePipelineConfig.minFaceSizeRatio,
    ),
  );

  Future<void> dispose() async {
    await _detector.close();
  }

  /// Builds face template from pose images, stores it securely, and marks enrolled = true.
  Future<void> buildAndSaveTemplate({
    required List<String> poseImagePaths, // front/left/right/up/down
  }) async {
    if (poseImagePaths.length < 3) {
      throw Exception('Not enough images. Please capture at least 3 poses.');
    }

    final embs = <List<double>>[];

    for (final path in poseImagePaths) {
      final croppedJpgBytes = await cropFaceFromPath(path);
      final emb = await FaceEmbedder.instance.embedJpgBytes(croppedJpgBytes);
      embs.add(emb);

      // Add mirrored pose embedding to make template more robust to orientation differences.
      final mirrored = _flipHorizontal(croppedJpgBytes);
      final mirroredEmb = await FaceEmbedder.instance.embedJpgBytes(mirrored);
      embs.add(mirroredEmb);
    }

    final template = FaceEmbedder.instance.averageTemplate(embs);
    final b64 = FaceEmbedder.instance.toBase64(template);

    // ✅ Store template + set enrolled flag
    await SessionGuard.saveTemplateBase64(b64);
    await SessionGuard.setEnrolled(true);
  }

  Future<Uint8List> cropFaceFromPath(String imagePath) async {
    final file = File(imagePath);
    if (!file.existsSync()) throw Exception('Image not found');

    final faces = await _detector.processImage(InputImage.fromFilePath(imagePath));
    if (faces.isEmpty) {
      throw Exception('No face found');
    }
    if (faces.length > 1) {
      throw Exception('Multiple faces found');
    }

    final face = faces.first;
    if (face.boundingBox.width < FacePipelineConfig.minFaceBoxPx ||
        face.boundingBox.height < FacePipelineConfig.minFaceBoxPx) {
      throw Exception('Face too small. Move closer and recapture.');
    }

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Image decode failed');

    final lightingIssue = _hasLightingIssue(decoded);
    if (lightingIssue) {
      throw Exception('Poor lighting. Use balanced front light and recapture.');
    }

    final crop = _cropFace(decoded, face.boundingBox);
    return crop;
  }

  Uint8List _cropFace(img.Image decoded, Rect box) {
    const pad = FacePipelineConfig.cropPad;
    final cx = box.left + box.width / 2;
    final cy = box.top + box.height / 2;
    final w = box.width * (1 + pad);
    final h = box.height * (1 + pad);

    int x = (cx - w / 2).round();
    int y = (cy - h / 2).round();
    int ww = w.round();
    int hh = h.round();

    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + ww > decoded.width) ww = decoded.width - x;
    if (y + hh > decoded.height) hh = decoded.height - y;

    final cropped = img.copyCrop(decoded, x: x, y: y, width: ww, height: hh);
    return Uint8List.fromList(
      img.encodeJpg(cropped, quality: FacePipelineConfig.jpgQuality),
    );
  }

  bool _hasLightingIssue(img.Image decoded) {
    double sum = 0;
    int count = 0;
    const step = 8;

    for (int y = 0; y < decoded.height; y += step) {
      for (int x = 0; x < decoded.width; x += step) {
        final pixel = decoded.getPixel(x, y);
        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;
        final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
        sum += lum;
        count++;
      }
    }

    if (count == 0) return true;
    final avg = sum / count;
    return avg < FacePipelineConfig.minLighting || avg > FacePipelineConfig.maxLighting;
  }

  Uint8List _flipHorizontal(Uint8List jpgBytes) {
    final decoded = img.decodeImage(jpgBytes);
    if (decoded == null) {
      return jpgBytes;
    }
    final flipped = img.flipHorizontal(decoded);
    return Uint8List.fromList(
      img.encodeJpg(flipped, quality: FacePipelineConfig.jpgQuality),
    );
  }
}
