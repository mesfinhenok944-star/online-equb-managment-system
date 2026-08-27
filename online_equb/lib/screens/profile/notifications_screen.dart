import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_direct_service.dart';
import '../../widgets/smart_back_button.dart';
import '../../widgets/offline_banner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationsScreen
//
// Shows all payment status notifications for the logged-in user.
// Fetched from Firestore notifications collection via FirestoreDirectService.
// Types: payment_verified (green), payment_rejected (red), general (blue).
// ─────────────────────────────────────────────────────────────────────────────

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;
  bool _isAmharic = false;

  String t(String en, String am) => _isAmharic ? am : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final auth      = context.read<AuthProvider>();
      final user      = auth.user ?? {};
      final userId    = (user['userId'] ?? user['id'] ?? user['uid'] ?? '').toString();
      final userEmail = (user['email'] ?? '').toString().toLowerCase();

      if (userId.isEmpty && userEmail.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      // Use FirestoreDirectService to query notifications
      final results = await FirestoreDirectService.getNotificationsForUser(
        userId: userId,
        userEmail: userEmail,
      );

      results.sort((a, b) =>
          (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));

      if (!mounted) return;
      setState(() { _notifs = results; _loading = false; });

      // Mark all unread as read in background
      for (final n in results) {
        if (n['isRead'] == true) continue;
        final docId = (n['id'] ?? n['docId'] ?? '').toString();
        if (docId.isNotEmpty) {
          FirestoreDirectService.updateDocument(
              'notifications', docId, {'isRead': true});
        }
      }
    } catch (e) {
      debugPrint('[Notifications] $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => n['isRead'] != true).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(t('Notifications', 'ማሳወቂያዎች')),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.red, borderRadius: BorderRadius.circular(12)),
              child: Text('$unread',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
        leading: const SmartBackButton(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Text(_isAmharic ? 'EN' : 'አማ',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () => setState(() => _isAmharic = !_isAmharic),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t('Refresh', 'አድስ'),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _notifs.isEmpty
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.notifications_none_rounded,
                            size: 70, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(t('No notifications yet', 'ምንም ማሳወቂያ የለም'),
                            style: const TextStyle(fontSize: 16,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Text(
                          t(
                            'Payment approval and rejection notifications\nwill appear here.',
                            'የክፍያ ፀደቃ እና ስረዛ ማሳወቂያዎች\nእዚህ ይታያሉ።',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13,
                              color: AppColors.textSecondary),
                        ),
                      ]),
                    ))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 50),
                        itemCount: _notifs.length,
                        itemBuilder: (_, i) => _card(_notifs[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> n) {
    final title     = (n['title']     ?? '').toString();
    final body      = (n['body']      ?? '').toString();
    final type      = (n['type']      ?? '').toString();
    final isRead    = n['isRead'] == true;
    final createdAt = (n['createdAt'] ?? '').toString();
    final dateStr   = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
    final amount    = (n['amount']    ?? '').toString();
    final level     = (n['level']     ?? '').toString();

    Color typeColor;
    IconData typeIcon;
    if (type.contains('verified') || type.contains('approved')) {
      typeColor = Colors.green;
      typeIcon  = Icons.check_circle_rounded;
    } else if (type.contains('rejected')) {
      typeColor = Colors.red;
      typeIcon  = Icons.cancel_rounded;
    } else if (type.contains('draw')) {
      typeColor = const Color(0xFF009A44);
      typeIcon  = Icons.emoji_events_rounded;
    } else {
      typeColor = AppColors.primary;
      typeIcon  = Icons.notifications_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : typeColor.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isRead ? Colors.grey.shade200 : typeColor.withOpacity(0.35),
            width: isRead ? 1 : 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03),
            blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: typeColor.withOpacity(0.12), shape: BoxShape.circle),
            child: Icon(typeIcon, color: typeColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: TextStyle(
                  fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                  fontSize: 13, color: AppColors.textPrimary),
                  maxLines: 2, overflow: TextOverflow.ellipsis)),
              if (!isRead)
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: typeColor, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(fontSize: 12,
                color: AppColors.textSecondary, height: 1.4),
                maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            // Tags row
            Row(children: [
              if (level.isNotEmpty)
                _tag(level.toUpperCase(), typeColor),
              if (amount.isNotEmpty && amount != '0') ...[
                const SizedBox(width: 6),
                _tag('ETB $amount', Colors.grey.shade600),
              ],
              const Spacer(),
              if (dateStr.isNotEmpty)
                Text(dateStr, style: TextStyle(fontSize: 10,
                    color: Colors.grey.shade400)),
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(label, style: TextStyle(fontSize: 10,
        color: color, fontWeight: FontWeight.bold)),
  );
}
