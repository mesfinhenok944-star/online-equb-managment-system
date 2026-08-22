import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../utils/constants.dart';
import '../../services/role_management_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> _equbs = [];
  List<dynamic> _notifications = [];
  List<Map<String, dynamic>> _drawHistory = [];
  String _historyFilterLevel = 'all';
  bool _loading = true;
  int _currentTab = 0;
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
          setState(() {
            _equbs = fs;
          });
        }
      } catch (_) {}

      final equbs = await ApiService.getEqubs();
      final notifs = await ApiService.getNotifications();
      final history = await RoleManagementService.getAllDrawHistory();
      if (mounted) {
        setState(() {
          if (_equbs.isEmpty) _equbs = equbs;
          _notifications = notifs;
          _drawHistory = history;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white24,
                        child: Text(
                          (() {
                            final name =
                                (user?['fullName'] ?? user?['firstName'] ?? '')
                                    .toString()
                                    .trim();
                            return name.isNotEmpty
                                ? name[0].toUpperCase()
                                : 'G';
                          })(),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.isLoggedIn
                                  ? (isAmharic
                                      ? 'ሰላም, ${user?['fullName'] ?? user?['firstName'] ?? ''}!'
                                      : 'Hello, ${user?['fullName'] ?? user?['firstName'] ?? ''}!')
                                  : (isAmharic
                                      ? 'እንኳን ደህና መጡ!'
                                      : 'Welcome to Online Equb!'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                            Text(
                              auth.isLoggedIn
                                  ? (auth.isSuperAdmin
                                      ? '👑 Super Admin'
                                      : auth.isAdmin
                                          ? '🛡️ Level Admin'
                                          : '👤 Active Member')
                                  : (isAmharic
                                      ? 'ዲጂታል ቁጠባና እቁብ ማህበር'
                                      : 'Digital Savings & Fair Draw Platform'),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      // Language selector button
                      InkWell(
                        onTap: _toggleLanguage,
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.language,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                isAmharic ? 'አማርኛ' : 'EN',
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
                ],
              ),
            ),

            // ── Main Content ───────────────────────────────────────────────────
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _loadData,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Banner Card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF6C5CE7),
                                    Color(0xFFA29BFE)
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black12,
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: Image.asset(
                                            'assets/images/app_icon.png',
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          isAmharic
                                              ? 'ትክክለኛና ግልጽ ዲጂታል እቁብ'
                                              : 'Fair & Automated Wheel Equb',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    isAmharic
                                        ? 'በብሔራዊ መታወቂያ የተረጋገጠ (1-ለ-1 ማረጋገጫ)፣ በየደረጃው ከተመደቡ አስተዳዳሪዎች ጋር እና አሸናፊውን በየተራ የሚመርጥ ፍትሃዊ መንኮራኩር!'
                                        : 'Verified 1-to-1 National ID mapping, dedicated level admins, and automated wheel spin draws with no duplicate wins!',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                        height: 1.3),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // ── 3 EQUB LEVELS SQUARE BUTTON SECTION ──────────────────
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isAmharic ? 'የእቁብ ደረጃዎች' : 'Equb Levels',
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textPrimary),
                                    ),
                                    Text(
                                      isAmharic
                                          ? 'ሙሉ መረጃ ለማየት አዝራሩን ይጫኑ'
                                          : 'Tap any square level button for full details',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Grid of 3 Square Buttons for Low, Medium, High levels
                            LayoutBuilder(builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              return width > 600
                                  ? Row(
                                      children: [
                                        Expanded(
                                            child: _buildSquareLevelButton(
                                                'low', isAmharic)),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: _buildSquareLevelButton(
                                                'medium', isAmharic)),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: _buildSquareLevelButton(
                                                'high', isAmharic)),
                                      ],
                                    )
                                  : Column(
                                      children: [
                                        _buildSquareLevelButton(
                                            'low', isAmharic),
                                        const SizedBox(height: 14),
                                        _buildSquareLevelButton(
                                            'medium', isAmharic),
                                        const SizedBox(height: 14),
                                        _buildSquareLevelButton(
                                            'high', isAmharic),
                                      ],
                                    );
                            }),

                            const SizedBox(height: 28),

                            // ── LIVE EQUB DRAW HISTORY (ALL LEVELS) ────────────
                            _buildHomeDrawHistorySection(isAmharic),

                            const SizedBox(height: 24),

                            if (_equbs
                                .where((e) => !['low', 'medium', 'high']
                                    .contains(e['level']))
                                .isNotEmpty) ...[
                              Text(
                                isAmharic
                                    ? 'አዳዲስ የተመዘገቡ የእቁብ ደረጃዎች'
                                    : 'Newly Registered Equb Levels',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              ..._equbs
                                  .where((e) => !['low', 'medium', 'high']
                                      .contains(e['level']))
                                  .map((eq) => _buildCustomLevelCard(
                                      Map<String, dynamic>.from(eq),
                                      isAmharic)),
                              const SizedBox(height: 24),
                            ],



                            // Recent Notifications / System Announcements
                            if (_notifications.isNotEmpty) ...[
                              Text(
                                isAmharic
                                    ? 'ቅርብ ጊዜ ማስታወቂያዎች'
                                    : 'System Announcements',
                                style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              ..._notifications
                                  .take(3)
                                  .map((n) => _buildNotifTile(n)),
                            ],
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),

      // ── BOTTOM NAVIGATION BAR ──────────────────────────────────────────────
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) {
          setState(() => _currentTab = index);
          switch (index) {
            case 0:
              context.go('/home');
              break;
            case 1:
              context.go('/equbs');
              break;
            case 2:
              // Smart profile tab: if guest, opens profile screen which presents login card
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
            icon: Icon(auth.isAdmin
                ? Icons.admin_panel_settings_outlined
                : Icons.person_outlined),
            selectedIcon:
                Icon(auth.isAdmin ? Icons.admin_panel_settings : Icons.person),
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

  // ── SQUARE LEVEL BUTTON BUILDER ──────────────────────────────────────────────
  Widget _buildSquareLevelButton(String level, bool isAmharic) {
    final Map<String, dynamic> info = switch (level) {
      'low' => {
          'level': 'low',
          'title': isAmharic ? 'ዝቅተኛ ደረጃ እቁብ' : 'Low Level Equb',
          'price': AppConstants.getLevelPriceRange('low', isAmharic: isAmharic),
          'prize': AppConstants.getLevelNetPrize('low', isAmharic: isAmharic),
          'participants': '100+ Participants (Up to 1,000)',
          'participantsAm': '100+ ተሳታፊዎች (እስከ 1,000)',
          'cycle': isAmharic ? 'በየሳምንቱ (እሑድ)' : 'Weekly (Every Sunday)',
          'color': const Color(0xFF0984E3),
          'bgGradient': const [Color(0xFF74B9FF), Color(0xFF0984E3)],
          'icon': Icons.trending_up,
          'admin': 'Low Level Admin',
          'desc': isAmharic
              ? 'ተመጣጣኝ የሳምንት እቁብ (1000 - 5000 ብር ክፍያ)። ጠቅላላ የአሸናፊ ድል አበል እስከ 495,000 ብር!'
              : 'Affordable weekly Equb (1k - 5k ETB contribution) with net prize up to 495,000 ETB!',
        },
      'medium' => {
          'level': 'medium',
          'title': isAmharic ? 'መካከለኛ ደረጃ እቁብ' : 'Medium Level Equb',
          'price': AppConstants.getLevelPriceRange('medium', isAmharic: isAmharic),
          'prize': AppConstants.getLevelNetPrize('medium', isAmharic: isAmharic),
          'participants': '100+ Participants (Up to 1,000)',
          'participantsAm': '100+ ተሳታፊዎች (እስከ 1,000)',
          'cycle': isAmharic ? 'በየሳምንቱ / በየሁለት ሳምንቱ' : 'Weekly / Bi-Weekly',
          'color': const Color(0xFFE67E22),
          'bgGradient': const [Color(0xFFF39C12), Color(0xFFD35400)],
          'icon': Icons.stars,
          'admin': 'Medium Level Admin',
          'desc': isAmharic
              ? 'ለ6,000 - 10,000 ብር ተሳታፊዎች የተዘጋጀ ተመራጭ እቁብ። ጠቅላላ የአሸናፊ ድል አበል እስከ 990,000 ብር!'
              : 'Standard Equb for 6k - 10k ETB contributions with net prize up to 990,000 ETB!',
        },
      'high' => {
          'level': 'high',
          'title': isAmharic ? 'ከፍተኛ ደረጃ እቁብ' : 'High Level Equb',
          'price': AppConstants.getLevelPriceRange('high', isAmharic: isAmharic),
          'prize': AppConstants.getLevelNetPrize('high', isAmharic: isAmharic),
          'participants': '100+ Participants (Up to 1,000)',
          'participantsAm': '100+ ተሳታፊዎች (እስከ 1,000)',
          'cycle': isAmharic ? 'በየሳምንቱ / በየወሩ' : 'Weekly / Monthly',
          'color': const Color(0xFF6C5CE7),
          'bgGradient': const [Color(0xFFA29BFE), Color(0xFF6C5CE7)],
          'icon': Icons.workspace_premium,
          'admin': 'High Level Admin',
          'desc': isAmharic
              ? 'ከፍተኛ ተመላሽ ያለው ፕሪሚየም እቁብ (11,000 - 20,000 ብር ክፍያ)። ጠቅላላ የአሸናፊ ድል አበል እስከ 1,980,000 ብር!'
              : 'Premium Equb for 11k - 20k ETB contribution members with net prize up to 1,980,000 ETB!',
        },
      _ => {},
    };

    final Color mainColor = info['color'] as Color;
    final List<Color> gradient = info['bgGradient'] as List<Color>;
    final levelKey = info['level'] as String;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: mainColor.withOpacity(0.4),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showFullLevelInformation(context, info, isAmharic),
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            children: [
              // Full Hero Image Background for the entire square box
              Positioned.fill(
                child: Image.asset(
                  'assets/images/levels/$levelKey.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/levels/${levelKey}_equb.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Smart CSS-style Gradient Overlay for High Contrast Text
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        mainColor.withOpacity(0.8),
                        Colors.black.withOpacity(0.65),
                        Colors.black.withOpacity(0.92),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),

              // Content inside Card
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Small Golden Icon Avatar Preview
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFFFD700), width: 1.5),
                          ),
                          child: Icon(info['icon'] as IconData, color: Colors.white, size: 22),
                        ),
                        // Participant Badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white30, width: 1),
                          ),
                          child: Text(
                            isAmharic
                                ? (info['participantsAm'] as String)
                                : (info['participants'] as String),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      info['title'] as String,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(color: Colors.black, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.payments, color: Colors.white70, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${isAmharic ? "ክፍያ" : "Price"}: ${info['price']}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.emoji_events, color: Colors.amberAccent, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Prize: ${info['prize']}',
                              style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Tap for info button with subtle pulse/hover feel
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, color: mainColor, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            isAmharic ? 'ሙሉ መረጃ ይመልከቱ' : 'Tap for Full Information',
                            style: TextStyle(
                                color: mainColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
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

  Widget _buildCustomLevelCard(Map<String, dynamic> equb, bool isAmharic) {
    final rawPrice = equb['price'];
    final rawPrize = equb['netPrize'] ?? equb['prize'];
    final rawParticipants = equb['maxParticipants'] ?? equb['participants'];
    final price = rawPrice is num ? rawPrice.toStringAsFixed(0) : '$rawPrice';
    final prize = rawPrize is num ? rawPrize.toStringAsFixed(0) : '$rawPrize';
    final participants = rawParticipants?.toString() ?? '—';
    final title = equb['name']?.toString().trim().isNotEmpty == true
        ? equb['name'].toString()
        : (isAmharic ? 'አዲስ የእቁብ ደረጃ' : 'New Equb Level');
    final level = equb['level']?.toString().replaceAll('_', ' ') ?? '';

    final info = <String, dynamic>{
      'title': title,
      'price': '$price ETB',
      'prize': '$prize ETB',
      'participants': '$participants Participants',
      'participantsAm': '$participants ተሳታፊዎች',
      'cycle': equb['cycle']?.toString() ?? '—',
      'admin': equb['adminName']?.toString() ?? '—',
      'desc': equb['description']?.toString() ?? '',
      'icon': Icons.savings,
      'color': AppColors.primary,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showFullLevelInformation(context, info, isAmharic),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.savings, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if (level.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(level,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 12)),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '${isAmharic ? 'ክፍያ' : 'Contribution'}: $price ETB  •  $participants ${isAmharic ? 'ተሳታፊዎች' : 'participants'}',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  // ── FULL INFORMATION POPUP MODAL DIALOG ──────────────────────────────────────
  void _showFullLevelInformation(
      BuildContext context, Map<String, dynamic> info, bool isAmharic) {
    final Color mainColor = info['color'] as Color;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Modal Drag Handle
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Header Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: mainColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: mainColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: mainColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: mainColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.asset(
                            'assets/images/levels/${info['level']}.jpg',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/images/levels/${info['level']}_equb.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => CircleAvatar(
                                radius: 24,
                                backgroundColor: mainColor,
                                child: Icon(info['icon'] as IconData,
                                    color: Colors.white, size: 26),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              info['title'] as String,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: mainColor),
                            ),
                            Text(
                              isAmharic
                                  ? 'የእቁብ ደረጃ ሙሉ መግለጫ'
                                  : 'Full Level Specifications & Rules',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Specifications Table
                Text(
                  isAmharic ? '📋 የደረጃው መለኪያዎች' : '📋 Level Breakdown',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _buildInfoRow(
                    Icons.payments,
                    isAmharic ? 'የአንድ ዙር ክፍያ' : 'Contribution per Round',
                    info['price'] as String,
                    mainColor),
                _buildInfoRow(
                    Icons.emoji_events,
                    isAmharic ? 'ጠቅላላ የድል አበል' : 'Net Winner Prize',
                    info['prize'] as String,
                    Colors.amber.shade800),
                _buildInfoRow(
                    Icons.groups,
                    isAmharic ? 'የተሳታፊዎች ብዛት' : 'Total Participants',
                    isAmharic
                        ? (info['participantsAm'] as String)
                        : (info['participants'] as String),
                    AppColors.primary),
                _buildInfoRow(
                    Icons.update,
                    isAmharic ? 'የእቁቡ ዑደት' : 'Draw Schedule',
                    info['cycle'] as String,
                    Colors.teal),
                _buildInfoRow(
                    Icons.admin_panel_settings,
                    isAmharic ? 'የደረጃው አስተዳዳሪ' : 'Assigned Level Admin',
                    info['admin'] as String,
                    mainColor),

                const SizedBox(height: 20),

                // System & Fairness Guarantees
                Text(
                  isAmharic
                      ? '⚖️ ህጎች እና የደህንነት ማረጋገጫዎች'
                      : '⚖️ Platform Rules & Fairness',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                _buildRuleItem(
                  Icons.verified_user,
                  isAmharic
                      ? 'የ1-ለ-1 ብሔራዊ መታወቂያ ማረጋገጫ'
                      : 'Strict 1-to-1 National ID Mapping',
                  isAmharic
                      ? 'አንድ ተጠቃሚ በብሔራዊ መታወቂያው በአንድ ጊዜ በአንድ መለያ ብቻ ነው የሚመዘገበው። የተደራረበ መለያ አይፈቀድም።'
                      : 'Every participant is verified with a unique National ID. Duplicate or fake accounts are prohibited.',
                ),
                _buildRuleItem(
                  Icons.casino,
                  isAmharic
                      ? 'በመንኮራኩር የሚመረጥ ፍትሃዊ አሸናፊ'
                      : 'Automated Wheel Draw Algorithm',
                  isAmharic
                      ? 'አሸናፊው በቀጥታ በመንኮራኩሩ (Spin Wheel) ይመረጣል፤ ስም እና መታወቂያ በመንኮራኩሩ ላይ ይዞራሉ።'
                      : 'Draws are conducted live using an interactive Wheel of Fortune with dynamic participant segments.',
                ),
                _buildRuleItem(
                  Icons.block,
                  isAmharic
                      ? 'አንድ ጊዜ ብቻ ማሸነፍ'
                      : 'No Repeat Winners in Same Cycle',
                  isAmharic
                      ? 'አንድ ጊዜ ያሸነፈ አባል እስከ ዙሩ መጨረሻ ድረስ ከሚቀጥሉት እጣዎች ይገለላል፤ በታሪክ ውስጥ ይመዘገባል።'
                      : 'Once a user wins, they are placed in winner history and excluded from future spins until full cycle resets.',
                ),

                const SizedBox(height: 24),

                // Action Buttons
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      final auth = context.read<AuthProvider>();
                      if (!auth.isLoggedIn) {
                        context.go('/login');
                      } else {
                        context.go('/equbs');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: mainColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      context.read<AuthProvider>().isLoggedIn
                          ? (isAmharic
                              ? 'ወደ እቁብ ዝርዝር ሂድ'
                              : 'Go to Equb Dashboard')
                          : (isAmharic
                              ? 'ለመቀላቀል ይግቡ (Login)'
                              : 'Sign In to Join This Equb'),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EqubHistoryScreen(
                            initialLevel: (info['level'] ?? 'low').toString(),
                          ),
                        ),
                      );
                    },
                    icon: Icon(Icons.history, color: mainColor),
                    label: Text(
                      isAmharic ? 'የእጣ ታሪክ ይመልከቱ' : 'View Level Draw History',
                      style: TextStyle(
                        color: mainColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: mainColor, width: 1.5),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(isAmharic ? 'ዝጋ' : 'Close',
                        style: const TextStyle(color: Colors.grey)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
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
                  fontSize: 14, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleItem(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold)),
                Text(body,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifTile(Map<String, dynamic> n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n['title'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                Text(n['message'] ?? '',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── HOME PAGE LIVE EQUB DRAW HISTORY SECTION ─────────────────────────────────
  Widget _buildHomeDrawHistorySection(bool isAmharic) {
    final filteredHistory = _drawHistory.where((item) {
      if (_historyFilterLevel == 'all') return true;
      final lvl = (item['equbLevel'] ?? item['level'] ?? '')
          .toString()
          .toLowerCase()
          .replaceAll('equb_', '')
          .trim();
      return lvl == _historyFilterLevel;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withOpacity(0.18), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade600, width: 1.2),
                ),
                child: const Icon(Icons.emoji_events, color: Colors.amber, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAmharic ? '🏆 የእቁብ እጣ አሸናፊዎች ታሪክ' : '🏆 Live Equb Draw History',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isAmharic
                          ? 'በየደረጃው ያሉ የአሸናፊዎች የቀጥታ ታሪክ'
                          : 'Real-time winner records for all Equb tiers',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // View All Button
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EqubHistoryScreen(
                        initialLevel: _historyFilterLevel == 'all' ? 'low' : _historyFilterLevel,
                      ),
                    ),
                  );
                },
                child: Row(
                  children: [
                    Text(
                      isAmharic ? 'ሁሉንም' : 'View All',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 12,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Level Filter Segment Chips (All, Low, Medium, High)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('all', isAmharic ? 'ሁሉም (All)' : 'All Levels', Colors.purple, isAmharic),
                const SizedBox(width: 8),
                _buildFilterChip('low', isAmharic ? 'ዝቅተኛ (Low)' : 'Low Level', AppColors.low, isAmharic),
                const SizedBox(width: 8),
                _buildFilterChip('medium', isAmharic ? 'መካከለኛ (Med)' : 'Medium Level', AppColors.medium, isAmharic),
                const SizedBox(width: 8),
                _buildFilterChip('high', isAmharic ? 'ከፍተኛ (High)' : 'High Level', AppColors.high, isAmharic),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // History List or Empty State
          if (filteredHistory.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.history_toggle_off, size: 42, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text(
                    isAmharic ? 'እስካሁን የተካሄደ እጣ የለም' : 'No draw history recorded yet',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isAmharic
                        ? 'አስተዳዳሪው እጣ ሲያወጣ አሸናፊው እዚህ ይወጣል'
                        : 'Winners will automatically appear here when draws are conducted by admins',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredHistory.length > 5 ? 5 : filteredHistory.length,
              itemBuilder: (context, index) {
                final draw = filteredHistory[index];
                final drawNum = draw['drawNumber'] ?? (index + 1);
                final winnerName = (draw['winnerName'] ?? draw['name'] ?? '—').toString();
                final winnerId = (draw['winnerUniqueId'] ?? draw['winnerNationalId'] ?? draw['winnerId'] ?? '—').toString();
                final levelKey = (draw['equbLevel'] ?? draw['level'] ?? 'low')
                    .toString()
                    .toLowerCase()
                    .replaceAll('equb_', '')
                    .trim();
                final createdAt = draw['createdAt'] ?? draw['drawDate'];

                Color cardColor = switch (levelKey) {
                  'medium' => AppColors.medium,
                  'high' => AppColors.high,
                  _ => AppColors.low,
                };

                String dateStr = '';
                if (createdAt != null) {
                  try {
                    final dt = createdAt is String
                        ? DateTime.parse(createdAt)
                        : (createdAt as dynamic).toDate();
                    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                    final period = dt.hour >= 12 ? 'PM' : 'AM';
                    dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}  $hour:${dt.minute.toString().padLeft(2, '0')} $period';
                  } catch (_) {
                    dateStr = createdAt.toString();
                    if (dateStr.length > 16) dateStr = dateStr.substring(0, 16);
                  }
                } else {
                  final now = DateTime.now();
                  final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
                  final period = now.hour >= 12 ? 'PM' : 'AM';
                  dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}  $hour:${now.minute.toString().padLeft(2, '0')} $period';
                }

                final netPrize = AppConstants.getLevelNetPrize(levelKey, isAmharic: isAmharic);

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardColor.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardColor.withOpacity(0.25), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Level Tag Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${levelKey.toUpperCase()} LEVEL',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Round Number
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade700,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isAmharic ? '$drawNumኛ እጣ' : 'Round #$drawNum',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            netPrize,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: cardColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: cardColor.withOpacity(0.15),
                            child: Text(
                              winnerName.isNotEmpty ? winnerName[0].toUpperCase() : 'W',
                              style: TextStyle(
                                color: cardColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  winnerName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  'ID: #$winnerId  •  $dateStr',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String levelKey, String label, Color color, bool isAmharic) {
    final isSelected = _historyFilterLevel == levelKey;
    return ChoiceChip(
      selected: isSelected,
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : AppColors.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
      ),
      selectedColor: color,
      backgroundColor: Colors.grey.shade100,
      onSelected: (val) {
        if (val) {
          setState(() {
            _historyFilterLevel = levelKey;
          });
        }
      },
    );
  }
}
