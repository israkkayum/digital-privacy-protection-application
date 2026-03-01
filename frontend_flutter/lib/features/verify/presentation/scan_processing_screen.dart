import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/scan_service.dart';
import '../data/scan_models.dart';

class ScanProcessingScreen extends StatefulWidget {
  final String? link;
  final String? uploadPath;
  final String sourceType;
  final String? sourceLabel;

  const ScanProcessingScreen({
    super.key,
    this.link,
    this.uploadPath,
    this.sourceType = 'link',
    this.sourceLabel,
  });

  @override
  State<ScanProcessingScreen> createState() => _ScanProcessingScreenState();
}

class _ScanProcessingScreenState extends State<ScanProcessingScreen> {
  final List<_ScanStep> steps = [
    _ScanStep(
      title: 'Preparing media',
      subtitle: 'Downloading or loading video',
    ),
    _ScanStep(
      title: 'Fetching frames',
      subtitle: 'Extracting frames from video',
    ),
    _ScanStep(
      title: 'Detecting faces',
      subtitle: 'Locating faces in each frame',
    ),
    _ScanStep(
      title: 'Generating embeddings',
      subtitle: 'Running server-side face model',
    ),
    _ScanStep(
      title: 'Matching & consent check',
      subtitle: 'Comparing with your encrypted template',
    ),
    _ScanStep(
      title: 'Preparing results',
      subtitle: 'Generating final verification outcome',
    ),
  ];

