import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';
import '../../services/role_management_service.dart';
import '../../services/firestore_direct_service.dart';
import '../../widgets/smart_back_button.dart';

/// Used for both CREATE (editData == null) and EDIT (editData != null) modes.
/// Route extra: Map<String,dynamic>? adminData
class SuperAdminAdminFormScreen extends StatefulWidget {
  final Map<String, dynamic>? editData;

  const SuperAdminAdminFormScreen({super.key, this.editData});

  @override
  State<SuperAdminAdminFormScreen> createState() =>
      _SuperAdminAdminFormScreenState();
}

class _SuperAdminAdminFormScreenState extends State<SuperAdminAdminFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // controllers
  late final TextEditingController _firstName;
  late final TextEditingController _middleName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _confirmPassword;
  late final TextEditingController _phone;
  late final TextEditingController _altPhone;
  late final TextEditingController _address;
  late final TextEditingController _city;
  late final TextEditingController _region;
  late final TextEditingController _emergencyContact;
  late final TextEditingController _emergencyPhone;

  String _selectedLevel = 'low';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  bool _isAmharic = false;
  bool get _isEdit => widget.editData != null;

  String t(String en, String am) => _isAmharic ? am : en;

  @override
  void initState() {
    super.initState();
    final d = widget.editData ?? {};
    final contact = (d['contactInfo'] as Map<String, dynamic>?) ?? {};

    _firstName = TextEditingController(text: d['firstName'] ?? '');
    _middleName = TextEditingController(text: d['middleName'] ?? '');
    _lastName = TextEditingController(text: d['lastName'] ?? '');
    _email = TextEditingController(text: d['email'] ?? '');
    _username = TextEditingController(text: d['username'] ?? '');
    _password = TextEditingController();
    _confirmPassword = TextEditingController();
    _phone =
        TextEditingController(text: d['phone'] ?? contact['phoneNumber'] ?? '');
    _altPhone = TextEditingController(text: contact['alternatePhone'] ?? '');
    _address =
        TextEditingController(text: d['address'] ?? contact['address'] ?? '');
    _city = TextEditingController(text: contact['city'] ?? '');
    _region = TextEditingController(text: contact['region'] ?? '');
    _emergencyContact =
        TextEditingController(text: contact['emergencyContact'] ?? '');
    _emergencyPhone =
        TextEditingController(text: contact['emergencyPhone'] ?? '');
    _selectedLevel = d['level'] ?? 'low';
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _middleName,
      _lastName,
      _email,
      _username,
      _password,
      _confirmPassword,
      _phone,
      _altPhone,
      _address,
      _city,
      _region,
      _emergencyContact,
      _emergencyPhone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── submit ────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final email = _email.text.trim().toLowerCase();
    final password =
        _password.text.isNotEmpty ? _password.text : 'admin123';

    final payload = <String, dynamic>{
      'firstName': _firstName.text.trim(),
      'middleName': _middleName.text.trim(),
      'lastName': _lastName.text.trim(),
      'email': email,
      'username': _username.text.trim().isEmpty
          ? email.split('@').first
          : _username.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'level': _selectedLevel,
      'equbLevel': _selectedLevel,
      'password': password,
      'contactInfo': {
        'phoneNumber': _phone.text.trim(),
        'alternatePhone': _altPhone.text.trim(),
        'address': _address.text.trim(),
        'city': _city.text.trim(),
        'region': _region.text.trim(),
        'emergencyContact': _emergencyContact.text.trim(),
        'emergencyPhone': _emergencyPhone.text.trim(),
      },
    };

    bool ok = false;
    String? errorMsg;
    String? successMsg;

    if (_isEdit) {
      // ── EDIT: update Firestore admin document ──────────────────────────
      ok = await RoleManagementService.updateAdmin(
        (widget.editData?['adminId'] ?? widget.editData?['id'] ?? '').toString(),
        payload,
      );
      errorMsg = t('Failed to update admin.', 'አስተዳዳሪ ሊሻሻል አልቻለም።');
      successMsg = t('Admin updated successfully.', 'አስተዳዳሪ ተሻሽሏል።');
    } else {
      // ── CREATE: write to Firestore admins collection first ─────────────
      final res = await RoleManagementService.createAdminResult(payload);
      ok = res['success'] == true;

      if (ok) {
        final firestoreDocId = (res['id'] ?? '').toString();
        successMsg = res['message'] ??
            t('Admin assigned successfully.', 'አስተዳዳሪ ተመድቧል።');

        // Firebase Auth disabled — patch password into Firestore doc so login works
        if (firestoreDocId.isNotEmpty && password.isNotEmpty) {
          try {
            await FirestoreDirectService.updateDocument('admins', firestoreDocId, {
              'password': password,
              'updatedAt': DateTime.now().toUtc().toIso8601String(),
            });
          } catch (_) {}
        }
      } else {
        errorMsg =
            res['error'] ?? t('Failed to assign admin.', 'አስተዳዳሪውን መመደብ አልተቻለም።');
      }
    }

    setState(() => _saving = false);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(successMsg ??
            t('Admin saved successfully.', 'አስተዳዳሪው በተሳካ ሁኔታ ተስቀምጧል።')),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 3),
      ));
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            errorMsg ?? t('Failed to process request.', 'ጥያቄውን ማከናወን አልተቻለም።')),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 4),
      ));
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? t('Edit Admin', 'አስተዳዳሪ አርትዕ')
            : t('Assign Admin', 'አስተዳዳሪ መድብ')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        leading: const SmartBackButton(color: Colors.white),
        actions: [
          IconButton(
            icon: Text(
              _isAmharic ? 'EN' : 'አማ',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13),
            ),
            onPressed: () => setState(() => _isAmharic = !_isAmharic),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              // ── header card ───────────────────────────────────────────────
              _sectionCard(
                icon: Icons.person,
                title: t('Personal Information', 'የግል መረጃ'),
                color: AppColors.primary,
                children: [
                  _row([
                    _field(t('First Name *', 'ስም *'), _firstName,
                        hint: t('Abebe', 'አበበ'), validator: _required),
                    _field(t('Middle Name', 'የአባት ስም'), _middleName,
                        hint: t('Bekele', 'በቀለ')),
                  ]),
                  const SizedBox(height: 12),
                  _field(t('Last Name *', 'የአያት ስም *'), _lastName,
                      hint: t('Alemu', 'አለሙ'), validator: _required),
                ],
              ),
              const SizedBox(height: 16),

              // ── account ───────────────────────────────────────────────────
              _sectionCard(
                icon: Icons.lock_outline,
                title: t('Account Information', 'የመለያ መረጃ'),
                color: AppColors.secondary,
                children: [
                  _field(t('Email Address *', 'ኢሜይል *'), _email,
                      hint: 'admin@equb.et',
                      type: TextInputType.emailAddress,
                      enabled: !_isEdit, validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return t('Email required', 'ኢሜይል ያስፈልጋል');
                    }
                    if (!v.contains('@')) {
                      return t('Invalid email', 'ትክክለኛ ኢሜይል ያስገቡ');
                    }
                    return null;
                  }),
                  const SizedBox(height: 12),
                  _field(t('Username', 'ተጠቃሚ ስም'), _username,
                      hint: t('Optional – defaults to email prefix',
                          'አማራጭ – ከኢሜይል ይወሰዳል')),
                  if (!_isEdit) ...[
                    const SizedBox(height: 12),
                    _passwordField(
                      label: t('Password *', 'የይለፍ ቃል *'),
                      controller: _password,
                      obscure: _obscurePassword,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      validator: (v) {
                        if (v == null || v.length < 6) {
                          return t('Min 6 characters', 'ቢያንስ 6 ቁምፊዎች');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    _passwordField(
                      label: t('Confirm Password *', 'የይለፍ ቃል ድገም *'),
                      controller: _confirmPassword,
                      obscure: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                      validator: (v) {
                        if (v != _password.text) {
                          return t(
                              'Passwords do not match', 'የይለፍ ቃሎቹ አይመሳሰሉም');
                        }
                        return null;
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            color: Colors.blue, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t(
                              'Email cannot be changed. Admin can change password after login.',
                              'ኢሜይል ሊቀየር አይችልም። አስተዳዳሪ ከገባ በኋላ ሊቀይሩ ይችላሉ።',
                            ),
                            style: TextStyle(
                                color: Colors.blue.shade800, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // ── contact ───────────────────────────────────────────────────
              _sectionCard(
                icon: Icons.contact_phone,
                title: t('Contact Information', 'የመገናኛ መረጃ'),
                color: AppColors.low,
                children: [
                  _field(t('Phone Number *', 'ስልክ ቁጥር *'), _phone,
                      hint: '09XXXXXXXX',
                      type: TextInputType.phone, validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return t('Phone required', 'ስልክ ያስፈልጋል');
                    }
                    if (v.trim().length < 9) {
                      return t('Invalid phone number',
                          'ትክክለኛ የኢትዮጵያ ስልክ ቁጥር ያስፈልጋል');
                    }
                    return null;
                  }),
                  const SizedBox(height: 12),
                  _field(t('Alternate Phone', 'ሌላ ስልክ'), _altPhone,
                      hint: '09XXXXXXXX', type: TextInputType.phone),
                  const SizedBox(height: 12),
                  _field(t('Address *', 'አድራሻ *'), _address,
                      hint: t('House No, Street', 'ቤት ቁጥር፣ ጎዳና'),
                      validator: _required),
                  const SizedBox(height: 12),
                  _row([
                    _field(t('City', 'ከተማ'), _city,
                        hint: t('Addis Ababa', 'አዲስ አበባ')),
                    _field(t('Region', 'ክልል'), _region,
                        hint: t('Addis Ababa', 'አዲስ አበባ')),
                  ]),
                  const SizedBox(height: 12),
                  _row([
                    _field(t('Emergency Contact', 'የአስቸኳይ ጊዜ ያናግሩ'),
                        _emergencyContact,
                        hint: t('Full name', 'ሙሉ ስም')),
                    _field(t('Emergency Phone', 'አስቸኳይ ስልክ'), _emergencyPhone,
                        hint: '09XXXXXXXX', type: TextInputType.phone),
                  ]),
                ],
              ),
              const SizedBox(height: 16),

              // ── equb level ────────────────────────────────────────────────
              _sectionCard(
                icon: Icons.savings,
                title: t('Assign EQUB Level', 'የEQUB ደረጃ ይምረጡ'),
                color: AppColors.medium,
                children: [
                  Text(
                    t(
                      'Select the EQUB level this admin will manage. Multiple admins can be assigned to the same level.',
                      'ይህ አስተዳዳሪ የሚያስተዳድረውን የEQUB ደረጃ ይምረጡ። ብዙ አስተዳዳሪዎች ለአንድ ደረጃ ሊመደቡ ይችላሉ።',
                    ),
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _LevelSelector(
                    selected: _selectedLevel,
                    isAmharic: _isAmharic,
                    onChanged: (v) => setState(() => _selectedLevel = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── submit ────────────────────────────────────────────────────
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(_isEdit ? Icons.save : Icons.person_add),
                  label: Text(
                    _saving
                        ? t('Saving…', 'በማስቀመጥ ላይ…')
                        : _isEdit
                            ? t('Save Changes', 'ለውጦቹን አስቀምጥ')
                            : t('Assign Admin', 'አስተዳዳሪ መድብ'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            ]),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _row(List<Widget> children) => Row(
        children: children
            .expand((w) => [Expanded(child: w), const SizedBox(width: 12)])
            .toList()
          ..removeLast(),
      );

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    TextInputType type = TextInputType.text,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: type,
          enabled: enabled,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint ?? label,
            fillColor: enabled ? Colors.white : Colors.grey.shade100,
          ),
        ),
      ],
    );
  }

  Widget _passwordField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          decoration: InputDecoration(
            hintText: '••••••••',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? t('This field is required', 'ይህ ሜዳ ያስፈልጋል')
      : null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Level selector widget
// ═══════════════════════════════════════════════════════════════════════════
class _LevelSelector extends StatefulWidget {
  const _LevelSelector({
    required this.selected,
    required this.isAmharic,
    required this.onChanged,
  });

  final String selected;
  final bool isAmharic;
  final ValueChanged<String> onChanged;

  @override
  State<_LevelSelector> createState() => _LevelSelectorState();
}

class _LevelSelectorState extends State<_LevelSelector> {
  List<Map<String, dynamic>> _customLevels = [];

  @override
  void initState() {
    super.initState();
    _loadCustomLevels();
  }

  Future<void> _loadCustomLevels() async {
    final equbs = await ApiService.getEqubs();
    if (!mounted) return;
    setState(() {
      _customLevels = equbs
          .whereType<Map>()
          .map((equb) => Map<String, dynamic>.from(equb))
          .where((equb) => !['low', 'medium', 'high'].contains(equb['level']))
          .toList();
    });
  }

  String t(String en, String am) => widget.isAmharic ? am : en;

  @override
  Widget build(BuildContext context) {
    final levels = <Map<String, dynamic>>[
      {
        'value': 'low',
        'label': t('Low Level', 'ዝቅተኛ ደረጃ'),
        'subtitle': t('5,000 ETB/week · up to 100 members',
            '5,000 ብር/ሳምንት · እስከ 100 አባላት'),
        'color': AppColors.low,
        'icon': Icons.savings,
      },
      {
        'value': 'medium',
        'label': t('Medium Level', 'መካከለኛ ደረጃ'),
        'subtitle': t('10,000 ETB/week · up to 100 members',
            '10,000 ብር/ሳምንት · እስከ 100 አባላት'),
        'color': AppColors.medium,
        'icon': Icons.business_center,
      },
      {
        'value': 'high',
        'label': t('High Level', 'ከፍተኛ ደረጃ'),
        'subtitle': t('20,000 ETB/week · up to 100 members',
            '20,000 ብር/ሳምንት · እስከ 100 አባላት'),
        'color': AppColors.high,
        'icon': Icons.stars,
      },
    ];
    levels.addAll(_customLevels.map((equb) {
      final price = equb['price']?.toString() ?? '—';
      final max = equb['maxParticipants']?.toString() ?? '—';
      return {
        'value': equb['level'].toString(),
        'label':
            equb['name']?.toString() ?? t('Custom Equb Level', 'አዲስ የእቁብ ደረጃ'),
        'subtitle': '$price ETB · $max ${t('members', 'አባላት')}',
        'color': AppColors.primary,
        'icon': Icons.add_business,
      };
    }));

    return Column(
      children: levels.map((l) {
        final value = l['value'] as String;
        final color = l['color'] as Color;
        final isSelected = widget.selected == value;

        return GestureDetector(
          onTap: () => widget.onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected ? color.withOpacity(0.08) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(l['icon'] as IconData, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l['label'] as String,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(l['subtitle'] as String,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ]),
              ),
              if (isSelected) Icon(Icons.check_circle, color: color, size: 24),
            ]),
          ),
        );
      }).toList(),
    );
  }
}
