import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/storage/secure_store.dart';
import '../data/report_models.dart';
import '../data/reports_api.dart';

class ReportCreateScreen extends StatefulWidget {
  final String? initialPlatform;
  final String? initialUrl;
  final String? initialScanId;
  final double? initialScore;
  final double? initialThreshold;
  final String? initialReason;
  final bool autoSend;

  const ReportCreateScreen({
    super.key,
    this.initialPlatform,
    this.initialUrl,
    this.initialScanId,
    this.initialScore,
    this.initialThreshold,
    this.initialReason,
    this.autoSend = false,
  });

  @override
  State<ReportCreateScreen> createState() => _ReportCreateScreenState();
}

class _ReportCreateScreenState extends State<ReportCreateScreen> {
  final _urlController = TextEditingController();
  final _notesController = TextEditingController();
  final _lawAgencyNameController = TextEditingController();
  final _lawAgencyEmailController = TextEditingController();
  final _lawAgencyPhoneController = TextEditingController();
  final _lawAgencyAddressController = TextEditingController();

  List<CountryProfileModel> _countries = const [];
  CountryProfileModel? _selectedCountry;
  String _platform = 'YOUTUBE';
  final Map<String, TextEditingController> _fieldControllers = {};

  bool _loading = true;
  bool _submitting = false;
  String? _createdReportId;
  String? _countryLoadError;
  String? _entryError;

