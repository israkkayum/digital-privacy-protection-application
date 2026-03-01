import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../../core/biometrics/face_pipeline_config.dart';
import '../../../core/storage/secure_store.dart';
import '../../enrollment/data/face_embedder.dart';
import 'face_matcher.dart';

class LiveVerifyReason {
  static const String success = 'success';
  static const String noTemplate = 'no_template';
  static const String poseIncomplete = 'pose_incomplete';
  static const String fileMissing = 'file_missing';
  static const String noFace = 'no_face';
  static const String multipleFaces = 'multiple_faces';
  static const String faceTooSmall = 'face_too_small';
  static const String poorLighting = 'poor_lighting';
  static const String embeddingFailed = 'embedding_failed';
  static const String lowScore = 'low_score';
  static const String livenessNotSatisfied = 'liveness_not_satisfied';
  static const String error = 'error';
}

class LiveVerifyResult {
  final bool ok;
  final double score; // cosine similarity
  final double threshold;
  final String reason;
  final String? bestPose;
  final Map<String, dynamic>? debug;

  LiveVerifyResult({
    required this.ok,
    required this.score,
    required this.threshold,
    required this.reason,
    this.bestPose,
    this.debug,
  });

  factory LiveVerifyResult.fail({
    required String reason,
    required double threshold,
    double score = 0.0,
  }) {
    return LiveVerifyResult(
      ok: false,
      score: score,
      threshold: threshold,
      reason: reason,
    );
  }
}

class LiveVerifyService {
  LiveVerifyService._();
  static final instance = LiveVerifyService._();

