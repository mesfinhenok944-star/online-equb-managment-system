import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../services/firestore_direct_service.dart';
import '../profile/notifications_screen.dart';
import '../equb/equb_history_screen.dart';
import '../payment/payment_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> _equbs = [];
  List<dynamic> _notifications = [];
  bool _loading    = true;
  int  _currentTab = 0;
  int  _unreadCount = 0;
  String _language = AppConstants.currentLanguage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      try {
        final fs = await FirestoreService.getEqubs();
        if (fs.isNotEmpty && mounted) {
          setState(() => _equbs = fs);
        }
      } catch (_) {}

      final equbs = await ApiService.getEqubs();
      final notifs = await ApiService.getNotifications();
      if (mounted) {
        setState(() {
          if (_equbs.isEmpty) _equbs = equbs;
          _notifications = notifs;
          _loading = false;
        });
      }
      _loadUnreadCount();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }
  Future<void> _loadUnreadCount() async {
    try {
      final auth      = context.read<AuthProvider>();
      final user      = auth.user ?? {};
      final userId    = (user['userId'] ?? user['id'] ?? user['uid'] ?? '').toString();
      final userEmail = (user['email'] ?? '').toString().toLowerCase();
      if (userId.isEmpty && userEmail.isEmpty) return;
      final notifs = await FirestoreDirectService.getNotificationsForUser(
          userId: userId, userEmail: userEmail);
      final unread = notifs.where((n) => n['isRead'] != true).length;
      if (mounted) setState(() => _unreadCount = unread);
    } catch (_) {}
  }

  void _toggleLanguage() {
    setState(() {
      _language = _language == 'en' ? 'am' : 'en';
      AppConstants.setLanguage(_language);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final isAmharic = _language == 'am';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      body: SafeArea(
        child: Column(
          children: [
            // ── Compact top bar ────────────────────────────────────────────
            _TopBar(
              user: user,
              isLoggedIn: auth.isLoggedIn,
              isSuperAdmin: auth.isSuperAdmin,
              isAdmin: auth.isAdmin,
              isAmharic: isAmharic,
              onToggleLanguage: _toggleLanguage,
              unreadCount: _unreadCount,
            ),

            // ── Content ────────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? _buildShimmer()
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      color: AppColors.primary,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Animated Hero Banner ──────────────────────
                            const _AnimatedHeroBanner(),

                            const SizedBox(height: 22),

                            // ── Section: Equb Levels ──────────────────────
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isAmharic
                                            ? 'የእቁብ ደረጃዎች'
                                            : 'Choose Your Equb Level',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.textPrimary,
                                          letterSpacing: -0.3,
                                        ),
                                      ),
                                      Text(
                                        isAmharic
                                            ? 'ደረጃ ይምረጡ • ሙሉ መረጃ ያግኙ'
                                            : 'Select a level for full details',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            // ── 3 Level Cards (stacked on mobile) ─────────
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: LayoutBuilder(
                                  builder: (ctx, constraints) {
                                final wide = constraints.maxWidth > 600;
                                if (wide) {
                                  return Row(
                                    children: [
                                      Expanded(
                                          child: _LevelCard(
                                              level: 'low',
                                              isAmharic: isAmharic,
                                              onTap: () =>
                                                  _showLevelSheet(
                                                      context, 'low',
                                                      isAmharic))),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: _LevelCard(
                                              level: 'medium',
                                              isAmharic: isAmharic,
                                              onTap: () =>
                                                  _showLevelSheet(context,
                                                      'medium', isAmharic))),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: _LevelCard(
                                              level: 'high',
                                              isAmharic: isAmharic,
                                              onTap: () =>
                                                  _showLevelSheet(
                                                      context, 'high',
                                                      isAmharic))),
                                    ],
                                  );
                                }
                                return Column(
                                  children: [
                                    _LevelCard(
                                        level: 'low',
                                        isAmharic: isAmharic,
                                        onTap: () => _showLevelSheet(
                                            context, 'low', isAmharic)),
                                    const SizedBox(height: 14),
                                    _LevelCard(
                                        level: 'medium',
                                        isAmharic: isAmharic,
                                        onTap: () => _showLevelSheet(
                                            context, 'medium', isAmharic)),
                                    const SizedBox(height: 14),
                                    _LevelCard(
                                        level: 'high',
                                        isAmharic: isAmharic,
                                        onTap: () => _showLevelSheet(
                                            context, 'high', isAmharic)),
                                  ],
                                );
                              }),
                            ),

                            // ── Custom levels ─────────────────────────────
                            ..._buildCustomLevels(isAmharic),

                            // ── Stats row ─────────────────────────────────
                            const SizedBox(height: 22),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: _StatsRow(isAmharic: isAmharic),
                            ),

                            // ── Notifications ─────────────────────────────
                            if (_notifications.isNotEmpty) ...[
                              const SizedBox(height: 22),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                child: Text(
                                  isAmharic
                                      ? '🔔 ቅርብ ጊዜ ማስታወቂያዎች'
                                      : '🔔 System Announcements',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(height: 10),
                              ..._notifications
                                  .take(3)
                                  .map((n) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 4),
                                        child: _NotifTile(notif: n),
                                      )),
                            ],

                            const SizedBox(height: 30),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),

      // ── Bottom Navigation ─────────────────────────────────────────────────
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        backgroundColor: Colors.white,
        elevation: 8,
        shadowColor: Colors.black26,
        onDestinationSelected: (i) {
          setState(() => _currentTab = i);
          switch (i) {
            case 0:
              context.go('/home');
            case 1:
              context.go('/equbs');
            case 2:
              context.go('/profile');
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: isAmharic ? 'መነሻ' : 'Home',
          ),
          NavigationDestination(
            icon: const Icon(Icons.savings_outlined),
            selectedIcon: const Icon(Icons.savings_rounded),
            label: isAmharic ? 'እቁብ' : 'Equb',
          ),
          NavigationDestination(
            icon: Stack(clipBehavior: Clip.none, children: [
              Icon(auth.isAdmin
                  ? Icons.admin_panel_settings_outlined
                  : Icons.person_outline_rounded),
              if (_unreadCount > 0)
                Positioned(
                  right: -4, top: -4,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Center(child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 8, fontWeight: FontWeight.bold),
                    )),
                  ),
                ),
            ]),
            selectedIcon: Stack(clipBehavior: Clip.none, children: [
              Icon(auth.isAdmin
                  ? Icons.admin_panel_settings_rounded
                  : Icons.person_rounded),
              if (_unreadCount > 0)
                Positioned(
                  right: -4, top: -4,
                  child: Container(
                    width: 14, height: 14,
                    decoration: const BoxDecoration(
                        color: Colors.red, shape: BoxShape.circle),
                    child: Center(child: Text(
                      _unreadCount > 9 ? '9+' : '$_unreadCount',
                      style: const TextStyle(color: Colors.white,
                          fontSize: 8, fontWeight: FontWeight.bold),
                    )),
                  ),
                ),
            ]),
            label: auth.isSuperAdmin
                ? 'Super Admin'
                : auth.isAdmin
                    ? 'Admin'
                    : isAmharic
                        ? 'መገለጫ'
                        : 'Profile',
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCustomLevels(bool isAmharic) {
    final custom = _equbs
        .where((e) => !['low', 'medium', 'high'].contains(e['level']))
        .toList();
    if (custom.isEmpty) return [];
    return [
      const SizedBox(height: 22),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Text(
          isAmharic ? 'አዳዲስ የተመዘገቡ ደረጃዎች' : 'New Custom Levels',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
      const SizedBox(height: 10),
      ...custom.map((eq) => Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            child: _CustomLevelTile(
              equb: Map<String, dynamic>.from(eq),
              isAmharic: isAmharic,
            ),
          )),
    ];
  }

  // ── Level bottom sheet ────────────────────────────────────────────────────
  void _showLevelSheet(
      BuildContext context, String level, bool isAmharic) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LevelDetailSheet(
        level: level,
        isAmharic: isAmharic,
        onPayment: () {
          Navigator.pop(context);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      PaymentScreen(initialLevel: level)));
        },
        onHistory: () {
          Navigator.pop(context);
          Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      EqubHistoryScreen(initialLevel: level)));
        },
        onGoEqubs: () {
          Navigator.pop(context);
          final auth = context.read<AuthProvider>();
          if (!auth.isLoggedIn) {
            context.go('/login');
          } else {
            context.go('/equbs');
          }
        },
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade300,
      highlightColor: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: List.generate(
            4,
            (i) => Container(
              height: i == 0 ? 200 : 110,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TopBar
// ─────────────────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final Map<String, dynamic>? user;
  final bool isLoggedIn, isSuperAdmin, isAdmin, isAmharic;
  final VoidCallback onToggleLanguage;
  final int unreadCount;

  const _TopBar({
    required this.user,
    required this.isLoggedIn,
    required this.isSuperAdmin,
    required this.isAdmin,
    required this.isAmharic,
    required this.onToggleLanguage,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final name = (user?['fullName'] ?? user?['firstName'] ?? '').toString().trim();
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'G';
    final roleLabel = isSuperAdmin
        ? '👑 Super Admin'
        : isAdmin
            ? '🛡️ Level Admin'
            : isLoggedIn
                ? '👤 Active Member'
                : (isAmharic ? 'ዲጂታል እቁብ ማህበር' : 'Digital Equb Platform');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D1B2A), Color(0xFF1A237E), Color(0xFF283593)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(color: Color(0x441A237E), blurRadius: 18, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
              ),
              border: Border.all(color: Colors.white30, width: 1.5),
            ),
            child: Center(
              child: Text(initials,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoggedIn
                      ? (isAmharic ? 'ሰላም፣ $name!' : 'Hello, $name!')
                      : (isAmharic ? 'እንኳን ደህና መጡ!' : 'Welcome!'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  roleLabel,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
          // Notification bell
          if (isLoggedIn) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              ),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Stack(clipBehavior: Clip.none, children: [
                  const Center(
                    child: Icon(Icons.notifications_rounded,
                        color: Colors.white, size: 20),
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 4, top: 4,
                      child: Container(
                        width: 14, height: 14,
                        decoration: const BoxDecoration(
                            color: Colors.red, shape: BoxShape.circle),
                        child: Center(child: Text(
                          unreadCount > 9 ? '9+' : '$unreadCount',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 8, fontWeight: FontWeight.bold),
                        )),
                      ),
                    ),
                ]),
              ),
            ),
          ],
          const SizedBox(width: 8),
          // Language toggle
          GestureDetector(
            onTap: onToggleLanguage,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language_rounded,
                      color: Colors.white70, size: 15),
                  const SizedBox(width: 4),
                  Text(
                    isAmharic ? 'EN' : 'አማ',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AnimatedHeroBanner
// Rotates through 6 slides every 3.5 s:
//   slide 0 – English title + tagline
//   slide 1 – Amharic title + tagline
//   slide 2 – Info: 1-to-1 ID rule
//   slide 3 – Info: automated draw
//   slide 4 – Info: three levels
//   slide 5 – Info: privacy & security
// ─────────────────────────────────────────────────────────────────────────────
class _AnimatedHeroBanner extends StatefulWidget {
  const _AnimatedHeroBanner();

  @override
  State<_AnimatedHeroBanner> createState() => _AnimatedHeroBannerState();
}

class _AnimatedHeroBannerState extends State<_AnimatedHeroBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  int _slideIndex = 0;

  static const _slides = [
    // ── 1. Ethiopian flag slide — Amharic primary ────────────────────────
    _Slide(
      icon: '🇪🇹',
      amTitle: 'ኢትዮጵያዊ ዲጂታል እቁብ\nስርዓት',
      enTitle: 'Ethiopian Digital Equb\nManagement System',
      amBody: 'ዘመናዊ የዲጂታል ቁጠባ ማህበር\nሁሉም አባሎች ፍትሃዊ ዕጣ ያሸንፋሉ',
      enBody: 'A modern digital savings circle\nFair wheel draw for every member',
      color1: Color(0xFF004D00),
      color2: Color(0xFF009A44),
      accent: Color(0xFFFFD700),
    ),
    // ── 2. Low level ─────────────────────────────────────────────────────
    _Slide(
      icon: '💰',
      amTitle: 'ዝቅተኛ ደረጃ እቁብ',
      enTitle: 'Low Level Equb',
      amBody: '1,000 – 5,000 ብር ሳምንታዊ ክፍያ\nድል አበል እስከ 495,000 ብር',
      enBody: '1,000 – 5,000 ETB per week\nNet Prize up to 495,000 ETB',
      color1: Color(0xFF0D47A1),
      color2: Color(0xFF1976D2),
      accent: Color(0xFF82B1FF),
    ),
    // ── 3. Medium level ──────────────────────────────────────────────────
    _Slide(
      icon: '⭐',
      amTitle: 'መካከለኛ ደረጃ እቁብ',
      enTitle: 'Medium Level Equb',
      amBody: '6,000 – 10,000 ብር ሳምንታዊ ክፍያ\nድል አበል እስከ 990,000 ብር',
      enBody: '6,000 – 10,000 ETB per week\nNet Prize up to 990,000 ETB',
      color1: Color(0xFFBF360C),
      color2: Color(0xFFE64A19),
      accent: Color(0xFFFFD180),
    ),
    // ── 4. High level ────────────────────────────────────────────────────
    _Slide(
      icon: '👑',
      amTitle: 'ከፍተኛ ደረጃ እቁብ',
      enTitle: 'High Level Equb',
      amBody: '11,000 – 20,000 ብር ሳምንታዊ ክፍያ\nድል አበል እስከ 1,980,000 ብር',
      enBody: '11,000 – 20,000 ETB per week\nNet Prize up to 1,980,000 ETB',
      color1: Color(0xFF4A148C),
      color2: Color(0xFF6A1B9A),
      accent: Color(0xFFCE93D8),
    ),
    // ── 5. 1-to-1 ID ─────────────────────────────────────────────────────
    _Slide(
      icon: '🪪',
      amTitle: '1-ለ-1 ብሔራዊ\nመታወቂያ ማረጋገጫ',
      enTitle: '1-to-1 National ID\nVerification',
      amBody: 'ሁሉም አባሎች በልዩ መታወቂያ ይመዘገባሉ\nድርብ ምዝገባ አይፈቀድም',
      enBody: 'Each member registers with one unique ID\nDuplicates are not allowed',
      color1: Color(0xFF004D40),
      color2: Color(0xFF00695C),
      accent: Color(0xFF80CBC4),
    ),
    // ── 6. Wheel draw ────────────────────────────────────────────────────
    _Slide(
      icon: '🎡',
      amTitle: 'ፍትሃዊ የዕጣ\nሥዕሉ ዙር',
      enTitle: 'Fair Wheel\nDraw Algorithm',
      amBody: 'አሸናፊ ዕጣ ዙር ያወጣዋል — ሁሉም እኩል ዕድል\nያሸነፈ ሰው ቀጣዩን ዕጣ አይሳተፍም',
      enBody: 'Live wheel selects one winner per round\nPast winners excluded from future draws',
      color1: Color(0xFF7F0000),
      color2: Color(0xFFC62828),
      accent: Color(0xFFFFD700),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0.06, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    _ctrl.forward();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (!mounted) return;
      _ctrl.reverse().then((_) {
        if (!mounted) return;
        setState(
            () => _slideIndex = (_slideIndex + 1) % _slides.length);
        _ctrl.forward();
        _startAutoPlay();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = _slides[_slideIndex];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [slide.color1, slide.color2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: slide.accent.withOpacity(0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: slide.color1.withOpacity(0.45),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                // ── decorative circles ───────────────────────────────
                Positioned(
                  right: -30,
                  top: -30,
                  child: _DecorCircle(
                      size: 130, color: slide.accent.withOpacity(0.12)),
                ),
                Positioned(
                  left: -20,
                  bottom: -20,
                  child: _DecorCircle(
                      size: 90, color: Colors.white.withOpacity(0.06)),
                ),
                Positioned(
                  right: 60,
                  bottom: -10,
                  child: _DecorCircle(
                      size: 60, color: slide.accent.withOpacity(0.1)),
                ),

                // ── content ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon + slide indicators
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Big icon
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: slide.accent.withOpacity(0.4),
                                  width: 1.5),
                            ),
                            child: Center(
                              child: Text(slide.icon,
                                  style: const TextStyle(fontSize: 28)),
                            ),
                          ),
                          const Spacer(),
                          // Dot indicators
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  _slides.length,
                                  (i) => AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    width: i == _slideIndex ? 18 : 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(left: 4),
                                    decoration: BoxDecoration(
                                      color: i == _slideIndex
                                          ? slide.accent
                                          : Colors.white30,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Subtitle badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: slide.accent.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: slide.accent.withOpacity(0.4)),
                                ),
                                child: Text(
                                  '${_slideIndex + 1} / ${_slides.length}',
                                  style: TextStyle(
                                    color: slide.accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Amharic title — PRIMARY: very large, bold, white
                      Text(
                        slide.amTitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                          letterSpacing: 0.1,
                          shadows: [
                            Shadow(color: Colors.black54, blurRadius: 6)
                          ],
                        ),
                      ),

                      const SizedBox(height: 6),

                      // English title — secondary
                      Text(
                        slide.enTitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.78),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Amharic body — bold
                      Text(
                        slide.amBody,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.45,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // English body
                      Text(
                        slide.enBody,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.70),
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Accent divider
                      Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              slide.accent.withOpacity(0),
                              slide.accent,
                              slide.accent.withOpacity(0),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Immutable slide data — bilingual
class _Slide {
  final String icon, amTitle, enTitle, amBody, enBody;
  final Color color1, color2, accent;
  const _Slide({
    required this.icon,
    required this.amTitle,
    required this.enTitle,
    required this.amBody,
    required this.enBody,
    required this.color1,
    required this.color2,
    required this.accent,
  });
}

// Decorative background circle
class _DecorCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _DecorCircle({required this.size, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _LevelCard  — animated tap card for each equb level
// ─────────────────────────────────────────────────────────────────────────────
class _LevelCard extends StatefulWidget {
  final String level;
  final bool isAmharic;
  final VoidCallback onTap;
  const _LevelCard(
      {required this.level, required this.isAmharic, required this.onTap});

  @override
  State<_LevelCard> createState() => _LevelCardState();
}

class _LevelCardState extends State<_LevelCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _press;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _press, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  static const _levelData = {
    'low': {
      'en_title': 'Low Level Equb',
      'am_title': 'ዝቅተኛ ደረጃ እቁብ',
      'price_en': '1,000 – 5,000 ETB',
      'price_am': '1,000 – 5,000 ብር',
      'prize_en': 'Up to 495,000 ETB',
      'prize_am': 'እስከ 495,000 ብር',
      'cycle_en': 'Weekly · Every Sunday',
      'cycle_am': 'ሳምንታዊ · እሑድ',
      'color1': Color(0xFF0D47A1),
      'color2': Color(0xFF1976D2),
      'accent': Color(0xFF82B1FF),
      'icon': Icons.trending_up_rounded,
      'emoji': '💰',
      'image': 'low',
    },
    'medium': {
      'en_title': 'Medium Level Equb',
      'am_title': 'መካከለኛ ደረጃ እቁብ',
      'price_en': '6,000 – 10,000 ETB',
      'price_am': '6,000 – 10,000 ብር',
      'prize_en': 'Up to 990,000 ETB',
      'prize_am': 'እስከ 990,000 ብር',
      'cycle_en': 'Weekly / Bi-Weekly',
      'cycle_am': 'ሳምንታዊ / ሁለት ሳምንት',
      'color1': Color(0xFFBF360C),
      'color2': Color(0xFFE64A19),
      'accent': Color(0xFFFFD180),
      'icon': Icons.stars_rounded,
      'emoji': '⭐',
      'image': 'medium',
    },
    'high': {
      'en_title': 'High Level Equb',
      'am_title': 'ከፍተኛ ደረጃ እቁብ',
      'price_en': '11,000 – 20,000 ETB',
      'price_am': '11,000 – 20,000 ብር',
      'prize_en': 'Up to 1,980,000 ETB',
      'prize_am': 'እስከ 1,980,000 ብር',
      'cycle_en': 'Weekly / Monthly',
      'cycle_am': 'ሳምንታዊ / ወርሃዊ',
      'color1': Color(0xFF4A148C),
      'color2': Color(0xFF6A1B9A),
      'accent': Color(0xFFCE93D8),
      'icon': Icons.workspace_premium_rounded,
      'emoji': '👑',
      'image': 'high',
    },
  };

  @override
  Widget build(BuildContext context) {
    final d = _levelData[widget.level]!;
    final c1 = d['color1'] as Color;
    final c2 = d['color2'] as Color;
    final accent = d['accent'] as Color;
    final icon = d['icon'] as IconData;
    final title =
        widget.isAmharic ? d['am_title'] as String : d['en_title'] as String;
    final price =
        widget.isAmharic ? d['price_am'] as String : d['price_en'] as String;
    final prize =
        widget.isAmharic ? d['prize_am'] as String : d['prize_en'] as String;
    final cycle =
        widget.isAmharic ? d['cycle_am'] as String : d['cycle_en'] as String;
    final imgKey = d['image'] as String;

    return GestureDetector(
      onTapDown: (_) => _press.forward(),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
      },
      onTapCancel: () => _press.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: c1.withOpacity(0.45),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              // Background hero image
              Positioned.fill(
                child: Image.asset(
                  'assets/images/levels/$imgKey.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [c1, c2],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
              ),
              // Gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        c1.withOpacity(0.75),
                        c2.withOpacity(0.55),
                        Colors.black.withOpacity(0.90),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              // Decorative accent circle
              Positioned(
                right: -20,
                top: -20,
                child: _DecorCircle(
                    size: 100, color: accent.withOpacity(0.15)),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Icon badge
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: accent.withOpacity(0.6), width: 1.5),
                          ),
                          child: Icon(icon, color: Colors.white, size: 22),
                        ),
                        // Prize badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                                color: accent.withOpacity(0.5), width: 1),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.emoji_events_rounded,
                                  color: accent, size: 13),
                              const SizedBox(width: 4),
                              Text(
                                prize,
                                style: TextStyle(
                                  color: accent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _CardChip(
                        icon: Icons.payments_rounded,
                        label: price,
                        accent: accent),
                    const SizedBox(height: 5),
                    _CardChip(
                        icon: Icons.calendar_month_rounded,
                        label: cycle,
                        accent: Colors.white70),
                    const SizedBox(height: 16),
                    // CTA button
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 6,
                              offset: Offset(0, 3)),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.touch_app_rounded, color: c1, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            widget.isAmharic
                                ? 'ሙሉ መረጃ ይመልከቱ'
                                : 'View Full Details',
                            style: TextStyle(
                              color: c1,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  const _CardChip(
      {required this.icon, required this.label, required this.accent});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  color: accent, fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _LevelDetailSheet  — full bottom sheet with specs + action buttons
// ─────────────────────────────────────────────────────────────────────────────
class _LevelDetailSheet extends StatelessWidget {
  final String level;
  final bool isAmharic;
  final VoidCallback onPayment, onHistory, onGoEqubs;

  const _LevelDetailSheet({
    required this.level,
    required this.isAmharic,
    required this.onPayment,
    required this.onHistory,
    required this.onGoEqubs,
  });

  static const _sheetData = {
    'low': {
      'color': Color(0xFF1565C0),
      'accent': Color(0xFF82B1FF),
      'en_title': 'Low Level Equb',
      'am_title': 'ዝቅተኛ ደረጃ እቁብ',
      'icon': Icons.trending_up_rounded,
      'image': 'low',
    },
    'medium': {
      'color': Color(0xFFD84315),
      'accent': Color(0xFFFFD180),
      'en_title': 'Medium Level Equb',
      'am_title': 'መካከለኛ ደረጃ እቁብ',
      'icon': Icons.stars_rounded,
      'image': 'medium',
    },
    'high': {
      'color': Color(0xFF6A1B9A),
      'accent': Color(0xFFCE93D8),
      'en_title': 'High Level Equb',
      'am_title': 'ከፍተኛ ደረጃ እቁብ',
      'icon': Icons.workspace_premium_rounded,
      'image': 'high',
    },
  };

  @override
  Widget build(BuildContext context) {
    final d = _sheetData[level]!;
    final color = d['color'] as Color;
    final accent = d['accent'] as Color;
    final icon = d['icon'] as IconData;
    final title =
        isAmharic ? d['am_title'] as String : d['en_title'] as String;
    final imgKey = d['image'] as String;

    final price =
        AppConstants.getLevelPriceRange(level, isAmharic: isAmharic);
    final prize = AppConstants.getLevelNetPrize(level, isAmharic: isAmharic);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),

            // Hero image + title row
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                children: [
                  Image.asset(
                    'assets/images/levels/$imgKey.jpg',
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 140,
                      color: color,
                    ),
                  ),
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          color.withOpacity(0.6),
                          Colors.black.withOpacity(0.65),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 14,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(icon, color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 4)
                              ],
                            ),
                          ),
                        ]),
                        Text(
                          isAmharic
                              ? 'ሙሉ መግለጫ'
                              : 'Full Level Specifications',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Specs
            Text(
              isAmharic ? '📋 የደረጃ መለኪያዎች' : '📋 Level Specifications',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _SpecRow(
              icon: Icons.payments_rounded,
              label: isAmharic ? 'ክፍያ' : 'Contribution',
              value: price,
              color: color,
            ),
            _SpecRow(
              icon: Icons.emoji_events_rounded,
              label: isAmharic ? 'የድል አበል' : 'Net Prize',
              value: prize,
              color: Colors.amber.shade700,
            ),
            _SpecRow(
              icon: Icons.groups_rounded,
              label: isAmharic ? 'ተሳታፊዎች' : 'Participants',
              value: isAmharic ? '100+ (እስከ 1,000)' : '100+ (up to 1,000)',
              color: Colors.teal,
            ),
            _SpecRow(
              icon: Icons.casino_rounded,
              label: isAmharic ? 'ዕጣ ዓይነት' : 'Draw Type',
              value: isAmharic ? 'ዕጣ መንኮራኩር (Random.secure)' : 'Spin Wheel (Random.secure)',
              color: const Color(0xFF6A1B9A),
            ),
            _SpecRow(
              icon: Icons.verified_user_rounded,
              label: isAmharic ? 'ማረጋገጫ' : 'Verification',
              value: isAmharic ? '1-ለ-1 ብሔራዊ መታወቂያ' : '1-to-1 National ID',
              color: Colors.green.shade700,
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 14),

            // Action buttons
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPayment,
                icon: const Icon(Icons.payments_rounded, color: Colors.white),
                label: Text(
                  isAmharic
                      ? '💳 ክፍያ ፈጽሙ / ደረሰኝ ያያይዙ'
                      : '💳 Pay Contribution / Submit Receipt',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onGoEqubs,
                icon: const Icon(Icons.savings_rounded, color: Colors.white),
                label: Text(
                  isAmharic ? 'ወደ እቁብ ዳሽቦርድ ሂድ' : 'Go to Equb Dashboard',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onHistory,
                icon: Icon(Icons.history_rounded, color: color),
                label: Text(
                  isAmharic ? '📜 የእጣ ታሪክ ይመልከቱ' : '📜 View Draw History',
                  style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: color, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  isAmharic ? 'ዝጋ' : 'Close',
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _SpecRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: color.withOpacity(0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    shape: BoxShape.circle),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: color),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatsRow — quick-glance stats bar
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  final bool isAmharic;
  const _StatsRow({required this.isAmharic});

  @override
  Widget build(BuildContext context) {
    final items = [
      _StatItem(
          icon: '🏆',
          value: '3',
          label: isAmharic ? 'ደረጃዎች' : 'Levels'),
      _StatItem(
          icon: '🔒',
          value: '1:1',
          label: isAmharic ? 'ID ማረጋገጫ' : 'ID Verified'),
      _StatItem(
          icon: '🎡',
          value: '100%',
          label: isAmharic ? 'ፍትሃዊ ዕጣ' : 'Fair Draw'),
      _StatItem(
          icon: '☁️',
          value: 'Live',
          label: isAmharic ? 'Firebase' : 'Firebase'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: items.map((e) => _buildStat(e)).toList(),
      ),
    );
  }

  Widget _buildStat(_StatItem item) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(item.icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(
            item.value,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary),
          ),
          Text(
            item.label,
            style: const TextStyle(
                fontSize: 10, color: AppColors.textSecondary),
          ),
        ],
      );
}

class _StatItem {
  final String icon, value, label;
  const _StatItem({required this.icon, required this.value, required this.label});
}

// ─────────────────────────────────────────────────────────────────────────────
// _CustomLevelTile
// ─────────────────────────────────────────────────────────────────────────────
class _CustomLevelTile extends StatelessWidget {
  final Map<String, dynamic> equb;
  final bool isAmharic;
  const _CustomLevelTile({required this.equb, required this.isAmharic});

  @override
  Widget build(BuildContext context) {
    final rawPrice = equb['price'];
    final rawPrize = equb['netPrize'] ?? equb['prize'];
    final price =
        rawPrice is num ? rawPrice.toStringAsFixed(0) : '$rawPrice';
    final prize =
        rawPrize is num ? rawPrize.toStringAsFixed(0) : '$rawPrize';
    final title = equb['name']?.toString().trim().isNotEmpty == true
        ? equb['name'].toString()
        : (isAmharic ? 'አዲስ ደረጃ' : 'New Level');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.savings_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(
                      '${isAmharic ? "ክፍያ" : "Contribution"}: $price ETB  •  '
                      '${isAmharic ? "ድል አበል" : "Prize"}: $prize ETB',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _NotifTile
// ─────────────────────────────────────────────────────────────────────────────
class _NotifTile extends StatelessWidget {
  final Map<String, dynamic> notif;
  const _NotifTile({required this.notif});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_rounded,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(notif['title'] ?? '',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(
                    notif['message'] ?? '',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

// Helper extension for missing color constant
extension _ColorAlpha on Color {
  Color withAlpha08() => withOpacity(0.08);
}
