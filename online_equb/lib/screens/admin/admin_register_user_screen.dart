import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme.dart';
import '../../services/role_management_service.dart';
import '../../widgets/page_header_banner.dart';

/// Full user registration / edit form.
/// Pass [editData] for edit mode; omit for create mode.
/// [level] — the equb level this user belongs to.
/// [adminId] — the admin creating/editing the user.
class AdminRegisterUserScreen extends StatefulWidget {
  final String level;
  final String adminId;
  final Map<String, dynamic>? editData;

  const AdminRegisterUserScreen({
    super.key,
    required this.level,
    required this.adminId,
    this.editData,
  });

  @override
  State<AdminRegisterUserScreen> createState() =>
      _AdminRegisterUserScreenState();
}

class _AdminRegisterUserScreenState extends State<AdminRegisterUserScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstName;
  late final TextEditingController _middleName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _uniqueId;

  bool _saving = false;
  bool _checkingId = false;
  bool _isAmharic = false;
  bool get _isEdit => widget.editData != null;

  String t(String en, String am) => _isAmharic ? am : en;

  Color get _levelColor {
    switch (widget.level) {
      case 'medium':
        return AppColors.medium;
      case 'high':
        return AppColors.high;
      default:
        return AppColors.low;
    }
  }

  String get _levelLabel {
    if (_isAmharic) {
      switch (widget.level) {
        case 'medium':
          return 'መካከለኛ';
        case 'high':
          return 'ከፍተኛ';
        default:
          return 'ዝቅተኛ';
      }
    }
    switch (widget.level) {
      case 'medium':
        return 'Medium';
      case 'high':
        return 'High';
      default:
        return 'Low';
    }
  }

  @override
  void initState() {
    super.initState();
    final d = widget.editData ?? {};
    _firstName = TextEditingController(text: d['firstName'] ?? '');
    _middleName = TextEditingController(text: d['middleName'] ?? '');
    _lastName = TextEditingController(text: d['lastName'] ?? '');
    _email = TextEditingController(text: d['email'] ?? '');
    _phone = TextEditingController(
        text: d['phoneNumber'] ?? d['phone'] ?? '');
    _uniqueId =
        TextEditingController(text: d['uniqueId'] ?? d['nationalId'] ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _firstName, _middleName, _lastName, _email, _phone, _uniqueId
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── submit ────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    final payload = <String, dynamic>{
      'firstName': _firstName.text.trim(),
      'middleName': _middleName.text.trim(),
      'lastName': _lastName.text.trim(),
      'email': _email.text.trim().toLowerCase(),
      'phoneNumber': _phone.text.trim(),
      'uniqueId': _uniqueId.text.trim(),
      'equbLevel': widget.level,
      'adminId': widget.adminId,
    };

    bool ok;
    String? errorMsg;
    String? successMsg;

    if (_isEdit) {
      // Check if uniqueId changed & is still unique
      final oldId = (widget.editData!['uniqueId'] ?? '').toString().trim();
      if (_uniqueId.text.trim() != oldId) {
        final taken = await RoleManagementService.isUniqueIdTaken(
            _uniqueId.text.trim(),
            excludeUserId: widget.editData!['userId']);
        if (taken) {
          setState(() => _saving = false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t(
              'This Unique ID is already registered to another user.',
              'ይህ ልዩ መታወቂያ ለሌላ ተጠቃሚ ተመዝግቧል።',
            )),
            backgroundColor: AppColors.error,
          ));
          return;
        }
      }
      ok = await RoleManagementService.updateUser(
          widget.editData!['userId'] ?? '', payload);
      errorMsg = t('Failed to update user.', 'ተጠቃሚውን ማሻሻል አልተቻለም።');
      successMsg = t('User updated successfully.', 'ተጠቃሚ ተሻሽሏል።');
    } else {
      final res = await RoleManagementService.createUserResult(payload);
      ok = res['success'] == true;
      if (ok) {
        successMsg = res['message'] ?? t('User assigned successfully.', 'ተጠቃሚ ተመዝግቧል።');
      } else {
        errorMsg = res['error'] ?? t('Failed to assign user.', 'ተጠቃሚውን መመዝገብ አልተቻለም።');
      }
    }

    setState(() => _saving = false);
    if (!mounted) return;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(successMsg ?? t('User saved successfully.', 'ተጠቃሚ በተሳካ ሁኔታ ተስቀምጧል።')),
        backgroundColor: AppColors.success,
      ));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(errorMsg ?? t('Failed to process request.', 'ጥያቄውን ማከናወን አልተቻለም።')),
        backgroundColor: AppColors.error,
      ));
    }
  }

  // ── uniqueId real-time check ───────────────────────────────────────────
  Future<void> _checkUniqueId(String value) async {
    if (value.trim().isEmpty) return;
    // Skip check when editing and value hasn't changed
    if (_isEdit &&
        value.trim() == (widget.editData!['uniqueId'] ?? '').toString().trim()) {
      return;
    }
    setState(() => _checkingId = true);
    final taken =
        await RoleManagementService.isUniqueIdTaken(value.trim());
    if (mounted) setState(() => _checkingId = false);
    if (taken && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(t(
          '⚠ Unique ID already taken by another user.',
          '⚠ ይህ ልዩ መታወቂያ ቀድሞ ጥቅም ላይ ውሏል።',
        )),
        backgroundColor: AppColors.warning,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit
            ? t('Edit User', 'ተጠቃሚ አርትዕ')
            : t('Register User', 'ተጠቃሚ ምዝገባ')),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, false),
        ),
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
        // Animated banner at the bottom of the AppBar
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: PageHeaderBanner(
            color: _levelColor,
            icon: Icons.how_to_reg_rounded,
            phrases: PageHeaderBanner.registerPhrases,
            staticTitle: t(
              '$_levelLabel Level — Add Member',
              '$_levelLabel ደረጃ — አባል ጨምር',
            ),
            height: 64,
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              // Level badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _levelColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _levelColor.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.savings, color: _levelColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      t('Registering for $_levelLabel Level EQUB',
                          'ለ$_levelLabel ደረጃ EQUB እያስመዘገቡ ነው'),
                      style: TextStyle(
                          color: _levelColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),

              // ── personal info ─────────────────────────────────────────────
              _sectionCard(
                icon: Icons.person,
                title: t('Personal Information', 'የግል መረጃ'),
                color: _levelColor,
                children: [
                  _row([
                    _field(t('First Name *', 'ስም *'), _firstName,
                        hint: t('Abebe', 'አበበ'),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                        ],
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return t('First name required', 'ስም ያስፈልጋል');
                          }
                          if (RegExp(r'[0-9]').hasMatch(v)) {
                            return t('No numbers in name', 'ቁጥር አይፈቀድም');
                          }
                          if (v.trim().length < 2) {
                            return t('Min 2 characters', 'ቢያንስ 2 ቁምፊዎች');
                          }
                          return null;
                        }),
                    _field(t('Middle Name', 'የአባት ስም'), _middleName,
                        hint: t('Bekele', 'በቀለ'),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                        ],
                        validator: (v) {
                          if (v != null && v.isNotEmpty &&
                              RegExp(r'[0-9]').hasMatch(v)) {
                            return t('No numbers in name', 'ቁጥር አይፈቀድም');
                          }
                          return null;
                        }),
                  ]),
                  const SizedBox(height: 12),
                  _field(t('Last Name *', 'የአያት ስም *'), _lastName,
                      hint: t('Alemu', 'አለሙ'),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return t('Last name required', 'የአያት ስም ያስፈልጋል');
                        }
                        if (RegExp(r'[0-9]').hasMatch(v)) {
                          return t('No numbers in name', 'ቁጥር አይፈቀድም');
                        }
                        return null;
                      }),
                ],
              ),
              const SizedBox(height: 16),

              // ── contact ───────────────────────────────────────────────────
              _sectionCard(
                icon: Icons.contact_phone,
                title: t('Contact Information', 'የመገናኛ መረጃ'),
                color: _levelColor,
                children: [
                  _field(t('Email Address *', 'ኢሜይል *'), _email,
                      hint: 'user@example.com',
                      type: TextInputType.emailAddress,
                      enabled: !_isEdit,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return t('Email required', 'ኢሜይል ያስፈልጋል');
                        }
                        final rx = RegExp(r'^[\w.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
                        if (!rx.hasMatch(v.trim())) {
                          return t('Enter a valid email (user@domain.com)',
                              'ትክክለኛ ኢሜይል ያስገቡ (user@domain.com)');
                        }
                        return null;
                      }),
                  const SizedBox(height: 12),
                  _field(t('Phone Number *', 'ስልክ ቁጥር *'), _phone,
                      hint: '09XXXXXXXX',
                      type: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9+\-\s]'))
                      ],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return t('Phone required', 'ስልክ ያስፈልጋል');
                        }
                        final clean =
                            v.trim().replaceAll(RegExp(r'[\s\-]'), '');
                        final local = RegExp(r'^0[79]\d{8}$');
                        final intl =
                            RegExp(r'^\+2519\d{8}$|^\+2517\d{8}$');
                        if (!local.hasMatch(clean) && !intl.hasMatch(clean)) {
                          return t(
                              'Use Ethiopian format: 09XXXXXXXX or +2519XXXXXXXX',
                              'ትክክለኛ ቅርጸት ይጠቀሙ: 09XXXXXXXX');
                        }
                        return null;
                      }),
                ],
              ),
              const SizedBox(height: 16),

              // ── unique ID ─────────────────────────────────────────────────
              _sectionCard(
                icon: Icons.badge,
                title: t('Unique Identification', 'ልዩ መታወቂያ'),
                color: _levelColor,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            color: AppColors.primary, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t(
                              'Each Unique ID maps to exactly one user (1:1 rule). Once registered, the same ID cannot be used again.',
                              'እያንዳንዱ ልዩ መታወቂያ ለአንድ ተጠቃሚ ብቻ ነው (1:1 ደንብ)። አንዴ ከተመዘገበ ዳግም ጥቅም ላይ ሊውል አይችልም።',
                            ),
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t('Unique ID *', 'ልዩ መታወቂያ *'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _uniqueId,
                        keyboardType: TextInputType.text,
                        onEditingComplete: () =>
                            _checkUniqueId(_uniqueId.text),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return t('Unique ID required',
                                'ልዩ መታወቂያ ያስፈልጋል');
                          }
                          if (v.trim().length < 5) {
                            return t('Min 5 characters',
                                'ቢያንስ 5 ቁምፊዎች');
                          }
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText:
                              t('e.g. ETH-1234-ABCD', 'ለምሳሌ ETH-1234-ABCD'),
                          prefixIcon: const Icon(Icons.badge),
                          suffixIcon: _checkingId
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ── assign button ─────────────────────────────────────────────
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _levelColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(_isEdit ? Icons.save : Icons.how_to_reg),
                  label: Text(
                    _saving
                        ? t('Saving…', 'እያስቀመጠ ነው…')
                        : _isEdit
                            ? t('Save Changes', 'ለውጦቹን አስቀምጥ')
                            : t('Assign User', 'ተጠቃሚ መድብ'),
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
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color)),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
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
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: type,
          enabled: enabled,
          inputFormatters: inputFormatters,
          validator: validator,
          decoration: InputDecoration(
            hintText: hint ?? label,
            fillColor: enabled ? Colors.white : Colors.grey.shade100,
          ),
        ),
      ],
    );
  }

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty)
          ? t('This field is required', 'ይህ ሜዳ ያስፈልጋል')
          : null;
}
