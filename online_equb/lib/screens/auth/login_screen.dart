import 'package:flutter/material.dart';
import '../../widgets/smart_back_button.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../widgets/page_header_banner.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  int _loginRoleIndex = 0; // 0: User / Member, 1: Admin / Super Admin

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(_email.text.trim(), _password.text);
    if (ok && mounted) {
      if (auth.isSuperAdmin) {
        context.go('/super-admin');
      } else if (auth.isAdmin) {
        context.go('/admin');
      } else {
        context.go('/home');
      }
    }
  }

  void _showServerDialog(BuildContext ctx) {
    final ctrl = TextEditingController(
        text: ApiService.currentBaseUrl.replaceAll('/api/v1', ''));
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.dns_rounded, color: AppColors.primary),
          SizedBox(width: 10),
          Text('Server / Backend URL',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your server IP address.\n'
              'Example: http://192.168.1.134:8080\n\n'
              'Leave blank to use Firebase directly\n(no server needed).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'http://192.168.x.x:8080',
                prefixIcon: Icon(Icons.http),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ApiService.clearServerUrl();
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Server URL cleared — using Firebase directly'),
                  backgroundColor: Colors.orange,
                ));
              }
            },
            child: const Text('Clear', style: TextStyle(color: Colors.orange)),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = ctrl.text.trim();
              if (url.isNotEmpty) {
                await ApiService.setServerUrl(url);
              } else {
                await ApiService.clearServerUrl();
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(url.isNotEmpty
                      ? '✅ Server set to $url'
                      : '✅ Using Firebase directly'),
                  backgroundColor: AppColors.success,
                ));
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _fillCredentials(String email, String pass) {
    setState(() {
      _email.text = email;
      _password.text = pass;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isAmharic = AppConstants.currentLanguage == 'am';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isAmharic ? 'መግቢያ ገጽ' : 'Account Login'),
        leading: const SmartBackButton(),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_rounded),
            tooltip: 'Server Settings',
            onPressed: () => _showServerDialog(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: PageHeaderBanner(
            color: AppColors.primary,
            icon: Icons.login_rounded,
            phrases: PageHeaderBanner.equbPhrases,
            staticTitle: isAmharic ? 'ወደ ኦንላይን እቁብ ይግቡ' : 'Sign in to Online Equb',
            height: 64,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),

                // Branding Logo & Title
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.2),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'Online Equb',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary),
                  ),
                ),
                Center(
                  child: Text(
                    isAmharic
                        ? 'ዲጂታል ቁጠባና እጣ ማህበር'
                        : 'Digital Savings & Fair Draw Platform',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),

                const SizedBox(height: 28),

                // Role Segmented Switch
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _loginRoleIndex = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _loginRoleIndex == 0
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _loginRoleIndex == 0
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                      )
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Text(
                                isAmharic ? '👤 አባል / ተጠቃሚ' : '👤 Member Login',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _loginRoleIndex == 0
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _loginRoleIndex = 1),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _loginRoleIndex == 1
                                  ? Colors.white
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: _loginRoleIndex == 1
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 4,
                                      )
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: Text(
                                isAmharic ? '👑 አስተዳዳሪ' : '👑 Admin Portal',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: _loginRoleIndex == 1
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Quick fill chips for testing convenience
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Text('Quick Fill: ',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary)),
                      ActionChip(
                        avatar: const Text('👑', style: TextStyle(fontSize: 12)),
                        label: const Text('Super Admin', style: TextStyle(fontSize: 11)),
                        onPressed: () => _fillCredentials('abebe@gmail.com', 'abebe1212'),
                        backgroundColor: Colors.purple.shade50,
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Text('🛡️', style: TextStyle(fontSize: 12)),
                        label: const Text('Level Admin', style: TextStyle(fontSize: 11)),
                        onPressed: () => _fillCredentials('admin@equb.et', 'admin123'),
                        backgroundColor: Colors.blue.shade50,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Email / Username Field
                Text(
                  isAmharic ? 'ኢሜይል ወይም የተጠቃሚ ስም' : 'Username / Email',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: _loginRoleIndex == 1
                        ? 'abe@gmail.com or admin@equb.et'
                        : 'user@gmail.com',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter username or email' : null,
                ),

                const SizedBox(height: 16),

                // Password Field
                Text(
                  isAmharic ? 'ይለፍ ቃል' : 'Password',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) =>
                      v == null || v.length < 5 ? 'Min 5 characters' : null,
                ),

                if (auth.error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.error, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            auth.error!,
                            style: const TextStyle(
                                color: AppColors.error, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: auth.loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: auth.loading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          )
                        : Text(
                            isAmharic ? 'ግባ (Login)' : 'Sign In / Login',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                  ),
                ),

                const SizedBox(height: 20),

                // Register Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isAmharic ? 'መለያ የሎትም? ' : "Don't have an account? "),
                    GestureDetector(
                      onTap: () => context.go('/register'),
                      child: Text(
                        isAmharic ? 'ተመዝገብ' : 'Register Now',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
