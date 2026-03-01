import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/ui/notify.dart';
import '../data/auth_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;
  bool _googleLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String _firebaseMsg(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'This email is already in use.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'network-request-failed':
        return 'Network error. Check your internet.';
      default:
        return e.message ?? 'Registration failed.';
    }
  }

  Future<void> _register() async {
    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (name.isEmpty || email.isEmpty || pass.isEmpty || confirm.isEmpty) {
      Notify.error(context, 'All fields are required');
      return;
    }
    if (pass != confirm) {
      Notify.error(context, 'Passwords do not match');
      return;
    }
    if (pass.length < 6) {
      Notify.error(context, 'Password must be at least 6 characters');
      return;
    }

    setState(() => _loading = true);
    try {
      await AuthService.instance.register(email, pass, displayName: name);
      if (mounted) Notify.success(context, 'Account created! Verify your email.');
      // ✅ Router redirect will go to /verify-email
    } on FirebaseAuthException catch (e) {
      if (mounted) Notify.error(context, _firebaseMsg(e));
    } catch (_) {
      if (mounted) Notify.error(context, 'Registration failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() => _googleLoading = true);
    try {
      await AuthService.instance.signInWithGoogle();

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
          const _RegisterHeader(),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  _InputField(controller: _nameCtrl, label: 'Full Name', icon: Icons.person_outline),
                  const SizedBox(height: 12),
                  _InputField(controller: _emailCtrl, label: 'Email', icon: Icons.email_outlined),
                  const SizedBox(height: 12),

                  _InputField(
                    controller: _passCtrl,
                    label: 'Password',
                    icon: Icons.lock_outline,
                    obscure: _obscure,
                    suffix: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InputField(
                    controller: _confirmCtrl,
                    label: 'Confirm Password',
                    icon: Icons.lock_outline,
                    obscure: _obscure,
                  ),

                  const SizedBox(height: 18),

                  FilledButton(
                    onPressed: disabled ? null : _register,
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
                            : const Text('Create Account', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

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

                  OutlinedButton(
                    onPressed: disabled ? null : _googleSignIn,
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
                      Text('Already have an account?', style: TextStyle(color: Colors.black.withOpacity(0.65))),
                      TextButton(
                        onPressed: disabled ? null : () => context.go('/login'),
                        child: const Text('Login', style: TextStyle(fontWeight: FontWeight.w900)),
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

class _RegisterHeader extends StatelessWidget {
  const _RegisterHeader();

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 200,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
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
                  const SizedBox(height: 48),
                  const Text(
                    'Create Account',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Join DPPA to protect your privacy online.',
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

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final Widget? suffix;

  const _InputField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}