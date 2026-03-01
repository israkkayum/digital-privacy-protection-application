import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/ui/notify.dart';
import '../../../core/utils/pose_utils.dart';
import '../../../main.dart'; // gCameras

enum EnrollStep { front, left, right, up, down, blink }

class EnrollmentCameraScreen extends StatefulWidget {
  const EnrollmentCameraScreen({super.key});

  @override
  State<EnrollmentCameraScreen> createState() => _EnrollmentCameraScreenState();
}

class _EnrollmentCameraScreenState extends State<EnrollmentCameraScreen> {
  // ---------------- Flow ----------------
  int currentIndex = 0;

  final List<EnrollStep> steps = const [
    EnrollStep.front,
    EnrollStep.left,
    EnrollStep.right,
    EnrollStep.up,
    EnrollStep.down,
    EnrollStep.blink,
  ];

  EnrollStep get step => steps[currentIndex];

  // store captured image paths per step (blink uses "BLINK_OK")
  final Map<EnrollStep, String?> capturedPath = {
    EnrollStep.front: null,
    EnrollStep.left: null,
    EnrollStep.right: null,
    EnrollStep.up: null,
    EnrollStep.down: null,
    EnrollStep.blink: null,
  };

  bool get _isCaptured => (capturedPath[step] != null);
  int get _doneCount => capturedPath.values.where((v) => v != null).length;
  double get _progress => _doneCount / steps.length;

  // ---------------- Camera ----------------
  CameraController? _controller;
  Future<void>? _initFuture;

  bool _streaming = false;
  bool _isProcessingFrame = false;
  bool _autoCapturing = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------------- FaceDetector ----------------
  FaceDetector? _detector;

  // ---------------- Pose thresholds + stability ----------------
  // yaw: left(-) right(+), pitch: up(-) down(+)
  static const double _yawLeft = -18;
  static const double _yawRight = 18;
  static const double _yawFrontMax = 10;

  static const double _pitchUp = -12;
  static const double _pitchDown = 12;
  static const double _pitchFrontMax = 10;

  int _stableFrames = 0;
  static const int _neededStable = 8; // ~8 frames stable ≈ good capture

  // Debug HUD values
  bool _faceOk = false;
  String _poseGuidance = 'Center your face in the frame.';

  // ---------------- Blink detection state ----------------
  bool _sawEyesOpen = false;
  bool _sawEyesClosed = false;

  static const double _openThresh = 0.65;
  static const double _closedThresh = 0.25;

  @override
  void initState() {
    super.initState();
    _setupCamera();
  }

  @override
  void dispose() {
    _stopStream();
    _closeDetector();
    _controller?.dispose();
    super.dispose();
  }

  // ---------------- Setup ----------------
  Future<void> _setupCamera() async {
    final front = gCameras
        .where((c) => c.lensDirection == CameraLensDirection.front)
        .toList();
    final cam = front.isNotEmpty
        ? front.first
        : (gCameras.isNotEmpty ? gCameras.first : null);

    if (cam == null) {
      if (mounted) Notify.error(context, 'No camera found on this device.');
      return;
    }

    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    setState(() {
      _controller = controller;
      _initFuture = controller.initialize();
    });

    await _initFuture;

    if (!mounted) return;
    _initDetectorForStep();
    await _startStream();
  }

