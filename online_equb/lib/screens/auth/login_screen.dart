import 'package:flutter/material.dart';
import '../../widgets/smart_back_button.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/firestore_direct_service.dart';
import '../../utils/constants.dart';
import '../../widgets/page_header_banner.dart';
import '../profile/notifications_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form     = GlobalKey<FormState>();
  final _email    = TextEditingController();
  final _password = TextEditingController();
  final _otpCtrl  = TextEditingController();
  bool _obscure        = true;
  int  _loginRoleIndex = 0;  // 0=Member, 1=Admin
  int  _loginMode      = 0;  // 0=Password, 1=OTP (email/phone)
  bool _otpSent        = false;
  bool _otpLoading     = false;
  String? _otpError;
  String? _simulatedOtp; // dev mode: OTP returned when SMS not configured

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.login(_email.text.trim(), _password.text);
    if (!mounted) return;
    if (ok) {
      if (auth.isSuperAdmin) {
        context.go('/super-admin');
      } else if (auth.isAdmin) {
        context.go('/admin');
      } else {
        context.go('/home');
      }
    } else {
      // Show the full error so we can debug on phone
      final msg = auth.error ?? 'Login failed. Please check your credentials.\nዳግም ሞክር።';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 13)),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
  }

  // ── Send OTP via email or phone ─────────────────────────────────────────────
  Future<void> _sendOtp() async {
    final id = _email.text.trim();
    if (id.isEmpty) {
      setState(() => _otpError = 'Enter your email or phone number first.');
      return;
    }
    setState(() { _otpLoading = true; _otpError = null; _simulatedOtp = null; });
    try {
      final res = await ApiService.sendOtp(id);
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _otpSent      = true;
          _otpLoading   = false;
          _simulatedOtp = res['simulated'] == true ? res['otp']?.toString() : null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res['simulated'] == true
              ? '📱 Dev mode: OTP = ${res['otp']} (SMS not configured)'
              : '✅ OTP sent to $id. Check your email/SMS.'),
          backgroundColor: res['simulated'] == true ? Colors.orange : Colors.green,
          duration: Duration(seconds: res['simulated'] == true ? 10 : 4),
        ));
      } else {
        setState(() {
          _otpError   = (res['error'] ?? 'Failed to send OTP').toString();
          _otpLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _otpError = 'Error: $e'; _otpLoading = false; });
    }
  }

  // ── Verify OTP and login ──────────────────────────────────────────────────
  Future<void> _verifyOtpAndLogin() async {
    final id  = _email.text.trim();
    final otp = _otpCtrl.text.trim();
    if (id.isEmpty || otp.isEmpty) {
      setState(() => _otpError = 'Enter your email/phone and the OTP code.');
      return;
    }
    setState(() { _otpLoading = true; _otpError = null; });
    try {
      final res = await ApiService.verifyOtp(id, otp);
      if (!mounted) return;
      if (res['token'] != null) {
        final auth = context.read<AuthProvider>();
        // Apply token + user to AuthProvider
        final token = res['token'].toString();
        final user  = (res['user'] as Map<String, dynamic>?) ?? {};
        final role  = (user['role'] ?? 'user').toString();
        if (role == 'admin') {
          final docId = (user['adminId'] ?? user['id'] ?? '').toString();
          final lvl   = (user['level'] ?? user['equbLevel'] ?? 'low').toString().toLowerCase();
          auth.refreshUser({...user, 'adminId': docId, 'id': docId, 'role': 'admin', 'level': lvl, 'equbLevel': lvl});
        } else if (role == 'super_admin') {
          auth.refreshUser({...user, 'role': 'super_admin'});
        } else {
          auth.refreshUser({...user, 'role': 'user'});
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', token);
        if (!mounted) return;
        setState(() => _otpLoading = false);
        if (auth.isSuperAdmin)      context.go('/super-admin');
        else if (auth.isAdmin)      context.go('/admin');
        else                        context.go('/home');
      } else {
        setState(() {
          _otpError   = (res['error'] ?? 'Invalid OTP. Please try again.').toString();
          _otpLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _otpError = 'Error: $e'; _otpLoading = false; });
    }
  }

  // ── Check notifications by email (no login required) ──────────────────────
  void _showEmailNotificationDialog(BuildContext ctx, bool isAmharic) {
    final emailCtrl = TextEditingController();
    String t(String en, String am) => isAmharic ? am : en;
    List<Map<String, dynamic>> notifList = [];
    bool loadingState = false;
    String? errorState;

    showDialog(
      context: ctx,
      builder: (dialogCtx) => StatefulBuilder(builder: (ctx2, setState2) {
        Future<void> search() async {
          final em = emailCtrl.text.trim().toLowerCase();
          if (em.isEmpty || !em.contains('@')) {
            setState2(() => errorState = t('Enter valid email', 'ትክክለኛ ኢሜይል ያስፈልጋል'));
            return;
          }
          setState2(() { loadingState = true; errorState = null; notifList = []; });
          try {
            List<Map<String, dynamic>> list = [];

            // 1. Try backend REST API first (fastest, always fresh)
            try {
              final apiList = await ApiService.getNotificationsByEmail(em);
              if (apiList.isNotEmpty) {
                list = apiList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
              }
            } catch (_) {}

            // 2. Fall back to FirestoreDirectService (JWT, no server needed)
            if (list.isEmpty) {
              list = await FirestoreDirectService.getNotificationsForUser(
                  userId: '', userEmail: em);
            }

            list.sort((a, b) => (b['createdAt']?.toString() ?? '')
                .compareTo(a['createdAt']?.toString() ?? ''));
            setState2(() { notifList = list; loadingState = false; });
          } catch (e) {
            setState2(() { errorState = 'Could not load. Check connection.\n$e'; loadingState = false; });
          }
        }
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.all(14),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx2).size.height * 0.80),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  const Icon(Icons.notifications_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    t('Check Payment Notifications', 'የክፍያ ማሳወቂያ ተመልከት'),
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 15),
                  )),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => Navigator.pop(dialogCtx),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
              ),
              // Email input
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    t('Enter your registered email to see payment status:',
                      'የተመዘገቡበት ኢሜይል ያስፈልጋል:'),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => search(),
                      decoration: InputDecoration(
                        hintText: 'you@gmail.com',
                        prefixIcon: const Icon(Icons.email_outlined, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true, fillColor: Colors.grey.shade50,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        errorText: errorState,
                        isDense: true,
                      ),
                    )),
                    const SizedBox(width: 8),
                    SizedBox(height: 46, child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: search,
                      child: loadingState
                          ? const SizedBox(width: 18, height: 18,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.search_rounded, color: Colors.white, size: 20),
                    )),
                  ]),
                ]),
              ),
              // Results
              if (loadingState)
                const Padding(padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator())
              else if (notifList.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Icon(Icons.notifications_none_rounded,
                        size: 48, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text(t('Enter email and tap search',
                           'ኢሜይልዎን ያስፈፅሙ'),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ]),
                )
              else
                Flexible(child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                  shrinkWrap: true,
                  itemCount: notifList.length,
                  itemBuilder: (_, i) {
                    final n = notifList[i];
                    final type = (n['type'] ?? '').toString();
                    final isApproved = type.contains('verified') || type.contains('approved');
                    final isRejected = type.contains('rejected');
                    final color = isApproved ? Colors.green
                                : isRejected ? Colors.red : AppColors.primary;
                    final icon  = isApproved ? Icons.check_circle_rounded
                                : isRejected ? Icons.cancel_rounded
                                : Icons.notifications_rounded;
                    final title = (n['title'] ?? '').toString();
                    final body  = (n['body']  ?? '').toString();
                    final date  = (n['createdAt'] ?? '').toString();
                    final dateStr = date.length >= 10 ? date.substring(0, 10) : date;
                    final amount  = (n['amount'] ?? '').toString();
                    final level   = (n['level']  ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                              color: color.withOpacity(0.12), shape: BoxShape.circle),
                          child: Icon(icon, color: color, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title, style: TextStyle(fontWeight: FontWeight.bold,
                              fontSize: 12, color: color),
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Text(body, style: const TextStyle(fontSize: 11,
                              color: AppColors.textSecondary, height: 1.3),
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(children: [
                            if (level.isNotEmpty) Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(level.toUpperCase(),
                                  style: TextStyle(fontSize: 8, color: color,
                                      fontWeight: FontWeight.bold)),
                            ),
                            if (amount.isNotEmpty && amount != '0') ...[
                              const SizedBox(width: 5),
                              Text('ETB $amount', style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary)),
                            ],
                            const Spacer(),
                            Text(dateStr, style: TextStyle(
                                fontSize: 9, color: Colors.grey.shade400)),
                          ]),
                        ])),
                      ]),
                    );
                  },
                )),
            ]),
          ),
        );
      }),
    );
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
          // 🔔 Notification icon — top right corner
          // Any user can check their payment notifications by entering their email
          IconButton(
            icon: const Icon(Icons.notifications_rounded),
            tooltip: isAmharic ? 'ማሳወቂያዎች' : 'Check Payment Notifications',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const NotificationsScreen())),
          ),
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

                const SizedBox(height: 16),

                // ── Login Mode Toggle ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() { _loginMode = 0; _otpSent = false; _otpError = null; }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _loginMode == 0 ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text(
                          isAmharic ? '🔑 የይለፍ ቃል' : '🔑 Password',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                              color: _loginMode == 0 ? Colors.white : AppColors.textSecondary),
                        )),
                      ),
                    )),
                    Expanded(child: GestureDetector(
                      onTap: () => setState(() { _loginMode = 1; _otpSent = false; _otpError = null; }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: _loginMode == 1 ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(child: Text(
                          isAmharic ? '📱 OTP ኮድ' : '📱 OTP Code',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                              color: _loginMode == 1 ? Colors.white : AppColors.textSecondary),
                        )),
                      ),
                    )),
                  ]),
                ),
                const SizedBox(height: 16),

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

                // ── PASSWORD MODE ─────────────────────────────────────────
                if (_loginMode == 0) ...[
                  Text(isAmharic ? 'ይለፍ ቃል' : 'Password',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'min 5 characters',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => v == null || v.length < 5 ? 'Min 5 characters' : null,
                  ),
                ],

                // ── OTP MODE ────────────────────────────────────────────────
                if (_loginMode == 1) ...[
                  if (!_otpSent) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.info_outline, color: AppColors.primary, size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text(
                            isAmharic
                                ? 'ኢሜይልዎ ወይም ስልክ ቁጥርዎ ያስፈልጋል። OTP ኮድ ይልካሉ።'
                                : 'Enter email or phone above. Tap to receive a 6-digit OTP.',
                            style: const TextStyle(fontSize: 12, color: AppColors.primary),
                          )),
                        ]),
                        const SizedBox(height: 10),
                        SizedBox(width: double.infinity, child: ElevatedButton.icon(
                          onPressed: _otpLoading ? null : _sendOtp,
                          icon: _otpLoading
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.send_rounded, size: 16),
                          label: Text(_otpLoading
                              ? (isAmharic ? 'እየተላከ...' : 'Sending...')
                              : (isAmharic ? 'OTP ኮድ ላክ' : 'Send OTP Code'),
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary, foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        )),
                        if (_otpError != null) ...[
                          const SizedBox(height: 8),
                          Text(_otpError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                      ]),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withOpacity(0.3)),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text(
                            isAmharic ? 'OTP ኮድ ተልኳል! ኢሜይልዎ/ስልክዎ ይፈትሹ።'
                                      : 'OTP sent! Check email or SMS.',
                            style: const TextStyle(fontSize: 12, color: Colors.green,
                                fontWeight: FontWeight.w600),
                          )),
                        ]),
                        if (_simulatedOtp != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('Dev OTP: $_simulatedOtp',
                              style: const TextStyle(fontWeight: FontWeight.bold,
                                  color: Colors.orange, fontSize: 14)),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(isAmharic ? '6-ዲጂት OTP ኮድ ያስፈልጋል:' : 'Enter 6-digit OTP:',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _otpCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold,
                              letterSpacing: 10),
                          decoration: InputDecoration(
                            hintText: '------',
                            counterText: '',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true, fillColor: Colors.white,
                          ),
                        ),
                        if (_otpError != null) ...[
                          const SizedBox(height: 6),
                          Text(_otpError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: () => setState(() { _otpSent = false; _otpError = null; }),
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          label: Text(isAmharic ? 'ዳግም ላክ' : 'Resend OTP',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ]),
                    ),
                  ],
                ],


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

                // ── Login / Verify OTP Button ──────────────────────────
                if (_loginMode == 0 || (_loginMode == 1 && _otpSent))
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: (auth.loading || _otpLoading)
                          ? null
                          : (_loginMode == 1 ? _verifyOtpAndLogin : _login),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: (auth.loading || _otpLoading)
                          ? const SizedBox(height: 22, width: 22,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : Text(
                              _loginMode == 1
                                  ? (isAmharic ? '✅ OTP ኮድ አረጋግጥ' : '✅ Verify OTP & Sign In')
                                  : (isAmharic ? 'ግባ (Login)' : 'Sign In / Login'),
                              style: const TextStyle(fontSize: 16,
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
