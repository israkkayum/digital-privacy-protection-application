import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/ui/notify.dart';
import '../data/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _firebaseMsg(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Wrong password.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'network-request-failed':
        return 'Network error. Check your internet.';
      default:
        return e.message ?? 'Login failed.';
    }
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    if (email.isEmpty || pass.isEmpty) {
      Notify.error(context, 'Email and password are required');
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService.instance.login(email, pass);
      if (mounted) Notify.success(context, 'Login successful');
      // ✅ Router redirect will handle next route
    } on FirebaseAuthException catch (e) {
      if (mounted) Notify.error(context, _firebaseMsg(e));
    } catch (_) {
      if (mounted) Notify.error(context, 'Login failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await AuthService.instance.signInWithGoogle();

      // user canceled
      if (AuthService.instance.user == null) {
        if (mounted) Notify.info(context, 'Google sign-in cancelled');
        return;
      }

      if (mounted) Notify.success(context, 'Signed in with Google');
      // ✅ Router redirect will handle next route
    } catch (_) {
      if (mounted) Notify.error(context, 'Google sign-in failed');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _loading || _googleLoading;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const _LoginHeader(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Login
                  FilledButton(
                    onPressed: disabled ? null : _login,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1D4ED8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: Center(
                        child: _loading
                            ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                            : const Text('Login', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Forgot password
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: disabled ? null : () => context.go('/forgot-password'),
                      child: const Text('Forgot password?', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // OR divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.black.withOpacity(0.12))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: Colors.black.withOpacity(0.55),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.black.withOpacity(0.12))),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Google
                  OutlinedButton(
                    onPressed: disabled ? null : _loginWithGoogle,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      backgroundColor: Colors.white,
                      side: BorderSide(color: Colors.black.withOpacity(0.12)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: const Center(
                            child: Text('G', style: TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Center(
                            child: _googleLoading
                                ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : const Text(
                              'Continue with Google',
                              style: TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
                            ),
                          ),
                        ),
                        const SizedBox(width: 22),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('New here?', style: TextStyle(color: Colors.black.withOpacity(0.65))),
                      TextButton(
                        onPressed: disabled ? null : () => context.go('/register'),
                        child: const Text('Create account', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 200,
      backgroundColor: Colors.transparent,
      elevation: 0,
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
                  const SizedBox(height: 56),
                  const Text(
                    'Welcome Back',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Login to continue DPPA.',
                    style: TextStyle(color: Colors.white.withOpacity(0.9)),
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