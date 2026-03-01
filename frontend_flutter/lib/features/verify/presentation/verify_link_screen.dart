import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../core/storage/secure_store.dart';
import '../../reports/data/report_generator.dart';

class VerifyLinkScreen extends StatelessWidget {
  const VerifyLinkScreen({super.key});

  Future<bool> _isEnrolled() async {
    return SecureStore.instance.getBool(SecureStore.keyIsEnrolled);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isEnrolled(),
      builder: (context, snap) {
        final enrolled = snap.data ?? false;

        // Loading
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Not enrolled → show a nice gate screen (not blank)
        if (!enrolled) {
          return _EnrollRequiredView(onEnroll: () => context.go('/enroll'));
        }

        // Enrolled → show the real Verify UI
        return const _VerifyContentUI();
      },
    );
  }
}

class _EnrollRequiredView extends StatelessWidget {
  final VoidCallback onEnroll;
  const _EnrollRequiredView({required this.onEnroll});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            color: const Color(0xFFF8FAFC),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: Color(0xFFFF7A59),
                  size: 34,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Face Enrollment Required',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'To verify Facebook/YouTube/TikTok links, enroll your face once (multi-pose + blink).',
                style: TextStyle(
                  color: Colors.black.withOpacity(0.7),
                  height: 1.25,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onEnroll,
                icon: const Icon(Icons.verified_user_rounded),
                label: const Text('Enroll Now'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1D4ED8),
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerifyContentUI extends StatefulWidget {
  const _VerifyContentUI();

  @override
  State<_VerifyContentUI> createState() => _VerifyContentUIState();
}

class _VerifyContentUIState extends State<_VerifyContentUI> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _openLiveVerify(
    BuildContext context, {
    required String nextRoute,
    required Map<String, dynamic> nextExtra,
  }) async {
    final shouldVerify = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Verify identity'),
        content: const Text(
          'For privacy protection, please verify your face before scanning content.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              final nav = Navigator.of(context, rootNavigator: true);
              if (nav.canPop()) nav.pop(false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final nav = Navigator.of(context, rootNavigator: true);
              if (nav.canPop()) nav.pop(true);
            },
            child: const Text('Verify Now'),
          ),
        ],
      ),
    );

    if (!context.mounted) return;
    if (shouldVerify != true) return;

    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;

    context.go(
      '/verify/live',
      extra: {'next': nextRoute, 'nextExtra': nextExtra},
    );
  }

  Future<void> _startLinkScan(BuildContext context) async {
    final link = controller.text.trim();
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please paste a link to scan.')),
      );
      return;
    }
    final platform = ReportGenerator.detectPlatform(link).toLowerCase();
    if (platform != 'youtube' &&
        platform != 'facebook' &&
        platform != 'tiktok') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Only Facebook, YouTube, and TikTok links are supported.',
          ),
        ),
      );
      return;
    }
    await _openLiveVerify(
      context,
      nextRoute: '/verify/processing',
      nextExtra: {'link': link, 'sourceType': 'link', 'sourceLabel': link},
    );
  }

  Future<void> _startUploadScan(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const ['mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm'],
    );
    if (result == null || result.files.isEmpty) {
      return;
    }

    final file = result.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not read selected video file.')),
      );
      return;
    }

    if (!context.mounted) return;
    await _openLiveVerify(
      context,
      nextRoute: '/verify/processing',
      nextExtra: {
        'uploadPath': path,
        'sourceType': 'upload',
        'sourceLabel': file.name,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Content')),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        children: [
          Text(
            'Paste a link or upload a video',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: Colors.black.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Facebook / YouTube / TikTok link',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _startUploadScan(context),
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Upload'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _startLinkScan(context),
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Scan'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1D4ED8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF1D4ED8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Facebook/YouTube links and uploaded videos are supported. Upload scans run one video at a time.',
                    style: TextStyle(
                      color: Colors.black.withOpacity(0.7),
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