  void _initDetectorForStep() {
    _closeDetector();

    final isBlink = step == EnrollStep.blink;

    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: true,
        enableClassification: isBlink, // only needed for blink step
        enableContours: false,
        enableLandmarks: false,
        minFaceSize: 0.15,
      ),
    );

    // reset per-step state
    _stableFrames = 0;
    _faceOk = false;
    _poseGuidance = 'Center your face in the frame.';

    if (isBlink) _resetBlinkState();
  }

  void _closeDetector() {
    try {
      _detector?.close();
    } catch (_) {}
    _detector = null;
  }

  // ---------------- UI helpers ----------------
  String _stepTitle(EnrollStep s) {
    switch (s) {
      case EnrollStep.front:
        return 'Look Straight';
      case EnrollStep.left:
        return 'Turn Left';
      case EnrollStep.right:
        return 'Turn Right';
      case EnrollStep.up:
        return 'Look Up';
      case EnrollStep.down:
        return 'Look Down';
      case EnrollStep.blink:
        return 'Blink Once';
    }
  }

  String _stepHint(EnrollStep s) {
    switch (s) {
      case EnrollStep.front:
        return 'Look at the camera and keep your face centered.';
      case EnrollStep.left:
        return 'Turn your face slightly to the left.';
      case EnrollStep.right:
        return 'Turn your face slightly to the right.';
      case EnrollStep.up:
        return 'Tilt your chin up a little.';
      case EnrollStep.down:
        return 'Tilt your chin down a little.';
      case EnrollStep.blink:
        return 'Keep eyes open, then blink once.';
    }
  }

  // ---------------- Storage helpers ----------------
  Future<String> _saveToAppDir(XFile file, EnrollStep forStep) async {
    final dir = await getApplicationDocumentsDirectory();
    final enrollDir = Directory(p.join(dir.path, 'enrollment'));
    if (!await enrollDir.exists()) await enrollDir.create(recursive: true);

    final filename =
        '${forStep.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final targetPath = p.join(enrollDir.path, filename);
    await File(file.path).copy(targetPath);
    return targetPath;
  }

  // ---------------- Stream: pose + blink auto logic ----------------
  Future<void> _startStream() async {
    final c = _controller;
    final d = _detector;
    if (c == null || d == null) return;
    if (_streaming) return;

    await _initFuture;

    _streaming = true;

    try {
      await c.startImageStream((CameraImage image) async {
        if (!_streaming) return;
        if (_isProcessingFrame) return;

        // Throttle
        final now = DateTime.now();
        if (now.difference(_lastProcessed).inMilliseconds < 150) return;
        _lastProcessed = now;

        _isProcessingFrame = true;

        try {
          final inputImage = _toInputImage(
            image,
            c.description.sensorOrientation,
          );
          final faces = await d.processImage(inputImage);

          if (!mounted) return;

          if (faces.length != 1) {
            // must be exactly one face
            _stableFrames = 0;
            setState(() {
              _faceOk = false;
              _poseGuidance = faces.isEmpty
                  ? 'No face found. Move your face inside the frame.'
                  : 'Only one face should be visible.';
            });
            return;
          }

          final face = faces.first;

          // Blink step
          if (step == EnrollStep.blink) {
            await _handleBlink(face);
            return;
          }

          // Pose step
          double yaw = face.headEulerAngleY ?? 0.0;
          double pitch = face.headEulerAngleX ?? 0.0;

          final lens =
              _controller?.description.lensDirection ??
              CameraLensDirection.front;
          final normalized = normalizeAngles(
            yaw: yaw,
            pitch: pitch,
            lens: lens,
          );

          final ok = _poseOk(step, normalized.yaw, normalized.pitch, face);

          if (ok) {
            _stableFrames++;
          } else {
            _stableFrames = 0;
          }

          final guidance = _poseFeedback(face: face, currentStep: step, ok: ok);

          setState(() {
            _faceOk = ok;
            _poseGuidance = guidance;
          });

          // Auto capture when stable
          if (_stableFrames >= _neededStable && !_autoCapturing) {
            _autoCapturing = true;

            // Stop stream before takePicture (required on many Android devices)
            await _stopStream();

            // Capture & continue
            await _capturePoseInternal();

            _autoCapturing = false;
          }
        } catch (_) {
          // keep silent; stream is frequent
        } finally {
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      _streaming = false;
      if (mounted) Notify.error(context, 'Camera stream failed: $e');
    }
  }

  Future<void> _stopStream() async {
    final c = _controller;
    if (c == null) return;
    if (!_streaming) return;

    _streaming = false;
    _isProcessingFrame = false;

    if (c.value.isStreamingImages) {
      try {
        await c.stopImageStream();
      } catch (_) {}
    }
  }

  bool _poseOk(EnrollStep s, double yaw, double pitch, Face face) {
    // quick “distance” heuristic: face bbox must be big enough
    if (face.boundingBox.width < 120 || face.boundingBox.height < 120) {
      return false;
    }

    switch (s) {
      case EnrollStep.front:
        return yaw.abs() < _yawFrontMax && pitch.abs() < _pitchFrontMax;
      case EnrollStep.left:
        return yaw < _yawLeft;
      case EnrollStep.right:
        return yaw > _yawRight;
      case EnrollStep.up:
        return pitch < _pitchUp;
      case EnrollStep.down:
        return pitch > _pitchDown;
      case EnrollStep.blink:
        return false;
    }
  }

  String _poseFeedback({
    required Face face,
    required EnrollStep currentStep,
    required bool ok,
  }) {
    if (face.boundingBox.width < 120 || face.boundingBox.height < 120) {
      return 'Move a little closer to the camera.';
    }

    if (!ok) {
      switch (currentStep) {
        case EnrollStep.front:
          return 'Look straight at the camera.';
        case EnrollStep.left:
          return 'Turn your face slightly to the left.';
        case EnrollStep.right:
          return 'Turn your face slightly to the right.';
        case EnrollStep.up:
          return 'Lift your chin a little.';
        case EnrollStep.down:
          return 'Lower your chin a little.';
        case EnrollStep.blink:
          return 'Keep your face centered.';
      }
    }

    if (_stableFrames >= _neededStable) return 'Great. Capturing now...';
    return 'Great. Hold still for a moment.';
  }

  // ---------------- Blink ----------------
  void _resetBlinkState() {
    _sawEyesOpen = false;
    _sawEyesClosed = false;
  }

  Future<void> _handleBlink(Face face) async {
    final le = face.leftEyeOpenProbability ?? -1;
    final re = face.rightEyeOpenProbability ?? -1;

    if (le < 0 || re < 0) return;

    final open = le > _openThresh && re > _openThresh;
    final closed = le < _closedThresh && re < _closedThresh;

    if (open) _sawEyesOpen = true;
    if (_sawEyesOpen && closed) _sawEyesClosed = true;

    // open -> closed -> open
    if (_sawEyesOpen && _sawEyesClosed && open) {
      setState(() {
        capturedPath[EnrollStep.blink] = 'BLINK_OK';
      });
      await _goNextOrFinish();
    }
  }

  // ---------------- Capture ----------------
  // Only used for pose steps (front/left/right/up/down)
  Future<void> _capturePoseInternal() async {
    final c = _controller;
    if (c == null) return;

    try {
      await _initFuture;
      if (c.value.isTakingPicture) return;

      final localStep = step; // important: freeze current step at capture time

      final shot = await c.takePicture();
      final savedPath = await _saveToAppDir(shot, localStep);

      if (!mounted) return;
      setState(() {
        capturedPath[localStep] = savedPath;
      });

      await _goNextOrFinish();
    } catch (e) {
      if (!mounted) return;
      Notify.error(context, 'Capture failed: $e');

      // try restarting stream so user can continue
      _initDetectorForStep();
      await _startStream();
    }
  }

  // ---------------- Next step / finish ----------------
  Future<void> _goNextOrFinish() async {
    // stop existing stream if any
    await _stopStream();

    if (!mounted) return;

    if (currentIndex < steps.length - 1) {
      setState(() => currentIndex++);
      _initDetectorForStep();
      await _startStream();
      return;
    }

    // final step done -> go processing
    final posePaths = <String>[
      capturedPath[EnrollStep.front]!,
      capturedPath[EnrollStep.left]!,
      capturedPath[EnrollStep.right]!,
      capturedPath[EnrollStep.up]!,
      capturedPath[EnrollStep.down]!,
    ];

    if (!mounted) return;
    context.go('/enroll/processing', extra: {'paths': posePaths});
  }

  // ---------------- Convert CameraImage -> InputImage ----------------
  InputImage _toInputImage(CameraImage image, int sensorOrientation) {
    final bytesBuilder = BytesBuilder(copy: false);
    for (final plane in image.planes) {
      bytesBuilder.add(plane.bytes);
    }
    final bytes = bytesBuilder.takeBytes();

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final rotation =
        InputImageRotationValue.fromRawValue(sensorOrientation) ??
        InputImageRotation.rotation0deg;

    final format =
        InputImageFormatValue.fromRawValue(image.format.raw) ??
        (image.planes.length == 1
            ? InputImageFormat.bgra8888
            : InputImageFormat.nv21);

    final metadata = InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  // ---------------- Build UI ----------------
  @override
  Widget build(BuildContext context) {
    final title = _stepTitle(step);
    final hint = _stepHint(step);
    final blinkStep = step == EnrollStep.blink;
    final stepNumber = currentIndex + 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Setup'),
        leading: IconButton(
          onPressed: () => context.go('/enroll'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Step $stepNumber of ${steps.length} - $title',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: TextStyle(color: Colors.black.withOpacity(0.72)),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF2563EB),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Stack(
                      children: [
                        if (_controller == null || _initFuture == null)
                          Center(
                            child: Text(
                              'No camera found',
                              style: TextStyle(
                                color: Colors.black.withOpacity(0.6),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          )
                        else
                          FutureBuilder(
                            future: _initFuture,
                            builder: (context, snap) {
                              if (snap.connectionState !=
                                  ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              return CameraPreview(_controller!);
                            },
                          ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: _isCaptured
                                        ? const Color(0xFF16A34A)
                                        : (_faceOk
                                              ? const Color(0xFF16A34A)
                                              : const Color(0xFF2563EB)),
                                    width: 3,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: !blinkStep
                  ? _PoseHud(
                      ok: _faceOk,
                      stableFrames: _stableFrames,
                      neededStable: _neededStable,
                      guidance: _poseGuidance,
                    )
                  : _BlinkHud(sawOpen: _sawEyesOpen, sawClosed: _sawEyesClosed),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StepStrip(
                capturedPath: capturedPath,
                steps: steps,
                currentIndex: currentIndex,
              ),
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () => context.go('/enroll'),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Start over'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ----------------- Pose HUD -----------------
class _PoseHud extends StatelessWidget {
  final bool ok;
  final int stableFrames;
  final int neededStable;
  final String guidance;

  const _PoseHud({
    required this.ok,
    required this.stableFrames,
    required this.neededStable,
    required this.guidance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Position Guide',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            guidance,
            style: TextStyle(
              color: Colors.black.withOpacity(0.75),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (stableFrames / neededStable).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                ok ? const Color(0xFF16A34A) : const Color(0xFF2563EB),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------- Blink HUD -----------------
class _BlinkHud extends StatelessWidget {
  final bool sawOpen;
  final bool sawClosed;

  const _BlinkHud({required this.sawOpen, required this.sawClosed});

  @override
  Widget build(BuildContext context) {
    final status = (sawOpen && sawClosed)
        ? 'Great. Blink captured.'
        : (sawOpen
              ? 'Now blink once.'
              : 'Keep your eyes open and look at the camera.');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Blink Check',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: TextStyle(
              color: Colors.black.withOpacity(0.75),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------- Step Strip -----------------
class _StepStrip extends StatelessWidget {
  final Map<EnrollStep, String?> capturedPath;
  final List<EnrollStep> steps;
  final int currentIndex;

  const _StepStrip({
    required this.capturedPath,
    required this.steps,
    required this.currentIndex,
  });

  String _label(EnrollStep s) {
    switch (s) {
      case EnrollStep.front:
        return 'Front';
      case EnrollStep.left:
        return 'Left';
      case EnrollStep.right:
        return 'Right';
      case EnrollStep.up:
        return 'Up';
      case EnrollStep.down:
        return 'Down';
      case EnrollStep.blink:
        return 'Blink';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: steps.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          final active = i == currentIndex;
          final done = capturedPath[s] != null;

          return Container(
            margin: EdgeInsets.only(right: i == steps.length - 1 ? 0 : 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: done ? const Color(0xFFDCFCE7) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active
                    ? const Color(0xFF2563EB)
                    : (done
                          ? const Color(0xFF22C55E)
                          : const Color(0xFFE2E8F0)),
                width: active ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  done ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: done
                      ? const Color(0xFF15803D)
                      : const Color(0xFF64748B),
                ),
                const SizedBox(width: 6),
                Text(
                  _label(s),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