  int activeIndex = 0;
  double progress = 0.05;
  Timer? timer;
  String? _jobId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      if (widget.sourceType == 'upload') {
        final uploadPath = widget.uploadPath ?? '';
        if (uploadPath.isEmpty) {
          throw Exception('Missing uploaded video path');
        }
        final fileName = widget.sourceLabel ?? uploadPath.split('/').last;
        final job = await ScanService.instance.createUploadJob(
          filePath: uploadPath,
          fileName: fileName,
        );
        _jobId = job.jobId;
      } else {
        final url = widget.link ?? '';
        if (url.isEmpty) {
          throw Exception('Missing link');
        }
        final job = await ScanService.instance.createLinkJob(url: url);
        _jobId = job.jobId;
      }
      await _pollStatus();
      timer = Timer.periodic(const Duration(seconds: 2), (_) => _pollStatus());
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyScanError(e.toString()));
    }
  }

  Future<void> _pollStatus() async {
    final jobId = _jobId;
    if (jobId == null || !mounted) return;

    try {
      final status = await ScanService.instance.fetchStatus(jobId);
      if (!mounted) return;
      _applyStatus(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyScanError(e.toString()));
    }
  }

  void _applyStatus(ScanStatus status) {
    setState(() {
      progress = (status.progress / 100).clamp(0.0, 1.0);
      if (progress >= 0.10) activeIndex = 1;
      if (progress >= 0.28) activeIndex = 2;
      if (progress >= 0.46) activeIndex = 3;
      if (progress >= 0.64) activeIndex = 4;
      if (progress >= 0.82) activeIndex = 5;
    });

    if (status.status == 'done') {
      timer?.cancel();
      final result = status.result;
      final matchFound = result?.ok ?? false;
      final confidence = result?.decisionScore ?? result?.bestScore ?? 0.0;
      final threshold = result?.matchThreshold ?? 0.72;
      final thresholdMode = result?.thresholdMode ?? 'global';
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        context.go(
          '/verify/result',
          extra: {
            'link': widget.link,
            'sourceType': widget.sourceType,
            'sourceLabel':
                widget.sourceLabel ?? widget.link ?? 'Uploaded video',
            'matchFound': matchFound,
            'confidence': confidence,
            'threshold': threshold,
            'thresholdMode': thresholdMode,
            'consentExists': false,
            'reason': result?.reason,
            'scanId': _jobId,
          },
        );
      });
    } else if (status.status == 'failed') {
      timer?.cancel();
      setState(
        () => _error = _friendlyScanError(status.error ?? 'Scan failed'),
      );
    }
  }

  String _friendlyScanError(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('inference_bad_response') ||
        text.contains('interface_bad_response')) {
      return 'Inference service returned an invalid response. Check Python service logs and model path, then retry.';
    }
    if (text.contains('invalid_inference_response')) {
      return 'Inference response format is invalid. Ensure /detect_embed returns { results: [...] }.';
    }
    if (text.contains('inference_connection_refused')) {
      return 'Inference service is offline. Start the Python service on port 8001, then retry.';
    }
    if (text.contains('inference_timeout')) {
      return 'Inference service timed out. Verify Python service is running and not overloaded.';
    }
    if (text.contains('inference_request_failed')) {
      return 'Inference request failed. Check backend and inference service connectivity.';
    }
    if (text.contains('embedding_size_mismatch')) {
      return 'Embedding size mismatch between enrolled template and inference model. Re-enroll after model sync.';
    }
    if (text.contains('inference_batch_mismatch')) {
      return 'Inference batch mismatch. Check /detect_embed implementation for one result per image.';
    }
    if (text.contains('no_face')) {
      return 'No clear face was found in video frames. Try a clearer video or better frontal frames.';
    }
    if (text.contains('private/unsupported')) {
      return 'Facebook link is private or unsupported. Use a public Facebook video URL.';
    }
    if (text.contains('unsupported_platform')) {
      return 'Scan source type is invalid on backend worker. Restart backend + worker and retry.';
    }
    if (text.contains('upload_missing')) {
      return 'Uploaded video file is missing. Please upload again.';
    }
    if (text.contains('video_too_large')) {
      return 'Video file is too large for upload.';
    }
    if (text.contains('unsupported_video_format')) {
      return 'Unsupported video format. Use mp4/mov/m4v/webm.';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final percent = (progress * 100).toStringAsFixed(0);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _Header(percent: percent, onCancel: _cancelScan),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SourceCard(
                    sourceType: widget.sourceType,
                    sourceLabel:
                        widget.sourceLabel ?? widget.link ?? 'Unknown source',
                  ),
                  const SizedBox(height: 12),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFDC2626),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_error!)),
                        ],
                      ),
                    ),
                  _ProgressCard(progress: progress, percent: percent),
                  const SizedBox(height: 14),

                  const Text(
                    'Scan Steps',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),

                  _StepsTimeline(steps: steps, activeIndex: activeIndex),

                  const SizedBox(height: 16),
                  _TipBox(activeIndex: activeIndex),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _cancelScan() {
    timer?.cancel();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel scan?'),
        content: const Text(
          'The current scan will stop and no result will be generated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/verify');
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String percent;
  final VoidCallback onCancel;

  const _Header({required this.percent, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 165,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: Colors.white),
        onPressed: onCancel,
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0F172A), Color(0xFF1D4ED8)],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 44),
                  const Text(
                    'Scanning...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Progress: $percent% • Please keep the app open',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  final String sourceType;
  final String sourceLabel;

  const _SourceCard({required this.sourceType, required this.sourceLabel});

  @override
  Widget build(BuildContext context) {
    final isUpload = sourceType == 'upload';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(
            isUpload ? Icons.upload_file_rounded : Icons.link_rounded,
            color: const Color(0xFF1D4ED8),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sourceLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final double progress;
  final String percent;

  const _ProgressCard({required this.progress, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 54,
            width: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.radar_rounded,
              color: Color(0xFF1D4ED8),
              size: 30,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overall Progress',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF1D4ED8),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$percent%',
                  style: TextStyle(color: Colors.black.withOpacity(0.65)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepsTimeline extends StatelessWidget {
  final List<_ScanStep> steps;
  final int activeIndex;

  const _StepsTimeline({required this.steps, required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: List.generate(steps.length, (i) {
          final step = steps[i];
          final isDone = i < activeIndex;
          final isActive = i == activeIndex;

          final icon = isDone
              ? Icons.check_circle_rounded
              : (isActive ? Icons.timelapse_rounded : Icons.circle_outlined);

          final color = isDone
              ? const Color(0xFF16A34A)
              : (isActive
                    ? const Color(0xFF1D4ED8)
                    : Colors.black.withOpacity(0.35));

          return Padding(
            padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.black.withOpacity(isActive ? 0.9 : 0.8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.subtitle,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.65),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _TipBox extends StatelessWidget {
  final int activeIndex;
  const _TipBox({required this.activeIndex});

  @override
  Widget build(BuildContext context) {
    final tip = switch (activeIndex) {
      0 => 'Tip: Keep this screen open while media is prepared.',
      1 => 'Tip: Higher video quality improves frame extraction.',
      2 => 'Tip: Clear faces (lighting + no heavy blur) improve detection.',
      3 => 'Tip: Server-side embeddings run for every detected face.',
      4 => 'Tip: Match scores are compared with your enrolled template.',
      _ => 'Tip: You can save the result and generate a report if needed.',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_rounded, color: Color(0xFFF97316)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tip,
              style: TextStyle(
                color: Colors.black.withOpacity(0.75),
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanStep {
  final String title;
  final String subtitle;
  const _ScanStep({required this.title, required this.subtitle});
}
