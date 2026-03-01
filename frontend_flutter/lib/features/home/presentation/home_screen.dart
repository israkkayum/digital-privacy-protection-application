import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/secure_store.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<bool> _loadEnrollment() async {
    return SecureStore.instance.getBool(SecureStore.keyIsEnrolled);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loadEnrollment(),
      builder: (context, snap) {
        final bool isEnrolled = snap.data ?? false;

        return Scaffold(
          appBar: AppBar(title: const Text('Home')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusCard(
                isEnrolled: isEnrolled,
                onEnroll: () => context.go('/enroll'),
              ),
              const SizedBox(height: 18),
              const Text(
                'Actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    _ActionTile(
                      title: 'Enroll Face',
                      subtitle: isEnrolled
                          ? 'Update your template'
                          : 'Multi-pose + blink',
                      icon: Icons.verified_user_rounded,
                      onTap: () => context.go('/enroll'),
                    ),
                    const Divider(height: 1),
                    _ActionTile(
                      title: 'Verify Link',
                      subtitle: 'Scan Facebook / YouTube',
                      icon: Icons.link_rounded,
                      onTap: () {
                        if (!isEnrolled) {
                          _showEnrollRequired(context);
                          return;
                        }
                        context.go('/verify');
                      },
                    ),
                    const Divider(height: 1),
                    _ActionTile(
                      title: 'Consent Camera',
                      subtitle: 'Record with consent',
                      icon: Icons.videocam_rounded,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Consent Camera: coming next'),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    _ActionTile(
                      title: 'Reports',
                      subtitle: 'History & status',
                      icon: Icons.description_rounded,
                      onTap: () => context.go('/reports'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'How it works',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bullet(
                        text: 'Enroll your face once (multi-pose + blink).',
                      ),
                      SizedBox(height: 8),
                      _Bullet(text: 'Paste a link or upload media to scan.'),
                      SizedBox(height: 8),
                      _Bullet(
                        text: 'The app detects faces and checks consent.',
                      ),
                      SizedBox(height: 8),
                      _Bullet(text: 'If unauthorized, generate a report.'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static void _showEnrollRequired(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Enrollment Required'),
        content: const Text(
          'Please enroll your face (multi-pose + blink) once to enable link verification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.go('/enroll');
            },
            child: const Text('Enroll Now'),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool isEnrolled;
  final VoidCallback onEnroll;

  const _StatusCard({required this.isEnrolled, required this.onEnroll});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        leading: Icon(
          isEnrolled ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
          color: isEnrolled ? Colors.green : Colors.orange,
        ),
        title: Text(
          isEnrolled ? 'Enrollment completed' : 'Enrollment required',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          isEnrolled
              ? 'You can verify links and generate reports.'
              : 'Enroll once to activate face verification.',
        ),
        trailing: isEnrolled
            ? null
            : TextButton(onPressed: onEnroll, child: const Text('Enroll')),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 6),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    );
  }
}
