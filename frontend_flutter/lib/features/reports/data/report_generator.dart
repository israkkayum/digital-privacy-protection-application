import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/constants/app_constants.dart';
import 'report_store.dart';

class ReportGenerator {
  static String detectPlatform(String url) {
    final u = url.toLowerCase();
    if (u.contains('facebook') || u.contains('fb.com') || u.contains('fbcdn')) {
      return 'Facebook';
    }
    if (u.contains('tiktok.com')) return 'TikTok';
    if (u.contains('youtube') || u.contains('youtu.be')) return 'YouTube';
    return 'Other';
  }

  static ReportItem buildReport({
    required String url,
    required double score,
    String? country,
  }) {
    final platform = detectPlatform(url);
    final createdAt = DateTime.now();
    final id = 'r_${createdAt.millisecondsSinceEpoch}';
    final user = FirebaseAuth.instance.currentUser;
    final userId = user?.email ?? user?.uid ?? 'Unknown';
    final c = country ?? AppConstants.defaultCountry;

    final text = _generateText(
      platform: platform,
      url: url,
      score: score,
      country: c,
      userId: userId,
      createdAt: createdAt,
    );

    return ReportItem(
      id: id,
      platform: platform,
      url: url,
      status: ReportStatus.draft,
      matchScore: score,
      createdAt: createdAt,
      country: c,
      reportText: text,
    );
  }

  static String _generateText({
    required String platform,
    required String url,
    required double score,
    required String country,
    required String userId,
    required DateTime createdAt,
  }) {
    final percent = (score * 100).toStringAsFixed(1);
    final time = createdAt.toLocal().toString().split('.').first;

    return '''Subject: Request for Removal of Unauthorized Content (Privacy Violation)

To $platform Support Team,

I am requesting the removal of content that includes my face without my consent. This upload violates my personal privacy rights.

Content Link:
$url

Detection Evidence:
- Face match confidence: $percent%
- Detection time: $time
- User ID: $userId

I confirm that I did not authorize my appearance in this content. Please review and remove the content and take necessary action according to your platform policy.

Sincerely,
[Your Name]
[Your Contact Email]

---

Local Authority Report ($country)

To the relevant cyber crime unit / police authority in $country,

I am reporting a privacy violation where my face appears in online content without my consent. The content is hosted on $platform.

Evidence:
- Content link: $url
- Face match confidence: $percent%
- Detection time: $time
- User ID: $userId

I request an investigation and necessary action as per local law.

Sincerely,
[Your Name]
[Your Contact Email]
''';
  }
}