  static const List<CountryProfileModel> _fallbackCountries = [
    CountryProfileModel(
      countryCode: 'BD',
      countryName: 'Bangladesh',
      youtubeEmail: '',
      facebookEmail: '',
      tiktokEmail: '',
      policeContactEmail: '',
      policeInstructionsMarkdown: 'Manual submission required for Bangladesh.',
      requiredFields: [
        CountryRequiredField(
          key: 'full_name',
          label: 'Full Name',
          required: true,
        ),
        CountryRequiredField(
          key: 'phone',
          label: 'Phone Number',
          required: true,
        ),
      ],
      isActive: true,
    ),
    CountryProfileModel(
      countryCode: 'IN',
      countryName: 'India',
      youtubeEmail: '',
      facebookEmail: '',
      tiktokEmail: '',
      policeContactEmail: '',
      policeInstructionsMarkdown: 'Manual submission guidance.',
      requiredFields: [
        CountryRequiredField(
          key: 'full_name',
          label: 'Full Name',
          required: true,
        ),
        CountryRequiredField(
          key: 'phone',
          label: 'Phone Number',
          required: true,
        ),
      ],
      isActive: true,
    ),
    CountryProfileModel(
      countryCode: 'US',
      countryName: 'United States',
      youtubeEmail: '',
      facebookEmail: '',
      tiktokEmail: '',
      policeContactEmail: '',
      policeInstructionsMarkdown: 'Manual submission guidance.',
      requiredFields: [
        CountryRequiredField(
          key: 'full_name',
          label: 'Full Name',
          required: true,
        ),
        CountryRequiredField(
          key: 'phone',
          label: 'Phone Number',
          required: true,
        ),
      ],
      isActive: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.initialUrl ?? '';
    final p = (widget.initialPlatform ?? '').toUpperCase();
    _platform = (p == 'FACEBOOK' || p == 'YOUTUBE' || p == 'TIKTOK')
        ? p
        : 'YOUTUBE';
    _loadCountries();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _notesController.dispose();
    _lawAgencyNameController.dispose();
    _lawAgencyEmailController.dispose();
    _lawAgencyPhoneController.dispose();
    _lawAgencyAddressController.dispose();
    for (final c in _fieldControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCountries() async {
    if ((widget.initialScanId ?? '').trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _entryError =
            'Manual report creation is disabled. Start from Verify -> Scan -> Report.';
      });
      return;
    }

    try {
      final apiCountries = await ReportsApi.instance.fetchCountries();
      final countries = apiCountries.isEmpty
          ? _fallbackCountries
          : apiCountries;
      final storedCountryRaw = await SecureStore.instance.getString(
        SecureStore.keyCountry,
      );
      final storedCountry = (storedCountryRaw ?? '').trim();

      CountryProfileModel? selected;
      if (storedCountry.isNotEmpty) {
        for (final item in countries) {
          if (item.countryCode.toUpperCase() == storedCountry.toUpperCase() ||
              item.countryName.toLowerCase() == storedCountry.toLowerCase()) {
            selected = item;
            break;
          }
        }
      }
      selected ??= countries.isNotEmpty ? countries.first : null;

      if (!mounted) return;
      setState(() {
        _countries = countries;
        _selectedCountry = selected;
        _loading = false;
        _countryLoadError = apiCountries.isEmpty
            ? 'Country list is empty on server. Using fallback list.'
            : null;
      });
      _rebuildRequiredFields();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _countries = _fallbackCountries;
        _selectedCountry = _fallbackCountries.first;
        _loading = false;
        _countryLoadError =
            'Failed to load countries from server. Using fallback list.';
      });
      _rebuildRequiredFields();
    }
  }

  void _rebuildRequiredFields() {
    final fields = _selectedCountry?.requiredFields ?? const [];
    for (final field in fields) {
      _fieldControllers.putIfAbsent(field.key, () => TextEditingController());
    }
  }

  bool _isUrlValidForPlatform(String rawUrl, String platform) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    if (platform == 'YOUTUBE') {
      return host == 'youtube.com' ||
          host.endsWith('.youtube.com') ||
          host == 'youtu.be';
    }
    if (platform == 'FACEBOOK') {
      return host == 'facebook.com' ||
          host.endsWith('.facebook.com') ||
          host == 'fb.watch';
    }
    if (platform == 'TIKTOK') {
      return host == 'tiktok.com' || host.endsWith('.tiktok.com');
    }
    return false;
  }

  Future<void> _createDraft() async {
    if (_selectedCountry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No country profile available. Seed countries first.'),
        ),
      );
      return;
    }
    final validationError = _validateInputs();
    if (validationError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(validationError)));
      return;
    }

    setState(() => _submitting = true);
    try {
      final userFields = <String, String>{};
      for (final field in _selectedCountry!.requiredFields) {
        userFields[field.key] = _fieldControllers[field.key]?.text.trim() ?? '';
      }
      final lawAgencyName = _lawAgencyNameController.text.trim();
      final lawAgencyEmail = _lawAgencyEmailController.text.trim();
      final lawAgencyPhone = _lawAgencyPhoneController.text.trim();
      final lawAgencyAddress = _lawAgencyAddressController.text.trim();
      if (lawAgencyName.isNotEmpty) {
        userFields['law_agency_name'] = lawAgencyName;
      }
      if (lawAgencyEmail.isNotEmpty) {
        userFields['law_agency_email'] = lawAgencyEmail;
      }
      if (lawAgencyPhone.isNotEmpty) {
        userFields['law_agency_phone'] = lawAgencyPhone;
      }
      if (lawAgencyAddress.isNotEmpty) {
        userFields['law_agency_address'] = lawAgencyAddress;
      }

      final report = await ReportsApi.instance.createReport(
        countryCode: _selectedCountry!.countryCode,
        platform: _platform,
        url: _urlController.text.trim(),
        scanId: widget.initialScanId,
        notes: _notesController.text.trim(),
        userFields: userFields,
      );
      if (!mounted) return;

      setState(() {
        _createdReportId = report.id;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Draft report created')));

      if (widget.autoSend) {
        await _sendReport();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create report: $e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String? _validateInputs() {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) return 'URL is required';
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Enter a valid URL';
    }
    if (!_isUrlValidForPlatform(rawUrl, _platform)) {
      return _platform == 'YOUTUBE'
          ? 'Use a valid YouTube URL'
          : _platform == 'FACEBOOK'
          ? 'Use a valid Facebook URL'
          : 'Use a valid TikTok URL';
    }

    final requiredFields = _selectedCountry?.requiredFields ?? const [];
    for (final field in requiredFields) {
      if (!field.required) continue;
      final value = _fieldControllers[field.key]?.text.trim() ?? '';
      if (value.isEmpty) {
        return '${field.label} is required';
      }
    }
    return null;
  }

  Future<void> _sendReport() async {
    final reportId = _createdReportId;
    if (reportId == null || reportId.isEmpty) return;

    setState(() => _submitting = true);
    try {
      await ReportsApi.instance.sendReport(reportId);
      if (!mounted) return;
      context.go('/reports/details', extra: {'id': reportId});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send report: $e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_entryError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create Report')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_entryError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Create Report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _platform,
            decoration: const InputDecoration(labelText: 'Platform'),
            items: const [
              DropdownMenuItem(value: 'YOUTUBE', child: Text('YouTube')),
              DropdownMenuItem(value: 'FACEBOOK', child: Text('Facebook')),
              DropdownMenuItem(value: 'TIKTOK', child: Text('TikTok')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _platform = value);
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Content URL',
              hintText: 'https://...',
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedCountry?.countryCode,
            decoration: const InputDecoration(labelText: 'Country'),
            items: _countries
                .map(
                  (item) => DropdownMenuItem(
                    value: item.countryCode,
                    child: Text('${item.countryName} (${item.countryCode})'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              final next = _countries
                  .where((c) => c.countryCode == value)
                  .first;
              setState(() => _selectedCountry = next);
              _rebuildRequiredFields();
            },
          ),
          if (_countryLoadError != null) ...[
            const SizedBox(height: 8),
            Text(
              _countryLoadError!,
              style: const TextStyle(color: Color(0xFFB45309), fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          ...(_selectedCountry?.requiredFields ?? const []).map((field) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: _fieldControllers[field.key],
                decoration: InputDecoration(
                  labelText: field.required ? '${field.label} *' : field.label,
                ),
              ),
            );
          }),
          const SizedBox(height: 6),
          const Text(
            'Law Enforcement Contact (optional)',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _lawAgencyNameController,
            decoration: const InputDecoration(labelText: 'Agency name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lawAgencyEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Agency email'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lawAgencyPhoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Agency phone'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lawAgencyAddressController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Agency address'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Any additional details',
            ),
          ),
          if (widget.initialScore != null) ...[
            const SizedBox(height: 14),
            _ScanSummaryBox(
              score: widget.initialScore!,
              threshold: widget.initialThreshold,
              reason: widget.initialReason,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _submitting ? null : _createDraft,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Create Draft'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: (_submitting || _createdReportId == null)
                ? null
                : _sendReport,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Send Report'),
          ),
        ],
      ),
    );
  }
}

class _ScanSummaryBox extends StatelessWidget {
  final double score;
  final double? threshold;
  final String? reason;

  const _ScanSummaryBox({
    required this.score,
    required this.threshold,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Attached Scan Summary',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('Score: ${(score * 100).toStringAsFixed(1)}%'),
          if (threshold != null)
            Text('Threshold: ${(threshold! * 100).toStringAsFixed(1)}%'),
          if ((reason ?? '').isNotEmpty) Text('Reason: ${reason!}'),
        ],
      ),
    );
  }
}
