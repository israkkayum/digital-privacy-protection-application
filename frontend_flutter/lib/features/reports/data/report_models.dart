class CountryRequiredField {
  final String key;
  final String label;
  final bool required;

  const CountryRequiredField({
    required this.key,
    required this.label,
    required this.required,
  });

  factory CountryRequiredField.fromJson(Map<String, dynamic> json) {
    return CountryRequiredField(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      required: json['required'] as bool? ?? true,
    );
  }
}

class CountryProfileModel {
  final String countryCode;
  final String countryName;
  final String youtubeEmail;
  final String facebookEmail;
  final String tiktokEmail;
  final String policeContactEmail;
  final String policeInstructionsMarkdown;
  final List<CountryRequiredField> requiredFields;
  final bool isActive;

  const CountryProfileModel({
    required this.countryCode,
    required this.countryName,
    required this.youtubeEmail,
    required this.facebookEmail,
    required this.tiktokEmail,
    required this.policeContactEmail,
    required this.policeInstructionsMarkdown,
    required this.requiredFields,
    required this.isActive,
  });

  factory CountryProfileModel.fromJson(Map<String, dynamic> json) {
    final platformContacts =
        (json['platformContacts'] as Map?)?.cast<String, dynamic>() ?? {};
    final requiredFields = (json['requiredFields'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => CountryRequiredField.fromJson(item.cast<String, dynamic>()),
        )
        .toList();

    return CountryProfileModel(
      countryCode: json['countryCode']?.toString() ?? '',
      countryName: json['countryName']?.toString() ?? '',
      youtubeEmail: platformContacts['youtubeEmail']?.toString() ?? '',
      facebookEmail: platformContacts['facebookEmail']?.toString() ?? '',
      tiktokEmail: platformContacts['tiktokEmail']?.toString() ?? '',
      policeContactEmail: json['policeContactEmail']?.toString() ?? '',
      policeInstructionsMarkdown:
          json['policeInstructionsMarkdown']?.toString() ?? '',
      requiredFields: requiredFields,
      isActive: json['isActive'] as bool? ?? true,
    );
  }
}

class ReportScanSummary {
  final bool ok;
  final double score;
  final double threshold;
  final String reason;
  final String bestPose;
  final double evidenceTimeSec;
  final String evidenceImagePath;

  const ReportScanSummary({
    required this.ok,
    required this.score,
    required this.threshold,
    required this.reason,
    required this.bestPose,
    required this.evidenceTimeSec,
    required this.evidenceImagePath,
  });

  factory ReportScanSummary.fromJson(Map<String, dynamic> json) {
    return ReportScanSummary(
      ok: json['ok'] as bool? ?? false,
      score: (json['score'] as num?)?.toDouble() ?? 0,
      threshold: (json['threshold'] as num?)?.toDouble() ?? 0.72,
      reason: json['reason']?.toString() ?? '',
      bestPose: json['bestPose']?.toString() ?? '',
      evidenceTimeSec: (json['evidenceTimeSec'] as num?)?.toDouble() ?? 0,
      evidenceImagePath: json['evidenceImagePath']?.toString() ?? '',
    );
  }
}

class ReportEvent {
  final DateTime at;
  final String type;
  final String message;

  const ReportEvent({
    required this.at,
    required this.type,
    required this.message,
  });

  factory ReportEvent.fromJson(Map<String, dynamic> json) {
    return ReportEvent(
      at: DateTime.tryParse(json['at']?.toString() ?? '') ?? DateTime.now(),
      type: json['type']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
    );
  }
}

class ReportAttempts {
  final int platform;
  final int police;

  const ReportAttempts({required this.platform, required this.police});

  factory ReportAttempts.fromJson(Map<String, dynamic> json) {
    return ReportAttempts(
      platform: (json['platform'] as num?)?.toInt() ?? 0,
      police: (json['police'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReportRecord {
  final String id;
  final String countryCode;
  final String platform;
  final String url;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? scanId;
  final ReportScanSummary scanSummary;
  final Map<String, String> userFields;
  final String notes;
  final ReportAttempts attempts;
  final String lastError;
  final String packPath;
  final List<ReportEvent> events;
  final bool manualRequired;
  final List<String> manualReasons;
  final String policeInstructionsMarkdown;

  const ReportRecord({
    required this.id,
    required this.countryCode,
    required this.platform,
    required this.url,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.scanId,
    required this.scanSummary,
    required this.userFields,
    required this.notes,
    required this.attempts,
    required this.lastError,
    required this.packPath,
    required this.events,
    required this.manualRequired,
    required this.manualReasons,
    required this.policeInstructionsMarkdown,
  });

  factory ReportRecord.fromJson(Map<String, dynamic> json) {
    final scanSummary =
        (json['scanSummary'] as Map?)?.cast<String, dynamic>() ?? {};
    final attempts = (json['attempts'] as Map?)?.cast<String, dynamic>() ?? {};
    final rawFields =
        (json['userFields'] as Map?)?.cast<String, dynamic>() ?? {};
    final events = (json['events'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => ReportEvent.fromJson(e.cast<String, dynamic>()))
        .toList();

    return ReportRecord(
      id: json['id']?.toString() ?? '',
      countryCode: json['countryCode']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      status: json['status']?.toString() ?? 'DRAFT',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
      scanId: json['scanId']?.toString(),
      scanSummary: ReportScanSummary.fromJson(scanSummary),
      userFields: rawFields.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      notes: json['notes']?.toString() ?? '',
      attempts: ReportAttempts.fromJson(attempts),
      lastError: json['lastError']?.toString() ?? '',
      packPath: json['packPath']?.toString() ?? '',
      events: events,
      manualRequired: json['manualRequired'] as bool? ?? false,
      manualReasons: (json['manualReasons'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      policeInstructionsMarkdown:
          json['policeInstructionsMarkdown']?.toString() ?? '',
    );
  }
}

class ReportListItem {
  final String id;
  final String platform;
  final String url;
  final double score;
  final String status;
  final DateTime date;
  final String countryCode;

  const ReportListItem({
    required this.id,
    required this.platform,
    required this.url,
    required this.score,
    required this.status,
    required this.date,
    required this.countryCode,
  });

  factory ReportListItem.fromJson(Map<String, dynamic> json) {
    return ReportListItem(
      id: json['id']?.toString() ?? '',
      platform: json['platform']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      status: json['status']?.toString() ?? '',
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime.now(),
      countryCode: json['countryCode']?.toString() ?? '',
    );
  }
}
