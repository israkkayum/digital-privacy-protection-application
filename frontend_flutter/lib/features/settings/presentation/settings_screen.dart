import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/secure_store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<String> _countries = [
    'Bangladesh',
    'India',
    'Pakistan',
    'United States',
    'United Kingdom',
  ];

  String _country = AppConstants.defaultCountry;

  @override
  void initState() {
    super.initState();
    _loadCountry();
  }

  Future<void> _loadCountry() async {
    final stored = await SecureStore.instance.getString(SecureStore.keyCountry);
    if (!mounted) return;
    setState(
      () => _country = stored?.isNotEmpty == true
          ? stored!
          : AppConstants.defaultCountry,
    );
  }

  Future<void> _saveCountry(String value) async {
    await SecureStore.instance.setString(SecureStore.keyCountry, value);
    if (!mounted) return;
    setState(() => _country = value);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Country set to $value')));
  }

  Future<void> _logout() async {
    await SecureStore.instance.clearAuthOnly();
    await FirebaseAuth.instance.signOut();
    if (mounted) context.go('/login');
  }

  Future<void> _resetEnrollment() async {
    await SecureStore.instance.clearEnrollment();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enrollment removed from this device')),
    );
  }

  Future<void> _pickCountry() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => ListView(
        shrinkWrap: true,
        children: _countries
            .map(
              (c) => ListTile(
                title: Text(c),
                trailing: c == _country ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, c),
              ),
            )
            .toList(),
      ),
    );

    if (selected != null) {
      await _saveCountry(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'General',
            children: [
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: const Text('Default Country'),
                subtitle: Text('$_country • used in report creation'),
                onTap: _pickCountry,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Account',
            children: [
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: const Text('Logout'),
                subtitle: const Text(
                  'Sign out only. Enrollment stays on this device.',
                ),
                onTap: _logout,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Biometrics',
            children: [
              ListTile(
                leading: const Icon(Icons.delete_forever_rounded),
                title: const Text('Reset Enrollment'),
                subtitle: const Text(
                  'Remove saved face template from this device',
                ),
                onTap: _resetEnrollment,
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
