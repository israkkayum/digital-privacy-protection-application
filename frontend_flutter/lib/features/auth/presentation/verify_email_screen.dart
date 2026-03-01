import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ui/notify.dart';
import '../data/auth_service.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  Timer? timer;
  bool sending = false;

  @override
  void initState() {
    super.initState();
    _startAutoCheck();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void _startAutoCheck() {
    timer = Timer.periodic(const Duration(seconds: 3), (_) async {
      await AuthService.instance.reloadUser();
      final verified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
      if (verified && mounted) {
        timer?.cancel();
        // router redirect will move forward
        context.go('/home');
      }
    });
  }

  Future<void> _resend() async {
    setState(() => sending = true);
    try {
      await AuthService.instance.sendEmailVerification();
      if (mounted) Notify.success(context, 'Verification email sent.');
    } catch (e) {
      if (mounted) Notify.error(context, 'Failed to send email.');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Email'),
        actions: [
          TextButton(onPressed: _logout, child: const Text('Logout')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Check your inbox',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              'We sent a verification link to:',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 6),
            Text(email, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            const Text(
              'After verifying, return here. We’ll auto-detect and continue.',
              style: TextStyle(height: 1.3),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: sending ? null : _resend,
              icon: const Icon(Icons.email),
              label: Text(sending ? 'Sending...' : 'Resend Email'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await AuthService.instance.reloadUser();
                final verified = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
                if (verified) {
                  if (mounted) context.go('/home');
                } else {
                  if (mounted) Notify.info(context, 'Not verified yet.');
                }
              },
              icon: const Icon(Icons.refresh),
              label: const Text('I verified, refresh'),
            ),
          ],
        ),
      ),
    );
  }
}