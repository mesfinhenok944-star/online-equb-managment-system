import 'package:flutter/material.dart';
import '../../widgets/smart_back_button.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../../widgets/page_header_banner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<dynamic> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      try {
        await context.read<AuthProvider>().refreshUserProfile();
      } catch (_) {}

      final txns = await ApiService.getPaymentHistory();
      if (mounted) {
        setState(() {
          _transactions = txns;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user ?? {};
    final isAmharic = AppConstants.currentLanguage == 'am';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isAmharic ? 'የእኔ መገለጫ' : 'My Profile'),
        leading: const SmartBackButton(),
        actions: [
          if (auth.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: isAmharic ? 'ውጣ' : 'Logout',
              onPressed: () async {
                await auth.logout();
                if (context.mounted) context.go('/login');
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: PageHeaderBanner(
            color: auth.isAdmin
                ? AppColors.primaryDark
                : AppColors.primary,
            icon: auth.isAdmin
                ? Icons.admin_panel_settings_rounded
                : Icons.person_rounded,
            phrases: PageHeaderBanner.equbPhrases,
            staticTitle: auth.isSuperAdmin
                ? (isAmharic ? 'ሱፐር አስተዳዳሪ' : 'Super Admin Profile')
                : auth.isAdmin
                    ? (isAmharic ? 'አስተዳዳሪ' : 'Admin Profile')
                    : (isAmharic ? 'የእኔ መገለጫ' : 'Member Profile'),
            height: 64,
          ),
        ),
      ),

      // ── BODY: GUEST STATE VS LOGGED IN STATE ────────────────────────────────
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: !auth.isLoggedIn
            ? _buildGuestProfileView(context, isAmharic)
            : _buildLoggedInProfileView(context, auth, user, isAmharic),
      ),

      // ── BOTTOM NAVIGATION BAR ──────────────────────────────────────────────
      bottomNavigationBar: NavigationBar(
        selectedIndex: 2,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/home');
              break;
            case 1:
              context.go('/equbs');
              break;
            case 2:
              context.go('/profile');
              break;
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: isAmharic ? 'መነሻ' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.savings_outlined),
            selectedIcon: const Icon(Icons.savings),
            label: isAmharic ? 'እቁብ' : 'Equb',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outlined),
            selectedIcon: const Icon(Icons.person),
            label: isAmharic ? 'መገለጫ' : 'Profile',
          ),
        ],
      ),
    );
  }

  // ── GUEST VIEW (NOT LOGGED IN) ─────────────────────────────────────────────
  Widget _buildGuestProfileView(BuildContext context, bool isAmharic) {
    return Column(
      children: [
        const SizedBox(height: 20),
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Image.asset(
              'assets/images/app_icon.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          isAmharic ? 'ወደ ኦንላይን እቁብ እንኳን ደህና መጡ' : 'Welcome to Online Equb',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          isAmharic
              ? 'የእርስዎን መለያ ለመድረስ፣ በእቁብ ለመሳተፍ እና የዕጣ ውጤቶችን ለመከታተል እባክዎ ይግቡ።'
              : 'Please sign in or register to manage your equbs, make payments, and view wheel draw history.',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),

        // PROMINENT LOGIN BUTTON
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.login),
            label: Text(
              isAmharic ? 'ወደ መለያዎ ይግቡ (Sign In / Login)' : 'Sign In / Login to Account',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => context.go('/register'),
            icon: const Icon(Icons.person_add_outlined),
            label: Text(
              isAmharic ? 'አዲስ መለያ ይፍጠሩ (Register)' : 'Create New Account',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),

        const SizedBox(height: 36),

        // Feature overview card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isAmharic ? '✨ የስርዓቱ ዋና ጥቅሞች' : '✨ Platform Highlights',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _featureRow(Icons.verified_user, isAmharic ? '1-ለ-1 ብሔራዊ መታወቂያ' : '1-to-1 National ID Mapping', isAmharic ? 'ግልጽነት ያለው የተጠቃሚ ማረጋገጫ' : 'Unique ID verification across all levels'),
              _featureRow(Icons.admin_panel_settings, isAmharic ? 'የተመደቡ አስተዳዳሪዎች' : 'Dedicated Level Admins', isAmharic ? 'የሱፐር አስተዳዳሪና የደረጃ አስተዳዳሪዎች' : 'Super Admin & Level Admin management'),
              _featureRow(Icons.casino, isAmharic ? 'በመንኮራኩር የሚመረጥ አሸናፊ' : 'Automated Wheel Draw', isAmharic ? 'አንዱ ተጠቃሚ አንዴ ካሸነፈ በሚቀጥለው አይሳተፍም' : '1 winner per draw with winner history'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _featureRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── LOGGED IN VIEW ─────────────────────────────────────────────────────────
  Widget _buildLoggedInProfileView(
      BuildContext context, AuthProvider auth, Map<String, dynamic> user, bool isAmharic) {
    final name = (user['fullName'] ?? '${user['firstName'] ?? ''} ${user['lastName'] ?? ''}'.trim()).toString();
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'U';

    return Column(
      children: [
        // ── Profile hero card — app icon + avatar + name ──────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
            boxShadow: [BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 16,
                offset: const Offset(0, 6))],
          ),
          child: Column(
            children: [
              // App icon — round, white border
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10)],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white24,
                      child: Center(child: Text(initials,
                          style: const TextStyle(color: Colors.white,
                              fontSize: 28, fontWeight: FontWeight.bold))),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Name
              Text(
                name.isNotEmpty ? name : (isAmharic ? 'ተጠቃሚ' : 'User'),
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              // Email
              Text(
                user['email']?.toString() ?? '',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 8),
              // Verification badge
              _verificationBadge(user['verificationStatus'] as String? ?? 'pending'),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Admin Dashboard Link if Admin or Super Admin
        if (auth.isAdmin)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.go(auth.isSuperAdmin ? '/super-admin' : '/admin'),
                icon: const Icon(Icons.dashboard, color: Colors.white),
                label: Text(
                  auth.isSuperAdmin
                      ? (isAmharic ? 'ወደ ሱፐር አስተዳዳሪ ዳሽቦርድ ሂድ' : 'Open Super Admin Dashboard')
                      : (isAmharic ? 'ወደ አስተዳዳሪ ዳሽቦርድ ሂድ' : 'Open Admin Dashboard'),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),

        // Info cards
        _infoCard([
          _row(Icons.phone, isAmharic ? 'ስልክ' : 'Phone', user['phoneNumber'] ?? ''),
          _row(Icons.badge, isAmharic ? 'ብሔራዊ መታወቂያ' : 'National ID', user['nationalId'] ?? user['nationalID'] ?? 'Verified'),
          _row(Icons.location_on, isAmharic ? 'አድራሻ' : 'Address', user['address'] ?? 'Ethiopia'),
          _row(Icons.security, isAmharic ? 'ሚና' : 'Role', user['role'] ?? 'user'),
        ]),
        const SizedBox(height: 16),

        // KYC section if unverified
        if (user['verificationStatus'] != 'verified')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber, color: AppColors.warning),
                    SizedBox(width: 8),
                    Text('KYC Verification Required',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: AppColors.warning)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  isAmharic
                      ? 'እባክዎ በብሔራዊ መታወቂያዎ ማንነትዎን ያረጋግጡ።'
                      : 'Complete identity verification to join equb draws.',
                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => _showKycDialog(context),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warning,
                      minimumSize: const Size(double.infinity, 44)),
                  child: Text(isAmharic ? 'ማንነት አረጋግጥ (KYC)' : 'Complete KYC',
                      style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Transaction history
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            isAmharic ? 'የክፍያ ታሪክ' : 'Transaction History',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const CircularProgressIndicator()
        else if (_transactions.isEmpty)
          Text(
            isAmharic ? 'ምንም ክፍያዎች የሉም' : 'No transactions recorded yet',
            style: const TextStyle(color: AppColors.textSecondary),
          )
        else
          ..._transactions.map((t) => _txnTile(t)),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
            icon: const Icon(Icons.logout, color: Colors.red),
            label: Text(isAmharic ? 'ከመለያ ውጣ (Logout)' : 'Logout'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.red),
              foregroundColor: Colors.red,
            ),
          ),
        ),
      ],
    );
  }

  Widget _verificationBadge(String status) {
    final color = status == 'verified'
        ? AppColors.success
        : status == 'pending'
            ? AppColors.warning
            : AppColors.error;
    final icon = status == 'verified' ? Icons.verified : Icons.pending;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(List<Widget> rows) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(children: rows),
      );

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 12),
            SizedBox(
                width: 100,
                child: Text(label,
                    style: const TextStyle(color: AppColors.textSecondary))),
            Expanded(
                child: Text(value.isEmpty ? '—' : value,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );

  Widget _txnTile(Map<String, dynamic> t) {
    final amount = double.tryParse(t['amount'].toString()) ?? 0;
    final status = t['status'] as String? ?? '';
    final color = status == 'completed'
        ? AppColors.success
        : status == 'pending'
            ? AppColors.warning
            : AppColors.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.payment, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t['type'] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(t['paymentMethod'] ?? '',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${amount.toStringAsFixed(0)} ETB',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(status, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  void _showKycDialog(BuildContext context) {
    final nationalId = TextEditingController();
    final dob = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('KYC Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nationalId,
                decoration: const InputDecoration(labelText: 'National ID')),
            const SizedBox(height: 12),
            TextField(
                controller: dob,
                decoration: const InputDecoration(
                    labelText: 'Date of Birth (YYYY-MM-DD)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final auth = context.read<AuthProvider>();
              final uid = auth.user != null ? (auth.user!['uid'] ?? auth.user!['userId']) : null;
              try {
                if (uid != null) {
                  final FirebaseFirestore db = FirebaseFirestore.instance;
                  await db.collection('users').doc(uid.toString()).set({
                    'kyc': {
                      'nationalId': nationalId.text,
                      'dateOfBirth': dob.text,
                      'status': 'pending'
                    },
                    'verificationStatus': 'pending'
                  }, SetOptions(merge: true));
                  await auth.refreshUserProfile();
                } else {
                  await ApiService.submitKyc({
                    'nationalId': nationalId.text,
                    'dateOfBirth': dob.text,
                  });
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('KYC submitted for review')));
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to submit KYC')));
                }
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }
}
