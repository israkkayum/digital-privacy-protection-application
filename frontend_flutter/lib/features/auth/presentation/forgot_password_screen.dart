import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/ui/notify.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      Notify.error(context, 'Email is required');
      return;
    }

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      Notify.success(context, 'Reset email sent. Check inbox/spam.');

      // ✅ safe navigation
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/login');
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      final msg = switch (e.code) {
        'invalid-email' => 'Invalid email format.',
        'user-not-found' => 'No account exists with this email.',
        'network-request-failed' => 'No internet / network error.',
        'too-many-requests' => 'Too many requests. Try again later.',
        'operation-not-allowed' => 'Password reset is disabled in Firebase console.',
        _ => (e.message ?? 'Failed to send reset email.'),
      };

      Notify.error(context, '$msg (${e.code})');
    } catch (e) {
      if (!mounted) return;
      Notify.error(context, 'Failed to send reset email.');
      // ignore: avoid_print
      print('RESET ERROR (unknown): $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your email. We will send a password reset link.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loading ? null : _sendReset,
              child: _loading
                  ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Text('Send reset email'),
            ),
          ],
        ),
      ),
    );
  }
}