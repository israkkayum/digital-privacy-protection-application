import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../data/live_verify_service.dart';
import '../data/verify_session_store.dart';

class LiveVerifyProcessingScreen extends StatefulWidget {
  final List<String> posePaths;
  final bool blinkOk;
  final String? nextRoute;
  final Object? nextExtra;

  const LiveVerifyProcessingScreen({
    super.key,
    required this.posePaths,
    this.blinkOk = true,
    this.nextRoute,
    this.nextExtra,
  });

  @override
  State<LiveVerifyProcessingScreen> createState() => _LiveVerifyProcessingScreenState();
}

class _LiveVerifyProcessingScreenState extends State<LiveVerifyProcessingScreen> {
  String status = 'Verifying face...';
  bool hasError = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      LiveVerifyResult result;

      if (!widget.blinkOk) {
        result = LiveVerifyResult.fail(
          reason: LiveVerifyReason.livenessNotSatisfied,
          threshold: LiveVerifyService.instance.threshold,
        );
      } else {
        result = await LiveVerifyService.instance.verifyFromPoseImages(widget.posePaths);
      }

      if (!mounted) return;

      final store = VerifySessionStore.instance;
      DateTime? lockoutUntil;
      final priorFails = await store.getFailCount();
      if (result.ok) {
        await store.registerSuccess();
      } else {
        lockoutUntil = await store.registerFailure();
      }

      final userId = FirebaseAuth.instance.currentUser?.uid ?? FirebaseAuth.instance.currentUser?.email;
      final retries = result.ok ? 0 : priorFails + 1;
      await store.addLog(
        VerifyLogEntry(
          timestamp: DateTime.now(),
          score: result.score,
          ok: result.ok,
          reason: result.reason,
          retries: retries,
          userId: userId,
          device: Platform.operatingSystem,
        ),
      );

      context.go(
        '/verify/live/result',
        extra: {
          'isMatch': result.ok,
          'score': result.score,
          'threshold': result.threshold,
          'reason': result.reason,
          'lockoutUntilMs': lockoutUntil?.millisecondsSinceEpoch,
          'next': widget.nextRoute,
          'nextExtra': widget.nextExtra,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        status = 'Verification failed: $e';
        hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!hasError) const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(status, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900)),
              if (hasError) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.go(
                    '/verify/live',
                    extra: {
                      'next': widget.nextRoute,
                      'nextExtra': widget.nextExtra,
                    },
                  ),
                  child: const Text('Try Again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => context.go('/verify'),
                  child: const Text('Back to Verify'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
