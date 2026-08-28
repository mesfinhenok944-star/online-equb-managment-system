import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/firestore_direct_service.dart';
import '../../widgets/smart_back_button.dart';
import '../../widgets/offline_banner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NotificationsScreen
//
// Shows payment approval/rejection notifications for a user.
//
// TWO MODES:
//   Logged-in user → auto-loads using their profile email
//   Guest / not logged in → shows email input field to check by email
//
// HOW IT WORKS:
//   1. Admin approves/rejects payment → notification saved to Firestore
//   2. User opens this screen → sees ✅ Approved or ❌ Rejected
//   3. Notification shows: level, amount, date, admin message
//
// NO OTP NEEDED — just enter your registered email to check status.
// ─────────────────────────────────────────────────────────────────────────────

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifs  = [];
  bool    _loading    = false;
  bool    _isAmharic  = false;
  bool    _searched   = false;
  String? _emailUsed;
  String? _error;

  final _emailCtrl = TextEditingController();

  String t(String en, String am) => _isAmharic ? am : en;

  @override
  void initState() {
    super.initState();
    // If user is already logged in, load their notifications automatically
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoLoad());
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  // ── Auto-load for logged-in users ─────────────────────────────────────────
  void _autoLoad() {
    try {
      final user  = context.read<AuthProvider>().user ?? {};
      final email = (user['email'] ?? '').toString().trim().toLowerCase();
      if (email.isNotEmpty) {
        _emailCtrl.text = email;
        _loadNotifications(email);
      }
    } catch (_) {}
  }

  // ── Load notifications by email ───────────────────────────────────────────
  Future<void> _loadNotifications(String email) async {
    final em = email.trim().toLowerCase();
    if (em.isEmpty || !em.contains('@')) {
      setState(() => _error = t('Please enter a valid email address.',
                               'ትክክለኛ ኢሜይል ያስፈልጋል።'));
      return;
    }

    setState(() { _loading = true; _error = null; _searched = true; _emailUsed = em; });

    try {
      List<Map<String, dynamic>> results = [];

      // 1. Backend REST API (fastest — uses Admin SDK, no rules issue)
      try {
        final apiList = await ApiService.getNotificationsByEmail(em)
            .timeout(const Duration(seconds: 8));
        if (apiList.isNotEmpty) {
          results = apiList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
          debugPrint('[Notifications] REST → ${results.length} for $em');
        }
      } catch (e) {
        debugPrint('[Notifications] REST error: $e');
      }

      // 2. FirestoreDirectService (JWT — works without server)
      if (results.isEmpty) {
        try {
          results = await FirestoreDirectService.getNotificationsForUser(
              userId: '', userEmail: em);
          debugPrint('[Notifications] Firestore JWT → ${results.length} for $em');
        } catch (e) {
          debugPrint('[Notifications] Firestore error: $e');
        }
      }

      // Sort newest first
      results.sort((a, b) =>
          (b['createdAt']?.toString() ?? '').compareTo(a['createdAt']?.toString() ?? ''));

      if (!mounted) return;
      setState(() { _notifs = results; _loading = false; });

      // Mark unread as read in background
      for (final n in results) {
        if (n['isRead'] == true) continue;
        final docId = (n['id'] ?? n['docId'] ?? '').toString();
        if (docId.isNotEmpty) {
          FirestoreDirectService.updateDocument(
              'notifications', docId, {'isRead': true});
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error   = t('Could not load. Check your internet connection.',
                     'ሊጫን አልቻለም። ኢንተርኔት ግንኙነቱን ያረጋግጡ።');
        _loading = false;
      });
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth    = context.watch<AuthProvider>();
    final isGuest = !auth.isLoggedIn;
    final unread  = _notifs.where((n) => n['isRead'] != true).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(t('Payment Notifications', 'የክፍያ ማሳወቂያዎች')),
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
          if (_emailUsed != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: t('Refresh', 'አድስ'),
              onPressed: () => _loadNotifications(_emailCtrl.text),
            ),
        ],
      ),
      body: Column(children: [
        const OfflineBanner(),

        // ── Email input (shown for guests, or to change email) ─────────────
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Description
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  t(
                    'Enter your registered email to see if your payment was approved ✅ or rejected ❌ by the admin.',
                    'የተፈቀደ ወይም የተሰረዘ ክፍያ ለማወቅ ኢሜይልዎን ያስፈፅሙ። አስተዳዳሪ ካረጋገጠ ወይም ከሰረዘ እዚህ ይታያል።',
                  ),
                  style: const TextStyle(fontSize: 12, color: AppColors.primary, height: 1.4),
                )),
              ]),
            ),
            const SizedBox(height: 12),

            // Email field + search button
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (v) => _loadNotifications(v),
                  decoration: InputDecoration(
                    hintText: t('Enter your email (e.g. user@gmail.com)',
                                'ኢሜይልዎ (ለምሳሌ user@gmail.com)'),
                    prefixIcon: const Icon(Icons.email_outlined, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    isDense: true,
                    errorText: _error,
                    errorMaxLines: 2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onPressed: _loading
                      ? null
                      : () => _loadNotifications(_emailCtrl.text),
                  child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.search_rounded, size: 18),
                          const SizedBox(width: 4),
                          Text(t('Check', 'ፈልግ'),
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ]),
                ),
              ),
            ]),
          ]),
        ),

        // ── Notification list ──────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : !_searched
                  // Not searched yet — show instruction
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Icon(Icons.mark_email_unread_rounded,
                            size: 72, color: Colors.grey.shade300),
                        const SizedBox(height: 16),
                        Text(t('Enter your email above to check\npayment status',
                               'ላይ ኢሜይልዎን ያስፈፅሙ\nየክፍያ ሁኔታ ለማወቅ'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14,
                                color: AppColors.textSecondary, height: 1.5)),
                      ]),
                    ))
                  : _notifs.isEmpty
                      // Searched but empty
                      ? Center(child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            Icon(Icons.notifications_none_rounded,
                                size: 72, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(t('No notifications found for\n${_emailUsed ?? ''}',
                                   'ለ${_emailUsed ?? ''}\nምንም ማሳወቂያ አልተገኘም'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 14,
                                    color: AppColors.textSecondary, height: 1.5)),
                            const SizedBox(height: 12),
                            Text(
                              t(
                                'If you submitted a payment, the admin\nhas not yet approved or rejected it.',
                                'ክፍያ ካስገቡ፣ አስተዳዳሪው\nገና አልፈቀደም ወይም አልሰረዘም።',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                          ]),
                        ))
                      // Has notifications
                      : RefreshIndicator(
                          onRefresh: () => _loadNotifications(_emailCtrl.text),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 50),
                            itemCount: _notifs.length,
                            itemBuilder: (_, i) => _notifCard(_notifs[i]),
                          ),
                        ),
        ),
      ]),
    );
  }

  // ── Notification card ──────────────────────────────────────────────────────
  Widget _notifCard(Map<String, dynamic> n) {
    final title     = (n['title']     ?? '').toString();
    final body      = (n['body']      ?? '').toString();
    final type      = (n['type']      ?? '').toString();
    final isRead    = n['isRead'] == true;
    final createdAt = (n['createdAt'] ?? '').toString();
    final dateStr   = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;
    final amount    = (n['amount']    ?? '').toString();
    final level     = (n['level']     ?? '').toString();
    final paymentId = (n['paymentId'] ?? '').toString();

    // Determine type color and icon
    final isApproved = type.contains('verified') || type.contains('approved');
    final isRejected = type.contains('rejected');
    final isDraw     = type.contains('draw');

    final Color typeColor = isApproved ? Colors.green
                           : isRejected ? Colors.red
                           : isDraw ? const Color(0xFF009A44)
                           : AppColors.primary;

    final IconData typeIcon = isApproved ? Icons.check_circle_rounded
                             : isRejected ? Icons.cancel_rounded
                             : isDraw ? Icons.emoji_events_rounded
                             : Icons.notifications_rounded;

    final String statusLabel = isApproved
        ? t('✅ APPROVED', '✅ ፀድቋል')
        : isRejected
            ? t('❌ REJECTED', '❌ ተሰርዟል')
            : isDraw
                ? t('🏆 DRAW RESULT', '🏆 የዕጣ ውጤት')
                : t('📢 INFO', '📢 መረጃ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isRead ? Colors.white : typeColor.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRead ? Colors.grey.shade200 : typeColor.withOpacity(0.4),
          width: isRead ? 1 : 1.8,
        ),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
            blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        // ── Status bar ───────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: typeColor.withOpacity(0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Icon(typeIcon, color: typeColor, size: 16),
            const SizedBox(width: 6),
            Text(statusLabel,
                style: TextStyle(color: typeColor, fontWeight: FontWeight.bold,
                    fontSize: 12)),
            const Spacer(),
            if (!isRead)
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle),
              ),
            const SizedBox(width: 4),
            if (dateStr.isNotEmpty)
              Text(dateStr, style: const TextStyle(fontSize: 10,
                  color: AppColors.textSecondary)),
          ]),
        ),

        // ── Body ─────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(
                fontWeight: isRead ? FontWeight.w600 : FontWeight.bold,
                fontSize: 14, color: typeColor),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(fontSize: 13,
                color: AppColors.textSecondary, height: 1.4),
                maxLines: 4, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 10),

            // Tags: level + amount
            Row(children: [
              if (level.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: typeColor.withOpacity(0.3)),
                  ),
                  child: Text('${level.toUpperCase()} LEVEL',
                      style: TextStyle(fontSize: 10, color: typeColor,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
              ],
              if (amount.isNotEmpty && amount != '0') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Text('ETB $amount',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary)),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}
