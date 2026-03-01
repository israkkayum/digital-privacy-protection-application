import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/live_verify_service.dart';

class LiveVerifyResultScreen extends StatelessWidget {
  final bool isMatch;
  final double score;
  final double threshold;
  final String? reason;
  final int? lockoutUntilMs;
  final String? nextRoute;
  final Object? nextExtra;

  const LiveVerifyResultScreen({
    super.key,
    required this.isMatch,
    required this.score,
    required this.threshold,
    this.reason,
    this.lockoutUntilMs,
    this.nextRoute,
    this.nextExtra,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = isMatch ? Colors.green : Colors.red;
    final statusText = isMatch ? 'Identity verified' : 'Verification failed';
    final message = _friendlyMessage(reason, isMatch);
    final lockoutUntil = lockoutUntilMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lockoutUntilMs!);
    final lockedOut =
        lockoutUntil != null && lockoutUntil.isAfter(DateTime.now());

    return Scaffold(
      appBar: AppBar(title: const Text('Live Verification')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(
                      isMatch
                          ? Icons.check_circle_rounded
                          : Icons.warning_amber_rounded,
                      color: statusColor,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      statusText,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(message, textAlign: TextAlign.center),
                    if (!isMatch && lockedOut) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Too many attempts. Try again after ${lockoutUntil!.toLocal().toString().split('.').first}.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ],
                    const SizedBox(height: 12),
                    _MetricRow(label: 'Score', value: score.toStringAsFixed(3)),
                    _MetricRow(
                      label: 'Threshold',
                      value: threshold.toStringAsFixed(3),
                    ),
                    if (!isMatch && reason != null)
                      _MetricRow(label: 'Reason', value: reason!),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isMatch && nextRoute != null)
              FilledButton(
                onPressed: () => context.go(nextRoute!, extra: nextExtra),
                child: const Text('Continue'),
              ),
            if (!isMatch && !lockedOut)
              FilledButton(
                onPressed: () => context.go(
                  '/verify/live',
                  extra: {'next': nextRoute, 'nextExtra': nextExtra},
                ),
                child: const Text('Try Again'),
              ),
            TextButton(
              onPressed: () => context.go('/verify'),
              child: const Text('Back to Verify'),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyMessage(String? reason, bool ok) {
    if (ok) return 'You can continue to protected actions.';
    switch (reason) {
      case LiveVerifyReason.noTemplate:
        return 'No enrolled template found. Please enroll first.';
      case LiveVerifyReason.poseIncomplete:
        return 'Capture was incomplete. Please try again.';
      case LiveVerifyReason.noFace:
        return 'No face detected. Move closer and try again.';
      case LiveVerifyReason.multipleFaces:
        return 'Multiple faces detected. Only one face should be visible.';
      case LiveVerifyReason.faceTooSmall:
        return 'Face too far away. Move closer to the camera.';
      case LiveVerifyReason.poorLighting:
        return 'Lighting is too low or too bright. Adjust lighting and retry.';
      case LiveVerifyReason.livenessNotSatisfied:
        return 'Liveness check failed. Please blink once and try again.';
      case LiveVerifyReason.lowScore:
        return 'Face match score is below the required threshold.';
      case LiveVerifyReason.embeddingFailed:
      case LiveVerifyReason.fileMissing:
      case LiveVerifyReason.error:
        return 'Verification failed due to an internal error. Please try again.';
      default:
        return 'We could not verify your identity. Please try again.';
    }
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(value),
        ],
      ),
    );
  }
}
