import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

class FaceCropper {
  FaceCropper._();
  static final instance = FaceCropper._();

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableLandmarks: false,
      enableContours: false,
      enableClassification: false,
      minFaceSize: 0.15,
    ),
  );

  Future<void> dispose() async {
    await _detector.close();
  }

  /// Returns cropped face JPG bytes from a photo file.
  /// If no face found, throws.
  Future<Uint8List> cropFaceJpgBytes(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final faces = await _detector.processImage(input);
    if (faces.isEmpty) {
      throw Exception('No face found in image');
    }

    // Pick the largest face
    faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
        .compareTo(a.boundingBox.width * a.boundingBox.height));
    final box = faces.first.boundingBox;

    final bytes = await File(imagePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Image decode failed');

    // Expand box a bit (padding)
    final pad = 0.18;
    final cx = box.left + box.width / 2;
    final cy = box.top + box.height / 2;
    final w = box.width * (1 + pad);
    final h = box.height * (1 + pad);

    int x = (cx - w / 2).round();
    int y = (cy - h / 2).round();
    int ww = w.round();
    int hh = h.round();

    // Clamp
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + ww > decoded.width) ww = decoded.width - x;
    if (y + hh > decoded.height) hh = decoded.height - y;

    final cropped = img.copyCrop(decoded, x: x, y: y, width: ww, height: hh);

    // Encode cropped face as jpg
    final jpg = img.encodeJpg(cropped, quality: 92);
    return Uint8List.fromList(jpg);
  }
}