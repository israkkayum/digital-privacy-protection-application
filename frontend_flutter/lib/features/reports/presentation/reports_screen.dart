import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/report_models.dart';
import '../data/reports_api.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<ReportListItem> _items = const [];
  String? _error;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _loadReports(showLoader: true);
  }

  Future<void> _loadReports({
    required bool showLoader,
    bool showSnack = false,
  }) async {
    if (_refreshing) return;
    setState(() {
      _refreshing = true;
      if (showLoader) _loading = true;
    });

    try {
      final reports = await ReportsApi.instance.fetchReports(
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() {
        _items = reports;
        _error = null;
        _loading = false;
      });
      if (showSnack) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Reports refreshed')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
      if (showSnack) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _refresh() async {
    await _loadReports(showLoader: false, showSnack: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            onPressed: _refreshing
                ? null
                : () {
                    _refresh();
                  },
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                children: [
                  if (_error != null && _items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Column(
                        children: [
                          Text(
                            'Failed to load reports: $_error',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _refreshing
                                ? null
                                : () {
                                    _loadReports(
                                      showLoader: true,
                                      showSnack: true,
                                    );
                                  },
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  else if (_items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: Text('No reports yet')),
                    )
                  else ...[
                    _TableHeader(),
                    const Divider(height: 1),
                    ..._items.map(
                      (item) => _ReportRow(
                        item: item,
                        onTap: () => context.go(
                          '/reports/details',
                          extra: {'id': item.id},
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              'Platform',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('Score', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Status',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text('Date', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final ReportListItem item;
  final VoidCallback onTap;

  const _ReportRow({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(item.platform)),
            Expanded(
              flex: 2,
              child: Text('${(item.score * 100).toStringAsFixed(1)}%'),
            ),
            Expanded(
              flex: 3,
              child: Text(
                item.status,
                style: TextStyle(
                  color: _statusColor(item.status),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                '${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}',
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
