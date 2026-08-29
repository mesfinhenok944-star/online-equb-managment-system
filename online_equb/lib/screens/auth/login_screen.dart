import 'package:flutter/material.dart';
import '../../widgets/smart_back_button.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../widgets/page_header_banner.dart';
import '../profile/notifications_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen
//
// Clean password login for admins and members.
// Notification bell (top right) → opens NotificationsScreen where user enters
// their email or phone to see payment approval/rejection status.
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form     = GlobalKey<FormState>();
  final _email    = TextEditingController();
  final _password = TextEditingController();
  bool _obscure        = true;
  int  _loginRoleIndex = 0; // 0=Member, 1=Admin

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  // ── Login ────────────────────────────────────────────────────────────────
  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok   = await auth.login(_email.text.trim(), _password.text);
    if (!mounted) return;
    if (ok) {
      if (auth.isSuperAdmin)  context.go('/super-admin');
      else if (auth.isAdmin)  context.go('/admin');
      else                    context.go('/home');
    } else {
      final msg = auth.error ?? 'Login failed. Check your credentials.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'OK', textColor: Colors.white, onPressed: () {}),
      ));
    }
  }

  // ── Server dialog (for LAN IP setup) ─────────────────────────────────────
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
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Set your server IP for local network.\n'
            'Example: http://192.168.1.x:8080\n\n'
            'Leave blank to use Firebase directly.',
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
        ]),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth      = context.watch<AuthProvider>();
    final isAmharic = AppConstants.currentLanguage == 'am';
    String t(String en, String am) => isAmharic ? am : en;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(t('Account Login', 'መግቢያ ገጽ')),
        leading: const SmartBackButton(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          // ── 🔔 NOTIFICATION BELL (top right) ─────────────────────────────
          // Tap → enter email or phone → see payment approval/rejection status
          IconButton(
            icon: const Icon(Icons.notifications_rounded),
            tooltip: t('Check Payment Notifications', 'ክፍያ ማሳወቂያ'),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen())),
          ),
          // Server settings (gear icon)
          IconButton(
            icon: const Icon(Icons.settings_rounded),
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
            staticTitle: t('Sign in to Online Equb', 'ወደ ኦንላይን እቁብ ይግቡ'),
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

                // ── App logo & title ──────────────────────────────────────
                Center(child: Column(children: [
                  Container(
                    width: 84, height: 84,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(
                          color: AppColors.primary.withOpacity(0.2),
                          blurRadius: 14, offset: const Offset(0, 5))],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset('assets/images/app_icon.png',
                          width: 84, height: 84, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.savings_rounded,
                              size: 48, color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Online Equb',
                      style: TextStyle(fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary)),
                  const SizedBox(height: 4),
                  Text(t('Digital Savings & Fair Draw Platform',
                         'ዲጂታል ቁጠባና እጣ ማህበር'),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ])),
                const SizedBox(height: 28),

                // ── Role toggle: Member | Admin ───────────────────────────
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    _roleTab(0, '👤 ${t("Member", "አባል")}', isAmharic),
                    _roleTab(1, '👑 ${t("Admin", "አስተዳዳሪ")}', isAmharic),
                  ]),
                ),
                const SizedBox(height: 20),

                const SizedBox(height: 8),

                // ── Email / Username field ────────────────────────────────
                Text(t('Email or Username', 'ኢሜይል ወይም ስም'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    hintText: _loginRoleIndex == 1
                        ? 'admin@equb.et / abe@gmail.com'
                        : 'user@gmail.com',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? t('Email or username required', 'ኢሜይል ያስፈልጋል')
                      : null,
                ),
                const SizedBox(height: 16),

                // ── Password field ────────────────────────────────────────
                Text(t('Password', 'ይለፍ ቃል'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _password,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    hintText: t('Enter your password', 'ይለፍ ቃል ያስፈፅሙ'),
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) => v == null || v.length < 5
                      ? t('Min 5 characters', 'ቢያንስ 5 ቁምፊ')
                      : null,
                ),

                // ── Error message ─────────────────────────────────────────
                if (auth.error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.error, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Text(auth.error!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 13))),
                    ]),
                  ),
                ],
                const SizedBox(height: 28),

                // ── Login button ──────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: auth.loading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 3,
                    ),
                    child: auth.loading
                        ? const SizedBox(height: 22, width: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Text(t('Sign In / Login', 'ግባ'),
                            style: const TextStyle(fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Notification button ───────────────────────────────────
                // User can check payment status WITHOUT logging in
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(
                            builder: (_) => const NotificationsScreen())),
                    icon: const Icon(Icons.notifications_active_rounded,
                        color: AppColors.primary),
                    label: Text(
                      t('🔔 Check Payment Notification',
                        '🔔 ክፍያ ማሳወቂያ ተመልከት'),
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(child: Text(
                  t('Enter your email or phone to see if admin approved/rejected your payment',
                    'ኢሜይልዎ ወይም ስልክ ቁጥርዎ ያስፈፅሙ — አስተዳዳሪ ክፍያዎን ፈቅዷል ወይም ሰርዟል ለማወቅ'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11,
                      color: AppColors.textSecondary, height: 1.4),
                )),
                const SizedBox(height: 22),

                // ── Register link ─────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(t("Don't have an account? ", 'መለያ የሎትም? ')),
                  GestureDetector(
                    onTap: () => context.go('/register'),
                    child: Text(t('Register Now', 'ተመዝገብ'),
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Role tab helper ───────────────────────────────────────────────────────
  Widget _roleTab(int index, String label, bool isAmharic) {
    final sel = _loginRoleIndex == index;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _loginRoleIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: sel
              ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
              : [],
        ),
        child: Center(child: Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: sel ? AppColors.primary : AppColors.textSecondary))),
      ),
    ));
  }


}