  /// Slightly relaxed default to reduce false rejects on-device.
  final double threshold = 0.68;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableContours: false,
      enableLandmarks: false,
      enableClassification: false,
      minFaceSize: FacePipelineConfig.minFaceSizeRatio,
    ),
  );

  Future<LiveVerifyResult> verifyFromPoseImages(List<String> posePaths) async {
    if (posePaths.isEmpty) {
      return LiveVerifyResult.fail(
        reason: LiveVerifyReason.poseIncomplete,
        threshold: threshold,
      );
    }

    final enrolledB64 = await SecureStore.instance.getString(
      SecureStore.keyFaceTemplate,
    );
    if (enrolledB64 == null || enrolledB64.isEmpty) {
      return LiveVerifyResult.fail(
        reason: LiveVerifyReason.noTemplate,
        threshold: threshold,
      );
    }
    late final List<double> enrolled;
    try {
      enrolled = _fromBase64(enrolledB64);
    } catch (_) {
      return LiveVerifyResult.fail(
        reason: LiveVerifyReason.embeddingFailed,
        threshold: threshold,
      );
    }

    final embs = <List<double>>[];
    double bestScore = -1;
    String? bestPose;
    bool mirrorHelped = false;

    for (final path in posePaths) {
      final check = await _detectAndCrop(path);
      if (!check.ok) {
        return LiveVerifyResult.fail(
          reason: check.reason,
          threshold: threshold,
        );
      }

      try {
        final poseScore = await _embedAndScore(
          enrolled: enrolled,
          croppedBytes: check.croppedBytes!,
        );
        embs.add(poseScore.embedding);

        if (poseScore.score > bestScore) {
          bestScore = poseScore.score;
          bestPose = check.poseLabel;
        }
        mirrorHelped = mirrorHelped || poseScore.usedMirror;
      } catch (_) {
        return LiveVerifyResult.fail(
          reason: LiveVerifyReason.embeddingFailed,
          threshold: threshold,
        );
      }
    }

    final live = FaceEmbedder.instance.averageTemplate(embs);
    final avgScore = FaceMatcher.cosine(enrolled, live);
    final score = bestScore > avgScore ? bestScore : avgScore;
    final ok = score >= threshold;

    return LiveVerifyResult(
      ok: ok,
      score: score,
      threshold: threshold,
      reason: ok ? LiveVerifyReason.success : LiveVerifyReason.lowScore,
      bestPose: bestPose,
      debug: {
        'bestScore': bestScore,
        'avgScore': avgScore,
        'poseCount': posePaths.length,
        'mirrorHelped': mirrorHelped,
      },
    );
  }

  List<double> _fromBase64(String b64) {
    final bytes = base64Decode(b64);
    if (bytes.lengthInBytes % 4 != 0) {
      throw Exception('Invalid template bytes');
    }
    final f32 = bytes.buffer.asFloat32List();
    if (f32.length != FaceEmbedder.embeddingSize) {
      throw Exception('Embedding size mismatch');
    }
    return f32.map((e) => e.toDouble()).toList();
  }

  Future<_PoseCheck> _detectAndCrop(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      return _PoseCheck.fail(LiveVerifyReason.fileMissing);
    }

    final input = InputImage.fromFilePath(path);
    final faces = await _detector.processImage(input);

    if (faces.isEmpty) {
      return _PoseCheck.fail(LiveVerifyReason.noFace);
    }
    if (faces.length > 1) {
      return _PoseCheck.fail(LiveVerifyReason.multipleFaces);
    }

    final face = faces.first;
    if (face.boundingBox.width < FacePipelineConfig.minFaceBoxPx ||
        face.boundingBox.height < FacePipelineConfig.minFaceBoxPx) {
      return _PoseCheck.fail(LiveVerifyReason.faceTooSmall);
    }

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return _PoseCheck.fail(LiveVerifyReason.embeddingFailed);
    }

    final lightingIssue = _checkLighting(decoded);
    if (lightingIssue != null) {
      return _PoseCheck.fail(lightingIssue);
    }

    final crop = _cropFace(decoded, face.boundingBox);
    return _PoseCheck.ok(crop, _poseLabelFromPath(path));
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

  String? _checkLighting(img.Image decoded) {
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

    if (count == 0) return LiveVerifyReason.poorLighting;
    final avg = sum / count;
    if (avg < FacePipelineConfig.minLighting || avg > FacePipelineConfig.maxLighting) {
      return LiveVerifyReason.poorLighting;
    }
    return null;
  }

  String _poseLabelFromPath(String path) {
    final name = p.basenameWithoutExtension(path);
    final parts = name.split('_');
    return parts.isNotEmpty ? parts.first : 'pose';
  }

  Future<_EmbeddingScore> _embedAndScore({
    required List<double> enrolled,
    required Uint8List croppedBytes,
  }) async {
    final emb = await FaceEmbedder.instance.embedJpgBytes(croppedBytes);
    final directScore = FaceMatcher.cosine(enrolled, emb);

    final mirroredBytes = _flipHorizontal(croppedBytes);
    final mirroredEmb = await FaceEmbedder.instance.embedJpgBytes(
      mirroredBytes,
    );
    final mirroredScore = FaceMatcher.cosine(enrolled, mirroredEmb);

    if (mirroredScore > directScore) {
      return _EmbeddingScore(
        embedding: mirroredEmb,
        score: mirroredScore,
        usedMirror: true,
      );
    }

    return _EmbeddingScore(
      embedding: emb,
      score: directScore,
      usedMirror: false,
    );
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

class _PoseCheck {
  final bool ok;
  final String reason;
  final Uint8List? croppedBytes;
  final String? poseLabel;

  const _PoseCheck._(this.ok, this.reason, this.croppedBytes, this.poseLabel);

  factory _PoseCheck.ok(Uint8List bytes, String? poseLabel) {
    return _PoseCheck._(true, LiveVerifyReason.success, bytes, poseLabel);
  }

  factory _PoseCheck.fail(String reason) {
    return _PoseCheck._(false, reason, null, null);
  }
}

class _EmbeddingScore {
  final List<double> embedding;
  final double score;
  final bool usedMirror;

  const _EmbeddingScore({
    required this.embedding,
    required this.score,
    required this.usedMirror,
  });
}
