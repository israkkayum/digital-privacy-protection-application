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
import '../data/verify_session_store.dart';

enum VerifyStep { front, left, right, up, down, blink }

enum _VerifyIssue { none, noFace, multipleFaces, faceTooSmall, poseMismatch }

class LiveVerifyCameraScreen extends StatefulWidget {
  final String? nextRoute;
  final Object? nextExtra;

  const LiveVerifyCameraScreen({super.key, this.nextRoute, this.nextExtra});

  @override
  State<LiveVerifyCameraScreen> createState() => _LiveVerifyCameraScreenState();
}

class _LiveVerifyCameraScreenState extends State<LiveVerifyCameraScreen> {
  int currentIndex = 0;

  final steps = const [VerifyStep.front, VerifyStep.blink];

  VerifyStep get step => steps[currentIndex];

  final Map<VerifyStep, String?> capturedPath = {
    VerifyStep.front: null,
    VerifyStep.blink: null, // "BLINK_OK"
  };

  bool get _isCaptured => capturedPath[step] != null;
  int get _doneCount => capturedPath.values.where((v) => v != null).length;
  double get _progress => _doneCount / steps.length;

  CameraController? _controller;
  Future<void>? _initFuture;

  FaceDetector? _detector;

  bool _streaming = false;
  bool _isProcessingFrame = false;
  bool _autoCapturing = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);

  bool _lockedOut = false;
  DateTime? _lockoutUntil;

  // Pose thresholds
  static const double _yawLeft = -18;
  static const double _yawRight = 18;
  static const double _yawFrontMax = 10;

  static const double _pitchUp = -12;
  static const double _pitchDown = 12;
  static const double _pitchFrontMax = 10;

  int _stableFrames = 0;
  static const int _neededStable = 8;

  // HUD
  double _yaw = 0;
  double _pitch = 0;
  bool _poseOk = false;
  _VerifyIssue _issue = _VerifyIssue.none;

  // Blink state
  bool _sawEyesOpen = false;
  bool _sawEyesClosed = false;
  double _leftEye = -1;
  double _rightEye = -1;

  static const double _openThresh = 0.65;
  static const double _closedThresh = 0.25;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _stopStream();
    _closeDetector();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final locked = await VerifySessionStore.instance.isLockedOut();
    if (locked) {
      final until = await VerifySessionStore.instance.getLockoutUntil();
      if (mounted) {
        setState(() {
          _lockedOut = true;
          _lockoutUntil = until;
        });
      }
      return;
    }
    await _setupCamera();
  }

  Future<void> _setupCamera() async {
    final front = gCameras
        .where((c) => c.lensDirection == CameraLensDirection.front)
        .toList();
    final cam = front.isNotEmpty
        ? front.first
        : (gCameras.isNotEmpty ? gCameras.first : null);

    if (cam == null) {
      if (mounted) Notify.error(context, 'No camera found.');
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

    final isBlink = step == VerifyStep.blink;
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableTracking: true,
        enableClassification: isBlink,
        enableContours: false,
        enableLandmarks: false,
        minFaceSize: 0.15,
      ),
    );

    _stableFrames = 0;
    _yaw = 0;
    _pitch = 0;
    _poseOk = false;
    _issue = _VerifyIssue.none;

    if (isBlink) _resetBlink();
  }

  void _closeDetector() {
    try {
      _detector?.close();
    } catch (_) {}
    _detector = null;
  }

  // ----------- UI text -----------
  String _title(VerifyStep s) {
    switch (s) {
      case VerifyStep.front:
        return 'Front';
      case VerifyStep.left:
        return 'Left';
      case VerifyStep.right:
        return 'Right';
      case VerifyStep.up:
        return 'Up';
      case VerifyStep.down:
        return 'Down';
      case VerifyStep.blink:
        return 'Blink (Liveness)';
    }
  }

  String _hint(VerifyStep s) {
    switch (s) {
      case VerifyStep.front:
        return 'Look straight. Keep face centered.';
      case VerifyStep.left:
        return 'Turn slightly left.';
      case VerifyStep.right:
        return 'Turn slightly right.';
      case VerifyStep.up:
        return 'Tilt head slightly up.';
      case VerifyStep.down:
        return 'Tilt head slightly down.';
      case VerifyStep.blink:
        return 'Blink naturally once.';
    }
  }

  // ----------- Stream -----------
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
            _stableFrames = 0;
            setState(() {
              _poseOk = false;
              _yaw = 0;
              _pitch = 0;
              _leftEye = -1;
              _rightEye = -1;
              _issue = faces.isEmpty
                  ? _VerifyIssue.noFace
                  : _VerifyIssue.multipleFaces;
            });
            return;
          }

          final face = faces.first;

          if (step == VerifyStep.blink) {
            _handleBlink(face);
            return;
          }

          if (face.boundingBox.width < 120 || face.boundingBox.height < 120) {
            _stableFrames = 0;
            setState(() {
              _poseOk = false;
              _issue = _VerifyIssue.faceTooSmall;
            });
            return;
          }

          final yaw = face.headEulerAngleY ?? 0.0;
          final pitch = face.headEulerAngleX ?? 0.0;
          final lens =
              _controller?.description.lensDirection ??
              CameraLensDirection.front;
          final normalized = normalizeAngles(
            yaw: yaw,
            pitch: pitch,
            lens: lens,
          );

          final ok = _isPoseOk(step, normalized.yaw, normalized.pitch, face);

          if (ok) {
            _stableFrames++;
          } else {
            _stableFrames = 0;
          }

          setState(() {
            _yaw = normalized.yaw;
            _pitch = normalized.pitch;
            _poseOk = ok;
            _issue = ok ? _VerifyIssue.none : _VerifyIssue.poseMismatch;
          });

          if (_stableFrames >= _neededStable && !_autoCapturing) {
            _autoCapturing = true;

            await _stopStream(); // IMPORTANT before takePicture
            await _capturePoseInternal(); // saves image and continues
            _autoCapturing = false;
          }
        } catch (_) {
          // ignore per-frame errors
        } finally {
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      _streaming = false;
      if (mounted) Notify.error(context, 'Stream failed: $e');
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

  bool _isPoseOk(VerifyStep s, double yaw, double pitch, Face face) {
    switch (s) {
      case VerifyStep.front:
        return yaw.abs() < _yawFrontMax && pitch.abs() < _pitchFrontMax;
      case VerifyStep.left:
        return yaw < _yawLeft;
      case VerifyStep.right:
        return yaw > _yawRight;
      case VerifyStep.up:
        return pitch < _pitchUp;
      case VerifyStep.down:
        return pitch > _pitchDown;
      case VerifyStep.blink:
        return false;
    }
  }

  // ----------- Blink -----------
  void _resetBlink() {
    _sawEyesOpen = false;
    _sawEyesClosed = false;
    _leftEye = -1;
    _rightEye = -1;
  }

  void _handleBlink(Face face) {
    final le = face.leftEyeOpenProbability ?? -1;
    final re = face.rightEyeOpenProbability ?? -1;

    setState(() {
      _leftEye = le;
      _rightEye = re;
    });

    if (le < 0 || re < 0) return;

    final open = le > _openThresh && re > _openThresh;
    final closed = le < _closedThresh && re < _closedThresh;

    if (open) _sawEyesOpen = true;
    if (_sawEyesOpen && closed) _sawEyesClosed = true;

    if (_sawEyesOpen && _sawEyesClosed && open) {
      setState(() => capturedPath[VerifyStep.blink] = 'BLINK_OK');
      _goNextOrFinish();
    }
  }

  // ----------- Capture Pose -----------
  Future<String> _saveToAppDir(XFile file, VerifyStep forStep) async {
    final dir = await getApplicationDocumentsDirectory();
    final verifyDir = Directory(p.join(dir.path, 'live_verify'));
    if (!await verifyDir.exists()) await verifyDir.create(recursive: true);

    final filename =
        '${forStep.name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final targetPath = p.join(verifyDir.path, filename);
    await File(file.path).copy(targetPath);
    return targetPath;
  }

  Future<void> _capturePoseInternal() async {
    final c = _controller;
    if (c == null) return;

    try {
      await _initFuture;
      if (c.value.isTakingPicture) return;

      final localStep = step;
      final shot = await c.takePicture();
      final saved = await _saveToAppDir(shot, localStep);

      if (!mounted) return;
      setState(() => capturedPath[localStep] = saved);

      _goNextOrFinish();
    } catch (e) {
      if (!mounted) return;
      Notify.error(context, 'Capture failed: $e');

      _initDetectorForStep();
      await _startStream();
    }
  }

  Future<void> _retake() async {
    setState(() {
      capturedPath[step] = null;
      _stableFrames = 0;
    });
    await _stopStream();
    _initDetectorForStep();
    await _startStream();
  }

  // ----------- Next / Finish -----------
  void _goNextOrFinish() async {
    await _stopStream();

    if (!mounted) return;

    if (currentIndex < steps.length - 1) {
      setState(() => currentIndex++);
      _initDetectorForStep();
      await _startStream();
      return;
    }

    // finished -> go processing
    final posePaths = <String>[];
    for (final s in steps) {
      if (s == VerifyStep.blink) continue;
      final path = capturedPath[s];
      if (path != null) posePaths.add(path);
    }

    context.go(
      '/verify/live/processing',
      extra: {
        'paths': posePaths,
        'blinkOk': capturedPath[VerifyStep.blink] == 'BLINK_OK',
        'next': widget.nextRoute,
        'nextExtra': widget.nextExtra,
      },
    );
  }

  // ----------- Convert frame to InputImage -----------
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

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final blinkStep = step == VerifyStep.blink;
    final title = _title(step);
    final hint = _hint(step);
    final String statusText = blinkStep
        ? (capturedPath[VerifyStep.blink] != null
              ? 'Blink detected'
              : 'Please blink once')
        : () {
            switch (_issue) {
              case _VerifyIssue.noFace:
                return 'No face detected';
              case _VerifyIssue.multipleFaces:
                return 'Only one face in frame';
              case _VerifyIssue.faceTooSmall:
                return 'Move closer to the camera';
              case _VerifyIssue.poseMismatch:
                return 'Align your face';
              case _VerifyIssue.none:
                return _poseOk ? 'Hold steady' : 'Align your face';
            }
          }();

    if (_lockedOut) {
      final untilText = _lockoutUntil == null
          ? 'Please try again later.'
          : 'Try again after ${_lockoutUntil!.toLocal().toString().split('.').first}';
      return Scaffold(
        body: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 46, 16, 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go('/verify'),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Live Verification',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Temporarily locked',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    untilText,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'You have reached the maximum number of attempts. Please wait and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black.withOpacity(0.7)),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          // Header (same style as enrollment)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 46, 16, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => context.go('/verify'),
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Live Verification',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$_doneCount/${steps.length}',
                      style: TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 8,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF22C55E),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hint,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Camera preview
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    children: [
                      if (_controller == null || _initFuture == null)
                        Center(
                          child: Text(
                            'No camera found',
                            style: TextStyle(
                              color: Colors.black.withOpacity(0.6),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      else
                        FutureBuilder(
                          future: _initFuture,
                          builder: (context, snap) {
                            if (snap.connectionState != ConnectionState.done) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            return CameraPreview(_controller!);
                          },
                        ),

                      // frame overlay
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: _isCaptured
                                      ? const Color(0xFF22C55E)
                                      : (_poseOk
                                            ? const Color(0xFF22C55E)
                                            : const Color(0xFF1D4ED8)),
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Simple status overlay
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 14,
                        child: _SimpleHud(text: statusText),
                      ),

                      if (_isCaptured)
                        Positioned(
                          top: 14,
                          right: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF22C55E),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'Captured',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Steps (simple pills)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _StepPill(
                    label: 'Front',
                    active: step == VerifyStep.front,
                    done: capturedPath[VerifyStep.front] != null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StepPill(
                    label: 'Blink',
                    active: step == VerifyStep.blink,
                    done: capturedPath[VerifyStep.blink] != null,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          if (_isCaptured)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: OutlinedButton(
                onPressed: () async => _retake(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Retake'),
              ),
            )
          else
            const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _SimpleHud extends StatelessWidget {
  final String text;
  const _SimpleHud({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _StepPill extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;

  const _StepPill({
    required this.label,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = active ? const Color(0xFF1D4ED8) : Colors.grey.shade300;
    final bg = done ? const Color(0xFFE7F8F3) : const Color(0xFFF8FAFC);
    final icon = done ? Icons.check_circle : Icons.circle_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: done ? Colors.green : Colors.grey),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
