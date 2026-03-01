import 'dart:convert';

import '../../../core/storage/secure_store.dart';

enum ReportStatus { draft, submitted, resolved }

extension ReportStatusLabel on ReportStatus {
  String get label {
    switch (this) {
      case ReportStatus.draft:
        return 'Draft';
      case ReportStatus.submitted:
        return 'Submitted';
      case ReportStatus.resolved:
        return 'Resolved';
    }
  }

  static ReportStatus fromLabel(String value) {
    switch (value) {
      case 'Submitted':
        return ReportStatus.submitted;
      case 'Resolved':
        return ReportStatus.resolved;
      case 'Draft':
      default:
        return ReportStatus.draft;
    }
  }
}

extension ReportStatusColor on ReportStatus {
  int get colorValue {
    switch (this) {
      case ReportStatus.draft:
        return 0xFFF97316;
      case ReportStatus.submitted:
        return 0xFF1D4ED8;
      case ReportStatus.resolved:
        return 0xFF16A34A;
    }
  }
}

class ReportItem {
  final String id;
  final String platform;
  final String url;
  final ReportStatus status;
  final double matchScore;
  final DateTime createdAt;
  final String country;
  final String reportText;

  const ReportItem({
    required this.id,
    required this.platform,
    required this.url,
    required this.status,
    required this.matchScore,
    required this.createdAt,
    required this.country,
    required this.reportText,
  });

  ReportItem copyWith({ReportStatus? status}) {
    return ReportItem(
      id: id,
      platform: platform,
      url: url,
      status: status ?? this.status,
      matchScore: matchScore,
      createdAt: createdAt,
      country: country,
      reportText: reportText,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform,
    'url': url,
    'status': status.label,
    'matchScore': matchScore,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'country': country,
    'reportText': reportText,
  };

  static ReportItem fromJson(Map<String, dynamic> json) {
    return ReportItem(
      id: json['id'] as String,
      platform: json['platform'] as String,
      url: json['url'] as String,
      status: ReportStatusLabel.fromLabel(json['status'] as String? ?? 'Draft'),
      matchScore: (json['matchScore'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int? ?? 0,
      ),
      country: json['country'] as String? ?? 'Bangladesh',
      reportText: json['reportText'] as String? ?? '',
    );
  }
}

class ReportStore {
  ReportStore._();
  static final ReportStore instance = ReportStore._();

  static const String _keyReports = 'reports_v1';

  Future<List<ReportItem>> getAll() async {
    final raw = await SecureStore.instance.getString(_keyReports);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final list = <ReportItem>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          list.add(ReportItem.fromJson(item));
        } else if (item is Map) {
          list.add(ReportItem.fromJson(item.cast<String, dynamic>()));
        }
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<ReportItem?> getById(String id) async {
    final list = await getAll();
    for (final item in list) {
      if (item.id == id) return item;
    }
    return null;
  }

  Future<void> saveAll(List<ReportItem> list) async {
    final encoded = jsonEncode(list.map((e) => e.toJson()).toList());
    await SecureStore.instance.setString(_keyReports, encoded);
  }

  Future<void> add(ReportItem item) async {
    final list = await getAll();
    list.insert(0, item);
    await saveAll(list);
  }

  Future<void> updateStatus(String id, ReportStatus status) async {
    final list = await getAll();
    final updated = list
        .map((e) => e.id == id ? e.copyWith(status: status) : e)
        .toList();
    await saveAll(updated);
  }
}
