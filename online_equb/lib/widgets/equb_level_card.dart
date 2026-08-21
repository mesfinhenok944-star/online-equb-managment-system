import 'package:flutter/material.dart';
import '../config/theme.dart';

class EqubLevelCard extends StatelessWidget {
  final Map<String, dynamic> equb;
  final VoidCallback onTap;

  const EqubLevelCard({super.key, required this.equb, required this.onTap});

  Color get _levelColor => switch (equb['level']) {
        'low' => AppColors.low,
        'medium' => AppColors.medium,
        'high' => AppColors.high,
        _ => AppColors.primary,
      };

  String get _levelLabel => switch (equb['level']) {
        'low' => 'ዝቅተኛ',
        'medium' => 'መካከለኛ',
        'high' => 'ከፍተኛ',
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final current = int.tryParse(equb['currentParticipants'].toString()) ?? 0;
    final max = int.tryParse(equb['maxParticipants'].toString()) ?? 100;
    final price = double.tryParse(equb['price'].toString()) ?? 0;
    final prize = double.tryParse(equb['netPrize'].toString()) ?? 0;
    final progress = max > 0 ? current / max : 0.0;

    final levelKey = (equb['level'] ?? 'low').toString();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _levelColor.withOpacity(0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _levelColor.withOpacity(0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Full Hero Level Image Banner Box
              Stack(
                children: [
                  SizedBox(
                    height: 120,
                    width: double.infinity,
                    child: Image.asset(
                      'assets/images/levels/$levelKey.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/levels/${levelKey}_equb.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_levelColor, _levelColor.withOpacity(0.7)],
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.savings, color: Colors.white, size: 48),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Dark Gradient Overlay for Smart CSS Contrast
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.black54, Colors.transparent, Colors.black.withOpacity(0.8)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  // Badges
                  Positioned(
                    top: 10,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _levelColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                      ),
                      child: Text(_levelLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 12,
                    child: _statusBadge(equb['status'] ?? 'pending'),
                  ),
                  Positioned(
                    bottom: 10,
                    left: 12,
                    right: 12,
                    child: Text(
                      equb['name'] ?? '',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // Content Details
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      equb['description'] ?? '',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _infoChip(Icons.attach_money, '${_fmt(price)} ETB', AppColors.primary),
                        const SizedBox(width: 8),
                        _infoChip(Icons.emoji_events, 'Prize: ${_fmt(prize)} ETB', _levelColor),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$current / $max participants',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text('${(progress * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontSize: 12, color: _levelColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: _levelColor.withOpacity(0.15),
                        valueColor: AlwaysStoppedAnimation(_levelColor),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.visibility, size: 18),
                        label: const Text('View Details'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _levelColor,
                          minimumSize: const Size(double.infinity, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
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

  Widget _statusBadge(String status) {
    final color = switch (status) {
      'active' => AppColors.success,
      'pending' => AppColors.warning,
      'completed' => AppColors.primary,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(status.toUpperCase(),
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  Widget _infoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}
