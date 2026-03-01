class ScanJob {
  final String jobId;
  final String status;
  final String? sourceName;

  ScanJob({required this.jobId, required this.status, this.sourceName});

  factory ScanJob.fromJson(Map<String, dynamic> json) {
    return ScanJob(
      jobId: json['jobId'] as String,
      status: json['status'] as String,
      sourceName: json['sourceName'] as String?,
    );
  }
}

class ScanResult {
  final bool ok;
  final double bestScore;
  final double decisionScore;
  final double topKAvgScore;
  final double matchThreshold;
  final String thresholdMode;
  final double bestFrameTime;
  final String? evidenceThumbPath;
  final String? reason;

  ScanResult({
    required this.ok,
    required this.bestScore,
    required this.decisionScore,
    required this.topKAvgScore,
    required this.matchThreshold,
    required this.thresholdMode,
    required this.bestFrameTime,
    this.evidenceThumbPath,
    this.reason,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) {
    return ScanResult(
      ok: json['ok'] as bool? ?? false,
      bestScore: (json['bestScore'] as num?)?.toDouble() ?? 0.0,
      decisionScore:
          (json['decisionScore'] as num?)?.toDouble() ??
          (json['bestScore'] as num?)?.toDouble() ??
          0.0,
      topKAvgScore: (json['topKAvgScore'] as num?)?.toDouble() ?? 0.0,
      matchThreshold: (json['matchThreshold'] as num?)?.toDouble() ?? 0.72,
      thresholdMode: json['thresholdMode'] as String? ?? 'global',
      bestFrameTime: (json['bestFrameTime'] as num?)?.toDouble() ?? 0.0,
      evidenceThumbPath: json['evidenceThumbPath'] as String?,
      reason: json['reason'] as String?,
    );
  }
}

class ScanStatus {
  final String status;
  final int progress;
  final ScanResult? result;
  final String? error;

  ScanStatus({
    required this.status,
    required this.progress,
    this.result,
    this.error,
  });

  factory ScanStatus.fromJson(Map<String, dynamic> json) {
    return ScanStatus(
      status: json['status'] as String? ?? 'queued',
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      result: json['result'] is Map<String, dynamic>
          ? ScanResult.fromJson(json['result'] as Map<String, dynamic>)
          : null,
      error: json['error'] as String?,
    );
  }
}
