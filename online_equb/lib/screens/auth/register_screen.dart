import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/smart_back_button.dart';
import '../../widgets/page_header_banner.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _form = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscure = true;
  bool _obscureConfirm = true;
  // animation for the form fields entrance
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  // ── Validators ────────────────────────────────────────────────────────────

  /// Only Amharic/Latin letters and spaces — no digits.
  String? _nameValidator(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required';
    if (RegExp(r'[0-9]').hasMatch(v)) return '$label must not contain numbers';
    if (v.trim().length < 2) return '$label must be at least 2 characters';
    return null;
  }

  String? _phoneValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Phone number is required';
    final cleaned = v.trim().replaceAll(RegExp(r'[\s\-]'), '');
    // Ethiopian: 09XXXXXXXX or 07XXXXXXXX or +2519XXXXXXXX / +2517XXXXXXXX
    final local = RegExp(r'^0[79]\d{8}$');
    final intl = RegExp(r'^\+2519\d{8}$|^\+2517\d{8}$');
    if (!local.hasMatch(cleaned) && !intl.hasMatch(cleaned)) {
      return 'Enter a valid Ethiopian phone (09XXXXXXXX or +2519XXXXXXXX)';
    }
    return null;
  }

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final emailRx = RegExp(r'^[\w.\-]+@[\w\-]+\.[a-zA-Z]{2,}$');
    if (!emailRx.hasMatch(v.trim())) return 'Enter a valid email address';
    return null;
  }

  String? _passwordValidator(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return 'Include at least one letter';
    return null;
  }

  String? _confirmPasswordValidator(String? v) {
    if (v != _password.text) return 'Passwords do not match';
    return null;
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _register() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final fullName =
        '${_firstName.text.trim()} ${_middleName.text.trim()} ${_lastName.text.trim()}'
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
    final ok = await auth.register({
      'firstName': _firstName.text.trim(),
      'middleName': _middleName.text.trim(),
      'lastName': _lastName.text.trim(),
      'fullName': fullName,
      'phoneNumber': _phone.text.trim(),
      'email': _email.text.trim().toLowerCase(),
      'password': _password.text,
    });
    if (ok && mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Column(
          children: [
            // ── Animated banner ──────────────────────────────────────────
            PageHeaderBanner(
              color: AppColors.primary,
              icon: Icons.person_add_rounded,
              phrases: PageHeaderBanner.registerPhrases,
              staticTitle: 'Create Your Equb Account',
            ),

            // ── Back button row ──────────────────────────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                children: [
                  const SmartBackButton(),
                  const Expanded(
                    child: Text(
                      'New Member Registration',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('FREE',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

            // ── Form ─────────────────────────────────────────────────────
            Expanded(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Personal info card
                          _FormCard(
                            icon: Icons.person_rounded,
                            title: 'Personal Information',
                            color: AppColors.primary,
                            children: [
                              _FieldRow(children: [
                                _FormField(
                                  controller: _firstName,
                                  label: 'First Name *',
                                  hint: 'Abebe',
                                  icon: Icons.person_outline,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                                  ],
                                  validator: (v) =>
                                      _nameValidator(v, 'First name'),
                                ),
                                _FormField(
                                  controller: _middleName,
                                  label: 'Father Name *',
                                  hint: 'Bekele',
                                  icon: Icons.person_outline,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                                  ],
                                  validator: (v) =>
                                      _nameValidator(v, 'Father name'),
                                ),
                              ]),
                              const SizedBox(height: 12),
                              _FormField(
                                controller: _lastName,
                                label: 'Grandfather Name *',
                                hint: 'Alemu',
                                icon: Icons.person_outline,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[a-zA-Z\u1200-\u137F ]'))
                                ],
                                validator: (v) =>
                                    _nameValidator(v, 'Grandfather name'),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Contact card
                          _FormCard(
                            icon: Icons.contact_phone_rounded,
                            title: 'Contact Information',
                            color: const Color(0xFF00897B),
                            children: [
                              _FormField(
                                controller: _phone,
                                label: 'Ethiopian Phone Number *',
                                hint: '0911234567 or +251911234567',
                                icon: Icons.phone_rounded,
                                type: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9+\-\s]'))
                                ],
                                validator: _phoneValidator,
                              ),
                              const SizedBox(height: 12),
                              _FormField(
                                controller: _email,
                                label: 'Email Address *',
                                hint: 'abebe@example.com',
                                icon: Icons.email_rounded,
                                type: TextInputType.emailAddress,
                                validator: _emailValidator,
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Security card
                          _FormCard(
                            icon: Icons.lock_rounded,
                            title: 'Account Security',
                            color: const Color(0xFF7B1FA2),
                            children: [
                              _PasswordField(
                                controller: _password,
                                label: 'Password *',
                                hint: 'Min 6 chars with letters',
                                obscure: _obscure,
                                onToggle: () =>
                                    setState(() => _obscure = !_obscure),
                                validator: _passwordValidator,
                              ),
                              const SizedBox(height: 12),
                              _PasswordField(
                                controller: _confirmPassword,
                                label: 'Confirm Password *',
                                hint: 'Re-enter your password',
                                obscure: _obscureConfirm,
                                onToggle: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm),
                                validator: _confirmPasswordValidator,
                              ),
                              const SizedBox(height: 12),
                              // Password strength hint
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          Colors.purple.withOpacity(0.2)),
                                ),
                                child: Row(children: [
                                  Icon(Icons.info_outline,
                                      size: 15,
                                      color: Colors.purple.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Password must have letters + numbers. '
                                      'Minimum 6 characters.',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.purple.shade700),
                                    ),
                                  ),
                                ]),
                              ),
                            ],
                          ),

                          // Error
                          if (auth.error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.error.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: AppColors.error.withOpacity(0.3)),
                              ),
                              child: Row(children: [
                                const Icon(Icons.error_outline,
                                    color: AppColors.error, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(auth.error!,
                                      style: const TextStyle(
                                          color: AppColors.error,
                                          fontSize: 13)),
                                ),
                              ]),
                            ),
                          ],

                          const SizedBox(height: 20),

                          // Submit
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: auth.loading ? null : _register,
                              icon: auth.loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.how_to_reg_rounded,
                                      color: Colors.white),
                              label: Text(
                                auth.loading
                                    ? 'Creating Account…'
                                    : 'Create My Account',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                                elevation: 4,
                              ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('Already have an account? ',
                                  style: TextStyle(fontSize: 14)),
                              GestureDetector(
                                onTap: () => context.go('/login'),
                                child: const Text('Sign In',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared form widgets ────────────────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final List<Widget> children;
  const _FormCard(
      {required this.icon,
      required this.title,
      required this.color,
      required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: color)),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          ...children,
        ]),
      );
}

class _FieldRow extends StatelessWidget {
  final List<Widget> children;
  const _FieldRow({required this.children});
  @override
  Widget build(BuildContext context) => Row(
        children: children
            .expand((w) => [Expanded(child: w), const SizedBox(width: 10)])
            .toList()
          ..removeLast(),
      );
}

class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final TextInputType? type;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.type,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 5),
          TextFormField(
            controller: controller,
            keyboardType: type,
            inputFormatters: inputFormatters,
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 12),
            ),
          ),
        ],
      );
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 5),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            validator: validator,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                  vertical: 10, horizontal: 12),
              suffixIcon: IconButton(
                icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18),
                onPressed: onToggle,
              ),
            ),
          ),
        ],
      );
}

// end of file
