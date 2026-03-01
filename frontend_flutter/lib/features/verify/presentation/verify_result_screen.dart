import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../reports/data/report_generator.dart';

class VerifyResultScreen extends StatelessWidget {
  final String? link;
  final String sourceType;
  final String? sourceLabel;
  final bool matchFound;
  final double confidence;
  final double threshold;
  final String thresholdMode;
  final bool consentExists;
  final String? reason;
  final String? scanId;

  const VerifyResultScreen({
    super.key,
    this.link,
    this.sourceType = 'link',
    this.sourceLabel,
    this.matchFound = false,
    this.confidence = 0.0,
    this.threshold = 0.72,
    this.thresholdMode = 'global',
    this.consentExists = false,
    this.reason,
    this.scanId,
  });

  @override
  Widget build(BuildContext context) {
    final sourceValue =
        sourceLabel ??
        link ??
        (sourceType == 'upload' ? 'Uploaded video' : 'Link not provided');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _ResultHeader(matchFound: matchFound),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _MainResultCard(
                    matchFound: matchFound,
                    confidence: confidence,
                    threshold: threshold,
                    thresholdMode: thresholdMode,
                    consentExists: consentExists,
                  ),
                  const SizedBox(height: 14),

                  const Text(
                    'Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),

                  _DetailTile(
                    icon: sourceType == 'upload'
                        ? Icons.upload_file_rounded
                        : Icons.link_rounded,
                    title: 'Source',
                    value: sourceValue,
                  ),
                  const SizedBox(height: 10),
                  _DetailTile(
                    icon: Icons.schedule_rounded,
                    title: 'Scan Duration',
                    value: 'See progress details in scan screen',
                  ),
                  const SizedBox(height: 10),
                  if (reason != null && reason!.isNotEmpty) ...[
                    _DetailTile(
                      icon: Icons.info_outline_rounded,
                      title: 'Reason',
                      value: reason!,
                    ),
                    const SizedBox(height: 10),
                  ],
                  _DetailTile(
                    icon: Icons.security_rounded,
                    title: 'Privacy',
                    value: 'No raw face images stored. Template is encrypted.',
                  ),
                  if (sourceType == 'upload') ...[
                    const SizedBox(height: 10),
                    _DetailTile(
                      icon: Icons.info_outline_rounded,
                      title: 'Reporting',
                      value:
                          'For uploaded videos, choose report platform and optionally add the public link.',
                    ),
                  ],

                  const SizedBox(height: 18),

                  _ActionBar(
                    matchFound: matchFound,
                    consentExists: consentExists,
                    onBack: () => context.go('/verify'),
                    onReport: () async {
                      await _openReportCreate(context, autoSend: true);
                    },
                    onSave: () async {
                      await _openReportCreate(context, autoSend: false);
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openReportCreate(
    BuildContext context, {
    required bool autoSend,
  }) async {
    if (!matchFound) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No match found. Report not created.')),
      );
      return;
    }

    String? platform;
    String? reportUrl;
    final sourceLink = link?.trim() ?? '';
    if (sourceType == 'link' && sourceLink.isNotEmpty) {
      final detected = ReportGenerator.detectPlatform(sourceLink).toLowerCase();
      if (detected == 'facebook') {
        platform = 'FACEBOOK';
        reportUrl = sourceLink;
      } else if (detected == 'youtube') {
        platform = 'YOUTUBE';
        reportUrl = sourceLink;
      } else if (detected == 'tiktok') {
        platform = 'TIKTOK';
        reportUrl = sourceLink;
      }
    }

    if (!context.mounted) return;
    context.go(
      '/reports/create',
      extra: {
        'platform': platform,
        'url': reportUrl,
        'scanId': scanId,
        'score': confidence,
        'threshold': threshold,
        'reason': reason,
        'autoSend': autoSend,
      },
    );
  }
}

class _ResultHeader extends StatelessWidget {
  final bool matchFound;
  const _ResultHeader({required this.matchFound});

  @override
  Widget build(BuildContext context) {
    final gradient = matchFound
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFFDC2626)], // dark → red
          )
        : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F172A), Color(0xFF22C55E)], // dark → green
          );

    return SliverAppBar(
      pinned: true,
      expandedHeight: 170,
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(gradient: gradient),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 42),
                  Text(
                    matchFound
                        ? 'Privacy Risk Detected'
                        : 'No Violation Detected',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    matchFound
                        ? 'Your face may appear in this content without consent.'
                        : 'No matching face found in the scanned content.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      height: 1.25,
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

class _MainResultCard extends StatelessWidget {
  final bool matchFound;
  final double confidence;
  final double threshold;
  final String thresholdMode;
  final bool consentExists;

  const _MainResultCard({
    required this.matchFound,
    required this.confidence,
    required this.threshold,
    required this.thresholdMode,
    required this.consentExists,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = matchFound
        ? const Color(0xFFDC2626)
        : const Color(0xFF16A34A);
    final statusBg = matchFound
        ? const Color(0xFFFFE4E6)
        : const Color(0xFFDCFCE7);

    final consentColor = consentExists
        ? const Color(0xFF16A34A)
        : const Color(0xFFDC2626);
    final consentText = consentExists
        ? 'Consent Found (Authorized)'
        : 'No Consent Found (Unauthorized)';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status row
          Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  matchFound
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_rounded,
                  color: statusColor,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  matchFound ? 'Match Found' : 'No Match',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  matchFound ? 'ALERT' : 'SAFE',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Confidence
          const Text(
            'Confidence Score',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: confidence.clamp(0, 1),
              minHeight: 10,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(confidence * 100).toStringAsFixed(1)}% similarity',
            style: TextStyle(color: Colors.black.withOpacity(0.65)),
          ),
          if (!matchFound) ...[
            const SizedBox(height: 4),
            Text(
              'Required threshold: ${(threshold * 100).toStringAsFixed(1)}%',
              style: TextStyle(color: Colors.black.withOpacity(0.65)),
            ),
            const SizedBox(height: 2),
            Text(
              'Threshold mode: $thresholdMode',
              style: TextStyle(
                color: Colors.black.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Consent section
          Row(
            children: [
              Icon(Icons.verified_rounded, color: consentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  consentText,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: consentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            consentExists
                ? 'This content is already approved in your consent log.'
                : 'You can generate a report to request removal/takedown.',
            style: TextStyle(
              color: Colors.black.withOpacity(0.7),
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _DetailTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, color: const Color(0xFF1D4ED8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(color: Colors.black.withOpacity(0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final bool matchFound;
  final bool consentExists;
  final VoidCallback onBack;
  final VoidCallback onSave;
  final VoidCallback onReport;

  const _ActionBar({
    required this.matchFound,
    required this.consentExists,
    required this.onBack,
    required this.onSave,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final bool canReport = matchFound && !consentExists;
    final bool canSave = matchFound;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: canSave ? onSave : null,
            icon: const Icon(Icons.bookmark_add_rounded),
            label: const Text('Save'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: canReport ? onReport : null,
            icon: const Icon(Icons.report_rounded),
            label: const Text('Report'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
