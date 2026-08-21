import 'package:flutter/material.dart';
import '../../widgets/smart_back_button.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';

class SuperAdminSettingsScreen extends StatefulWidget {
  const SuperAdminSettingsScreen({super.key});

  @override
  State<SuperAdminSettingsScreen> createState() => _SuperAdminSettingsScreenState();
}

class _SuperAdminSettingsScreenState extends State<SuperAdminSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  Future<void> _loadCurrentProfile() async {
    final profile = await RoleManagementService.getSuperAdminProfile();
    if (!mounted) return;
    setState(() {
      _username.text = profile['username'] ?? 'superadmin';
      _email.text = profile['email'] ?? 'superadmin@equb.et';
      _password.text = profile['password'] ?? 'admin123';
      _fullName.text = profile['fullName'] ?? 'Super Admin';
      _phone.text = profile['phone'] ?? '+251900000000';
      _address.text = profile['address'] ?? 'Addis Ababa';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final profile = {
      'firstName': _fullName.text.trim().split(' ').first,
      'middleName': '',
      'lastName': _fullName.text.trim().split(' ').length > 1 ? _fullName.text.trim().split(' ').sublist(1).join(' ') : '',
      'fullName': _fullName.text.trim(),
      'username': _username.text.trim(),
      'email': _email.text.trim(),
      'password': _password.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'role': 'super_admin',
    };

    await RoleManagementService.saveSuperAdminProfile(profile);

    final auth = context.read<AuthProvider>();
    auth.refreshUser({
      ...profile,
      'role': 'super_admin',
      'fullName': _fullName.text.trim(),
      'email': _email.text.trim(),
    });

    setState(() => _saving = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Super admin settings updated.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Super Admin Settings'),
        leading: const SmartBackButton(),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _field('Full Name', _fullName, validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 14),
                _field('Username', _username, validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 14),
                _field('Email', _email, type: TextInputType.emailAddress, validator: (v) => (v == null || !v.contains('@')) ? 'Valid email required' : null),
                const SizedBox(height: 14),
                const Text('Password', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  validator: (v) => (v == null || v.length < 6) ? 'Min 6 chars' : null,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _field('Phone', _phone, type: TextInputType.phone),
                const SizedBox(height: 14),
                _field('Address', _address),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Update Settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: type,
          validator: validator ?? (_) => null,
          decoration: InputDecoration(
            prefixIcon: label == 'Address' ? const Icon(Icons.location_on_outlined) : null,
          ),
        ),
      ],
    );
  }
}
