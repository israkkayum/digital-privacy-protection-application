import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class EnrollmentSuccessScreen extends StatelessWidget {
  const EnrollmentSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Setup Complete'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                height: 88,
                width: 88,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF16A34A),
                  size: 46,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'You are all set',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                'Your face profile is ready. You can now verify links and submit reports.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black.withOpacity(0.72),
                  height: 1.3,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => context.go('/home'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const SizedBox(
                  width: double.infinity,
                  child: Center(
                    child: Text(
                      'Continue to Home',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
