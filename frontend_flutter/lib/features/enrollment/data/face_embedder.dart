import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceEmbedder {
  FaceEmbedder._();
  static final instance = FaceEmbedder._();

  Interpreter? _itp;

  // MobileFaceNet defaults
  static const int inputSize = 112;
  static const int embeddingSize = 192;

  // ✅ MODEL LOADS HERE
  Future<void> init() async {
    if (_itp != null) return;

    _itp = await Interpreter.fromAsset(
      'assets/models/face_embedder.tflite',
    );
  }

  Future<List<double>> embedJpgBytes(Uint8List jpgBytes) async {
    await init();
    final itp = _itp!;

    final decoded = img.decodeImage(jpgBytes);
    if (decoded == null) throw Exception('Image decode failed');

    final resized =
    img.copyResize(decoded, width: inputSize, height: inputSize);

    final input = Float32List(inputSize * inputSize * 3);
    int i = 0;

    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);

        final r = pixel.r;
        final g = pixel.g;
        final b = pixel.b;

        // Normalize [-1,1]
        input[i++] = (r - 127.5) / 128.0;
        input[i++] = (g - 127.5) / 128.0;
        input[i++] = (b - 127.5) / 128.0;
      }
    }

    final inputTensor =
    input.reshape([1, inputSize, inputSize, 3]);

    final output =
    List.generate(1, (_) => List.filled(embeddingSize, 0.0));

    itp.run(inputTensor, output);

    return _l2Normalize(output[0]);
  }

  List<double> averageTemplate(List<List<double>> embs) {
    final d = embs.first.length;
    final avg = List<double>.filled(d, 0);

    for (final e in embs) {
      for (int i = 0; i < d; i++) {
        avg[i] += e[i];
      }
    }

    for (int i = 0; i < d; i++) {
      avg[i] /= embs.length;
    }

    return _l2Normalize(avg);
  }

  String toBase64(List<double> v) {
    final bytes = Float32List.fromList(v).buffer.asUint8List();
    return base64Encode(bytes);
  }

  List<double> _l2Normalize(List<double> v) {
    double sum = 0;
    for (final x in v) sum += x * x;
    final norm = sqrt(sum) + 1e-10;
    return v.map((x) => x / norm).toList();
  }
}