import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/report_models.dart';
import '../data/reports_api.dart';

class ReportDetailsScreen extends StatefulWidget {
  final String? reportId;

  const ReportDetailsScreen({super.key, this.reportId});

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  ReportRecord? _report;
  bool _loading = true;
  bool _sending = false;
  bool _refreshing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false, bool forceRefresh = false}) async {
    final id = widget.reportId;
    if (id == null || id.isEmpty) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }
    if (!silent && mounted) {
      setState(() => _loading = true);
    }
    try {
      final report = await ReportsApi.instance.fetchReport(
        id,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
      _syncPolling(report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load report: $e')));
    }
  }

  void _syncPolling(ReportRecord report) {
    if (report.status == 'QUEUED') {
      _pollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) {
        _load(silent: true);
      });
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _refreshNow() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _load(silent: true, forceRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report refreshed')));
    } catch (_) {
      // _load already handles toast in error path.
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _sendReport() async {
    final report = _report;
    if (report == null) return;
    setState(() => _sending = true);
    try {
      await ReportsApi.instance.sendReport(report.id);
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report queued for sending')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _resetReport() async {
    final report = _report;
    if (report == null) return;
    setState(() => _sending = true);
    try {
      await ReportsApi.instance.resetReport(report.id);
      await _load(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Report reset to draft')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final report = _report;
    if (report == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Report Details')),
        body: const Center(child: Text('Report not found')),
      );
    }

    final queuedAgeSec = report.status == 'QUEUED'
        ? DateTime.now().difference(report.updatedAt).inSeconds
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Report Details'),
        actions: [
          IconButton(
            onPressed: _refreshing ? null : _refreshNow,
            icon: _refreshing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(report: report),
          if (report.status == 'QUEUED')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                queuedAgeSec > 60
                    ? 'Still queued for ${queuedAgeSec}s. Check worker/Redis if it does not move.'
                    : 'Queued means waiting for background worker.',
                style: const TextStyle(color: Color(0xFFB45309), fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          _SummaryCard(report: report),
          const SizedBox(height: 12),
          _ScanCard(scan: report.scanSummary),
          const SizedBox(height: 12),
          _UserFieldsCard(fields: report.userFields, notes: report.notes),
          const SizedBox(height: 12),
          if (report.manualRequired)
            _ManualCard(instructions: report.policeInstructionsMarkdown),
          if (report.manualRequired) const SizedBox(height: 12),
          _EventsCard(events: report.events),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _sending || report.status == 'QUEUED'
                ? null
                : _sendReport,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send / Retry'),
          ),
          const SizedBox(height: 8),
          if (report.status == 'FAILED')
            OutlinedButton.icon(
              onPressed: _sending ? null : _resetReport,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset to Draft'),
            ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ReportRecord report;

  const _StatusCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(report.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              report.status,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Platform attempts: ${report.attempts.platform}  |  Police attempts: ${report.attempts.police}',
            ),
            if (report.lastError.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Error: ${report.lastError}',
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final ReportRecord report;

  const _SummaryCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report ID: ${report.id}'),
            Text('Country: ${report.countryCode}'),
            Text('Platform: ${report.platform}'),
            SelectableText('URL: ${report.url}'),
            Text('Created: ${report.createdAt}'),
            Text('Updated: ${report.updatedAt}'),
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  final ReportScanSummary scan;

  const _ScanCard({required this.scan});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Scan Summary',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text('Match: ${scan.ok ? 'YES' : 'NO'}'),
            Text('Score: ${(scan.score * 100).toStringAsFixed(2)}%'),
            Text('Threshold: ${(scan.threshold * 100).toStringAsFixed(2)}%'),
            Text('Reason: ${scan.reason.isEmpty ? '-' : scan.reason}'),
            Text(
              'Evidence time: ${scan.evidenceTimeSec.toStringAsFixed(2)} sec',
            ),
            if (scan.evidenceImagePath.isNotEmpty)
              SelectableText('Evidence image path: ${scan.evidenceImagePath}'),
          ],
        ),
      ),
    );
  }
}

class _UserFieldsCard extends StatelessWidget {
  final Map<String, String> fields;
  final String notes;

  const _UserFieldsCard({required this.fields, required this.notes});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'User Fields',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            if (fields.isEmpty)
              const Text('-')
            else
              ...fields.entries.map((e) => Text('${e.key}: ${e.value}')),
            const SizedBox(height: 8),
            const Text('Notes', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(notes.isEmpty ? '-' : notes),
          ],
        ),
      ),
    );
  }
}

class _ManualCard extends StatelessWidget {
  final String instructions;

  const _ManualCard({required this.instructions});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF7ED),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manual Action Required',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            SelectableText(
              instructions.isEmpty
                  ? 'No instructions available.'
                  : instructions,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: instructions.isEmpty
                        ? 'No instructions available.'
                        : instructions,
                  ),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Instructions copied')),
                );
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy Instructions'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventsCard extends StatelessWidget {
  final List<ReportEvent> events;

  const _EventsCard({required this.events});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Audit Log',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            if (events.isEmpty)
              const Text('No events')
            else
              ...events.reversed.map(
                (event) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '[${event.at.toLocal()}] ${event.type}: ${event.message}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'SENT_BOTH':
      return const Color(0xFF16A34A);
    case 'SENT_PLATFORM':
    case 'SENT_POLICE':
      return const Color(0xFF1D4ED8);
    case 'FAILED':
      return const Color(0xFFDC2626);
    case 'MANUAL_REQUIRED':
      return const Color(0xFFF97316);
    case 'QUEUED':
      return const Color(0xFF0EA5E9);
    default:
      return Colors.black87;
  }
}
