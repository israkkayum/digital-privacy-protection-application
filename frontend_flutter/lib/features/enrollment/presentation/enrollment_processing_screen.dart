import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/enrollment_processor.dart';
import '../data/template_service.dart';

class EnrollmentProcessingScreen extends StatefulWidget {
  final List<String> posePaths;
  const EnrollmentProcessingScreen({super.key, required this.posePaths});

  @override
  State<EnrollmentProcessingScreen> createState() =>
      _EnrollmentProcessingScreenState();
}

class _EnrollmentProcessingScreenState
    extends State<EnrollmentProcessingScreen> {
  bool _running = true;
  String _status = 'Preparing your face setup...';
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _status = 'Preparing your face setup...';
    });

    try {
      if (widget.posePaths.length != 5) {
        throw Exception('Missing pose images. Please capture all 5 poses.');
      }

      setState(() => _status = 'Checking photo quality...');
      await EnrollmentProcessor.instance.buildAndSaveTemplate(
        poseImagePaths: widget.posePaths,
      );

      setState(() => _status = 'Saving your secure profile...');
      await TemplateService.instance.uploadTemplate();

      if (!mounted) return;
      context.go('/enroll/success');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = _prettyError(e.toString());
        _status = 'Enrollment failed';
      });
    }
  }

  String _prettyError(String raw) {
    return raw
        .replaceFirst('Exception: ', '')
        .replaceFirst('Error: ', '')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finishing Setup'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_running) ...[
                      Container(
                        height: 56,
                        width: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Setting up your face profile',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black.withOpacity(0.72)),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Please keep this screen open.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black.withOpacity(0.56)),
                      ),
                    ] else ...[
                      Container(
                        height: 56,
                        width: 56,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFDC2626),
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Setup could not be completed',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error ?? 'Something went wrong. Please try again.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.72),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => context.go('/enroll/camera'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Retake photos'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _run,
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Try again'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
