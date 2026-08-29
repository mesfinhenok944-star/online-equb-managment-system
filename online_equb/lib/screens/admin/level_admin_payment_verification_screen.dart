import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/role_management_service.dart';
import '../../widgets/smart_back_button.dart';
import '../../widgets/offline_banner.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LevelAdminPaymentVerificationScreen
//
// Full payment verification dashboard for each equb level admin.
//
// Tabs:  Pending | Verified | Rejected | All
// Each card shows: fullName, memberID, email, bank, ref#, amount
//   • View Screenshot (full-size proof dialog)
//   • Approve  → status=verified  + email notification to user
//   • Reject   → reason prompt    + email notification to user
//   • Delete   → clear screenshot (free storage), mark deleted
//
// Works on real Android phone via FirestoreDirectService (JWT bypasses rules).
// ─────────────────────────────────────────────────────────────────────────────

class LevelAdminPaymentVerificationScreen extends StatefulWidget {
  final String level;
  const LevelAdminPaymentVerificationScreen({super.key, required this.level});

  @override
  State<LevelAdminPaymentVerificationScreen> createState() =>
      _LevelAdminPaymentVerificationScreenState();
}

class _LevelAdminPaymentVerificationScreenState
    extends State<LevelAdminPaymentVerificationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late String _levelKey;
  List<Map<String, dynamic>> _allPayments = [];
  bool _loading = true;
  bool _isAmharic = false;

  String t(String en, String am) => _isAmharic ? am : en;

  Color get _levelColor {
    switch (_levelKey) {
      case 'medium': return AppColors.medium;
      case 'high':   return AppColors.high;
      default:       return AppColors.low;
    }
  }

  String get _levelLabel {
    if (_isAmharic) {
      switch (_levelKey) {
        case 'medium': return 'መካከለኛ ደረጃ';
        case 'high':   return 'ከፍተኛ ደረጃ';
        default:       return 'ዝቅተኛ ደረጃ';
      }
    }
    switch (_levelKey) {
      case 'medium': return 'Medium Level';
      case 'high':   return 'High Level';
      default:       return 'Low Level';
    }
  }

  String get _adminId {
    try {
      final u = context.read<AuthProvider>().user;
      return (u?['adminId'] ?? u?['id'] ?? 'admin_$_levelKey').toString();
    } catch (_) { return 'admin_$_levelKey'; }
  }

  // ── Counts ──────────────────────────────────────────────────────────────
  int get _pendingCount  => _allPayments.where((p) {
    final s = (p['status'] ?? '').toString();
    return s == 'pending_verification' || s == 'pending';
  }).length;
  int get _verifiedCount => _allPayments.where((p) => (p['status'] ?? '') == 'verified').length;
  int get _rejectedCount => _allPayments.where((p) => (p['status'] ?? '') == 'rejected').length;

  List<Map<String, dynamic>> _filtered(String tab) {
    switch (tab) {
      case 'pending':  return _allPayments.where((p) {
        final s = (p['status'] ?? '').toString();
        return s == 'pending_verification' || s == 'pending';
      }).toList();
      case 'verified': return _allPayments.where((p) => (p['status'] ?? '') == 'verified').toList();
      case 'rejected': return _allPayments.where((p) => (p['status'] ?? '') == 'rejected').toList();
      default:         return _allPayments.where((p) => (p['status'] ?? '') != 'deleted').toList();
    }
  }

  @override
  void initState() {
    super.initState();
    _levelKey = widget.level.toLowerCase().replaceAll('equb_', '').trim();
    _tabController = TabController(length: 4, vsync: this);
    _loadPayments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── Load ─────────────────────────────────────────────────────────────────
  Future<void> _loadPayments() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list = await RoleManagementService.getPaymentsByLevel(_levelKey);
      if (mounted) setState(() { _allPayments = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Approve / Reject ──────────────────────────────────────────────────────
  Future<void> _verify(String paymentId, String status,
      {String reason = '', Map<String, dynamic>? item}) async {
    setState(() => _loading = true);
    final ok = await RoleManagementService.verifyPayment(
      paymentId: paymentId,
      status:    status,
      rejectionReason: reason,
      adminId:   _adminId,
      level:     _levelKey,
    );
    if (ok && item != null) {
      final userId    = (item['userId']    ?? '').toString();
      final userEmail = (item['email']     ?? '').toString();
      final userPhone = (item['phoneNumber'] ?? item['phone'] ?? '').toString();
      final fullName  = (item['fullName']  ?? item['name'] ?? item['firstName'] ?? '').toString();
      final amount    = (item['amount']    ?? '0').toString();
      if (userId.isNotEmpty || userEmail.isNotEmpty || userPhone.isNotEmpty) {
        await RoleManagementService.sendPaymentNotification(
          userId: userId, userEmail: userEmail,
          userPhone: userPhone, fullName: fullName,
          status: status, amount: amount,
          level: _levelKey, rejectionReason: reason,
        );
      }
    }
    if (!mounted) return;
    _snack(ok
        ? (status == 'verified'
            ? t('✅ Payment Approved! Member notified.', '✅ ክፍያ ፀድቋል! ለአባሉ ተነግሯቸዋል።')
            : t('❌ Payment Rejected. Member notified.', '❌ ክፍያ ተሰርዟል። አባሉ ተነግሯቸዋል።'))
        : t('Action failed. Check connection.', 'ተግባሩ አልተሳካም።'),
        ok ? (status == 'verified' ? Colors.green : Colors.red) : Colors.orange);
    _loadPayments();
  }

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _delete(String paymentId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          const Icon(Icons.delete_forever_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(t('Delete Record', 'መዝገብ ሰርዝ'),
              style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
        content: Text(t(
          'Delete payment record for "$name"?\n\nScreenshot will be cleared to free storage. '
          'Do this after approving or rejecting.',
          'ለ"$name" ያለው የክፍያ መዝገብ ይሰረዝ?\n\nስክሪንሽቱ ለቦታ ማስለቀቅ ይጸዳል።',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(t('Cancel', 'ሰርዝ'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(t('Delete', 'ሰርዝ'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    final deleted = await RoleManagementService.deletePayment(paymentId);
    _snack(deleted
        ? t('Record deleted. Storage cleared.', 'መዝገብ ተሰርዟል። ቦታ ተለቅቋል።')
        : t('Failed to delete.', 'ማስወገድ አልተሳካም።'),
        deleted ? Colors.green : Colors.red);
    _loadPayments();
  }

  // ── Reject reason dialog ──────────────────────────────────────────────────
  void _showRejectDialog(String paymentId, Map<String, dynamic> item) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('Rejection Reason', 'የመሰረዝ ምክንያት'),
            style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('Member will receive an email with this reason.',
                 'አባሉ ምክንያቱን ኢሜይል ይደርሳቸዋል።'),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 3,
            autofocus: true,
            decoration: InputDecoration(
              hintText: t('e.g. Wrong bank / unclear screenshot / invalid reference',
                          'ለምሳሌ: የተሳሳተ ባንክ / ደረሰኝ ግልጽ አይደለም'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel', 'ሰርዝ'))),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _verify(paymentId, 'rejected',
                  reason: ctrl.text.trim(), item: item);
            },
            icon: const Icon(Icons.cancel_rounded, size: 16),
            label: Text(t('Reject & Notify', 'ሰርዝና አሳውቅ')),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ── Screenshot proof viewer ───────────────────────────────────────────────
  void _showProof(Map<String, dynamic> item) {
    final base64Str = (item['proofScreenshotBase64'] ?? '').toString();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.all(10),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Row(children: [
              Icon(Icons.receipt_long_rounded, color: _levelColor),
              const SizedBox(width: 8),
              Expanded(child: Text(t('Payment Receipt', 'የክፍያ ደረሰኝ'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),
            const Divider(),
            // Member summary
            _infoCard(item),
            const SizedBox(height: 12),
            // Screenshot
            if (base64Str.isNotEmpty && base64Str.contains('base64,'))
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.48),
                  child: Image.memory(
                    base64Decode(base64Str.split('base64,').last),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => _noScreenshot(),
                  ),
                ),
              )
            else
              _noScreenshot(),
            // Proof hash
            if ((item['proofHash'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.verified_user_rounded, color: Colors.green, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'SHA-256: ${item['proofHash'].toString().substring(0, 20)}…',
                    style: const TextStyle(fontSize: 10, color: Colors.green,
                        fontWeight: FontWeight.bold),
                  )),
                ]),
              ),
            ],
            // Action buttons in dialog (for pending only)
            if (_isPending(item)) ...[
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () { Navigator.pop(ctx); _showRejectDialog(
                      (item['paymentId'] ?? item['id'] ?? '').toString(), item); },
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red, size: 16),
                  label: Text(t('Reject', 'ሰርዝ'), style: const TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                )),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () { Navigator.pop(ctx);
                    _verify((item['paymentId'] ?? item['id'] ?? '').toString(),
                        'verified', item: item); },
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(t('Approve', 'አረጋግጥ')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, foregroundColor: Colors.white),
                )),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  bool _isPending(Map<String, dynamic> p) {
    final s = (p['status'] ?? '').toString();
    return s == 'pending_verification' || s == 'pending';
  }

  Widget _noScreenshot() => Container(
    height: 140, width: double.infinity,
    decoration: BoxDecoration(color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10)),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.image_not_supported_rounded, color: Colors.grey.shade400, size: 40),
      const SizedBox(height: 8),
      Text(t('No screenshot', 'ምስል የለም'),
          style: const TextStyle(color: AppColors.textSecondary)),
    ]),
  );

  Widget _infoCard(Map<String, dynamic> p) {
    final name   = (p['fullName']    ?? p['name']       ?? 'Member').toString();
    final email  = (p['email']       ?? '').toString();
    final memId  = (p['nationalId']  ?? p['uniqueId']   ?? '—').toString();
    final bank   = (p['bankName']    ?? 'Bank').toString();
    final ref    = (p['referenceNumber'] ?? '—').toString();
    final amount = (p['amount']      ?? 0).toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _levelColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _levelColor.withOpacity(0.2)),
      ),
      child: Column(children: [
        _infoRow(Icons.person,           t('Name',    'ስም'),          name),
        _infoRow(Icons.badge_rounded,    t('ID',      'መታወቂያ'),      memId),
        _infoRow(Icons.email_outlined,   t('Email',   'ኢሜይል'),       email),
        _infoRow(Icons.account_balance,  t('Bank',    'ባንክ'),         bank),
        _infoRow(Icons.receipt_long,     t('Ref #',   'ቁጥር'),        ref),
        _infoRow(Icons.payments_rounded, t('Amount',  'መጠን'),        '$amount ETB'),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(children: [
      Icon(icon, size: 14, color: _levelColor),
      const SizedBox(width: 6),
      SizedBox(width: 58, child: Text(label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
      Expanded(child: Text(value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis, maxLines: 1)),
    ]),
  );

  void _snack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: bg,
        duration: const Duration(seconds: 4)));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('$_levelLabel — ${t("Payments", "ክፍያዎች")}'),
        leading: const SmartBackButton(),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Text(_isAmharic ? 'EN' : 'አማ',
                style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () => setState(() => _isAmharic = !_isAmharic),
          ),
          IconButton(icon: const Icon(Icons.refresh_rounded),
              tooltip: t('Refresh', 'አድስ'), onPressed: _loadPayments),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(text: '${t("Pending", "በመጠበቅ")} ${_pendingCount > 0 ? "($_pendingCount)" : ""}'),
            Tab(text: '${t("Approved", "ፀድቋል")} ${_verifiedCount > 0 ? "($_verifiedCount)" : ""}'),
            Tab(text: '${t("Rejected", "ተሰርዟል")} ${_rejectedCount > 0 ? "($_rejectedCount)" : ""}'),
            Tab(text: t('All', 'ሁሉም')),
          ],
        ),
      ),
      body: Column(children: [
        const OfflineBanner(),
        Expanded(
          child: _loading
              ? Center(child: CircularProgressIndicator(color: _levelColor))
              : TabBarView(
                  controller: _tabController,
                  children: ['pending', 'verified', 'rejected', 'all']
                      .map((tab) => _paymentList(_filtered(tab), tab))
                      .toList(),
                ),
        ),
      ]),
    );
  }

  Widget _paymentList(List<Map<String, dynamic>> items, String tab) {
    if (items.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long_outlined, size: 56, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(
          tab == 'pending'  ? t('No pending payments', 'ምንም ያልፀደቀ ክፍያ የለም')
        : tab == 'verified' ? t('No approved payments', 'ምንም የፀደቀ ክፍያ የለም')
        : tab == 'rejected' ? t('No rejected payments', 'ምንም የተሰረዘ ክፍያ የለም')
        : t('No payment records', 'ምንም ክፍያ አልተገኘም'),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _loadPayments,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
        itemCount: items.length,
        itemBuilder: (_, i) => _paymentCard(items[i]),
      ),
    );
  }

  Widget _paymentCard(Map<String, dynamic> item) {
    final pId     = (item['paymentId'] ?? item['id'] ?? '').toString();
    final name    = (item['fullName']  ?? item['name'] ?? 'Member').toString();
    final email   = (item['email']     ?? '').toString();
    final memId   = (item['nationalId'] ?? item['uniqueId'] ?? '—').toString();
    final bank    = (item['bankName']  ?? 'Bank').toString();
    final ref     = (item['referenceNumber'] ?? '—').toString();
    final amount  = (item['amount']    ?? 0).toString();
    final status  = (item['status']    ?? 'pending_verification').toString();
    final isPending  = _isPending(item);
    final isVerified = status == 'verified';
    final isRejected = status == 'rejected';
    final rejReason  = (item['rejectionReason'] ?? '').toString();
    final createdAt  = (item['createdAt'] ?? '').toString();
    final dateStr    = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt;

    Color statusColor = isPending  ? Colors.orange.shade800
                      : isVerified ? Colors.green
                      : isRejected ? Colors.red
                      : Colors.grey;
    String statusLabel = isPending  ? t('PENDING',   'በመጠበቅ')
                       : isVerified ? t('APPROVED',  'ፀድቋል')
                       : isRejected ? t('REJECTED',  'ተሰርዟል')
                       : t('DELETED', 'ተሰርዟል');
    IconData statusIcon = isPending  ? Icons.hourglass_top_rounded
                        : isVerified ? Icons.check_circle_rounded
                        : isRejected ? Icons.cancel_rounded
                        : Icons.delete_rounded;

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Column(children: [
        // ── Status bar ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Icon(statusIcon, color: statusColor, size: 16),
            const SizedBox(width: 6),
            Text(statusLabel, style: TextStyle(color: statusColor,
                fontWeight: FontWeight.bold, fontSize: 12)),
            const Spacer(),
            if (dateStr.isNotEmpty)
              Text(dateStr, style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(width: 8),
            Text('$amount ETB', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: _levelColor)),
          ]),
        ),

        // ── Body ────────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Name + avatar
            Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: _levelColor.withOpacity(0.15),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'M',
                    style: TextStyle(color: _levelColor,
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15),
                    overflow: TextOverflow.ellipsis),
                Text(email, style: const TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis),
              ])),
            ]),
            const SizedBox(height: 10),

            // Member ID — prominent
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _levelColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _levelColor.withOpacity(0.2)),
              ),
              child: Row(children: [
                Icon(Icons.badge_rounded, size: 15, color: _levelColor),
                const SizedBox(width: 6),
                Text(t('Member ID: ', 'መታወቂያ: '),
                    style: const TextStyle(fontSize: 11,
                        color: AppColors.textSecondary)),
                Expanded(child: Text(memId, style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold,
                    color: _levelColor), overflow: TextOverflow.ellipsis)),
              ]),
            ),
            const SizedBox(height: 8),

            // Bank + reference
            Row(children: [
              Icon(Icons.account_balance, size: 14,
                  color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(child: Text(bank,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600))),
              Icon(Icons.receipt_long, size: 14,
                  color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(ref, style: TextStyle(fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700)),
            ]),

            // Rejection reason
            if (isRejected && rejReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Icon(Icons.info_outline, color: Colors.red, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(rejReason, style: const TextStyle(
                      fontSize: 11, color: Colors.red))),
                ]),
              ),
            ],
            const SizedBox(height: 12),

            // ── Action buttons ─────────────────────────────────────────────
            Row(children: [
              // View screenshot
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _showProof(item),
                icon: const Icon(Icons.remove_red_eye_rounded, size: 15),
                label: Text(t('View Receipt', 'ደረሰኝ')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade700,
                  side: BorderSide(color: Colors.blue.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              )),
              if (isPending) ...[
                const SizedBox(width: 6),
                // Reject
                IconButton(
                  icon: const Icon(Icons.cancel_rounded,
                      color: Colors.red, size: 26),
                  tooltip: t('Reject', 'ሰርዝ'),
                  onPressed: () => _showRejectDialog(pId, item),
                  constraints: const BoxConstraints(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                // Approve
                Expanded(child: ElevatedButton.icon(
                  onPressed: () => _verify(pId, 'verified', item: item),
                  icon: const Icon(Icons.check_circle_rounded, size: 15),
                  label: Text(t('Approve', 'አረጋግጥ')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                )),
              ],
            ]),

            // Delete button — shown after approve/reject
            if (!isPending) ...[
              const SizedBox(height: 6),
              SizedBox(width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _delete(pId, name),
                  icon: const Icon(Icons.delete_forever_rounded,
                      size: 14, color: Colors.grey),
                  label: Text(
                    t('Delete Record (Free Storage)',
                      'መዝገብ ሰርዝ — ቦታ ለቅቅ'),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}
