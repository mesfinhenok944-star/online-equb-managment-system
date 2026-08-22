import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/role_management_service.dart';
import '../../utils/constants.dart';
import '../../widgets/smart_back_button.dart';

class EqubHistoryScreen extends StatefulWidget {
  final String initialLevel;
  const EqubHistoryScreen({super.key, this.initialLevel = 'low'});

  @override
  State<EqubHistoryScreen> createState() => _EqubHistoryScreenState();
}

class _EqubHistoryScreenState extends State<EqubHistoryScreen> {
  late String _selectedLevel;
  List<dynamic> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _selectedLevel = widget.initialLevel.toLowerCase().replaceAll('equb_', '');
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // Fetch level-isolated history from Firestore/RoleManagementService
      final history = await RoleManagementService.getDrawHistory(_selectedLevel);
      if (mounted) {
        setState(() {
          _history = history;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Color _levelColor(String level) {
    switch (level.toLowerCase().replaceAll('equb_', '')) {
      case 'low':
        return AppColors.low;
      case 'medium':
        return AppColors.medium;
      case 'high':
        return AppColors.high;
      default:
        return AppColors.primary;
    }
  }

  String _levelName(String level) {
    switch (level.toLowerCase().replaceAll('equb_', '')) {
      case 'low':
        return 'ዝቅተኛ (Low Level)';
      case 'medium':
        return 'መካከለኛ (Medium Level)';
      case 'high':
        return 'ከፍተኛ (High Level)';
      default:
        return level.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _levelColor(_selectedLevel);
    final isAmharic = AppConstants.currentLanguage == 'am';
    final priceRangeText = AppConstants.getLevelPriceRange(_selectedLevel, isAmharic: isAmharic);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isAmharic ? 'የእቁብ እጣ ታሪክ' : 'Equb Draw History'),
        leading: const SmartBackButton(),
        backgroundColor: currentColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // ── Level Selector Segment Header ────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: currentColor.withOpacity(0.08),
              border: Border(bottom: BorderSide(color: currentColor.withOpacity(0.2))),
            ),
            child: Column(
              children: [
                // Dedicated Current Level Header Badge (No other level buttons)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: currentColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: currentColor.withOpacity(0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        '${_levelName(_selectedLevel)} ${isAmharic ? "የአሸናፊዎች ታሪክ" : "Winners History"}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Level Price Range Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: currentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: currentColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.payments_rounded, size: 18, color: currentColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${isAmharic ? "የክፍያ መጠን" : "Contribution Range"}: $priceRangeText',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: currentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── History List ───────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _history.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history_toggle_off_rounded,
                                size: 64, color: currentColor.withOpacity(0.4)),
                            const SizedBox(height: 14),
                            Text(
                              isAmharic
                                  ? 'ለዚህ እቁብ እስካሁን የተካሄደ እጣ የለም'
                                  : 'No draw history available for this level',
                              style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isAmharic
                                  ? 'በየሳምንቱ የሚወጡ አሸናፊዎች እዚህ በቋሚነት ይመዘገባሉ'
                                  : 'Weekly winners will be recorded here permanently',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _history.length,
                        itemBuilder: (context, index) {
                          final draw = _history[index] as Map<String, dynamic>;
                          final drawNum = draw['drawNumber'] ?? (index + 1);
                          final winnerName = (draw['winnerName'] ?? draw['name'] ?? '—').toString();
                          final winnerId = (draw['winnerUniqueId'] ?? draw['winnerNationalId'] ?? draw['winnerId'] ?? '—').toString();
                          final createdAt = draw['createdAt'] ?? draw['drawDate'];

                          String fullDateTimeStr = '';
                          if (createdAt != null) {
                            try {
                              final dt = createdAt is String
                                  ? DateTime.parse(createdAt)
                                  : (createdAt as dynamic).toDate();
                              final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                              final period = dt.hour >= 12 ? 'PM' : 'AM';
                              final monthStr = dt.month.toString().padLeft(2, '0');
                              final dayStr = dt.day.toString().padLeft(2, '0');
                              final minStr = dt.minute.toString().padLeft(2, '0');
                              fullDateTimeStr = '${dt.year}-$monthStr-$dayStr  •  $hour:$minStr $period';
                            } catch (_) {
                              fullDateTimeStr = createdAt.toString();
                              if (fullDateTimeStr.length > 16) {
                                fullDateTimeStr = fullDateTimeStr.substring(0, 16);
                              }
                            }
                          } else {
                            final now = DateTime.now();
                            final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
                            final period = now.hour >= 12 ? 'PM' : 'AM';
                            fullDateTimeStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}  •  $hour:${now.minute.toString().padLeft(2, '0')} $period';
                          }

                          final netPrize = AppConstants.getLevelNetPrize(_selectedLevel, isAmharic: isAmharic);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: currentColor.withOpacity(0.3), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: currentColor.withOpacity(0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Round / Week Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: currentColor,
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 14),
                                            const SizedBox(width: 4),
                                            Text(
                                              isAmharic ? '$drawNumኛ ሳምንት አሸናፊ' : 'Round #$drawNum Winner',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      // Trophy Icon
                                      Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.15),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.emoji_events, color: Colors.amber, size: 18),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: currentColor.withOpacity(0.15),
                                        child: Text(
                                          winnerName.isNotEmpty ? winnerName[0].toUpperCase() : 'W',
                                          style: TextStyle(
                                            color: currentColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              winnerName,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${isAmharic ? "መታወቂያ" : "Unique ID"}: #$winnerId',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: currentColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 18, thickness: 0.8),
                                  Row(
                                    children: [
                                      Icon(Icons.access_time_rounded, size: 14, color: Colors.grey.shade600),
                                      const SizedBox(width: 6),
                                      Text(
                                        fullDateTimeStr,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        netPrize,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: currentColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
