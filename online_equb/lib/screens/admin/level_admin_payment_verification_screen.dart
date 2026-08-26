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
// Admin reviews payment submissions for their assigned equb level:
//  • Shows full name, registered member ID (uniqueId/nationalId), email
//  • Shows bank used, reference number, amount
//  • Full-screen proof screenshot viewer
//  • Approve → marks payment verified, updates user balance in Firestore
//  • Reject → prompts for reason, saves rejectionReason in Firestore
//  • Filter by: Pending / Verified / Rejected / All
// ─────────────────────────────────────────────────────────────────────────────

class LevelAdminPaymentVerificationScreen extends StatefulWidget {
  final String level;

  const LevelAdminPaymentVerificationScreen({
    super.key,
    required this.level,
  });

  @override
  State<LevelAdminPaymentVerificationScreen> createState() =>
      _LevelAdminPaymentVerificationScreenState();
}

class _LevelAdminPaymentVerificationScreenState
    extends State<LevelAdminPaymentVerificationScreen> {
  late String _levelKey;
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;
  String _filterStatus = 'pending_verification';
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
    } catch (_) {
      return 'admin_$_levelKey';
    }
  }

  @override
  void initState() {
    super.initState();
    _levelKey = widget.level.toLowerCase().replaceAll('equb_', '').trim();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final list = await RoleManagementService.getPaymentsByLevel(_levelKey);
      if (mounted) {
        setState(() { _payments = list; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Approve / Reject ──────────────────────────────────────────────────────
  Future<void> _verifyPayment(String paymentId, String status,
      {String reason = ''}) async {
    setState(() => _loading = true);
    final ok = await RoleManagementService.verifyPayment(
      paymentId: paymentId,
      status: status,
      rejectionReason: reason,
      adminId: _adminId,
      level: _levelKey,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? (status == 'verified'
                ? t('✅ Payment Approved! Member contribution updated.',
                    '✅ ክፍያ ፀድቋል! የአባሉ ሂሳብ ተሻሽሏል።')
                : t('❌ Payment Rejected.', '❌ ክፍያ ተሰርዟል።'))
            : t('Failed to update payment.', 'ሁኔታ ማዘመን አልተሳካም።')),
        backgroundColor: ok
            ? (status == 'verified' ? Colors.green : Colors.red)
            : Colors.orange,
        duration: const Duration(seconds: 3),
      ));
      _loadPayments();
    }
  }

  // ── Proof screenshot viewer ───────────────────────────────────────────────
  void _showProofDialog(Map<String, dynamic> item) {
    final base64Str = (item['proofScreenshotBase64'] ?? '').toString();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        insetPadding: const EdgeInsets.all(12),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Row(children: [
              Icon(Icons.receipt_long_rounded, color: _levelColor),
              const SizedBox(width: 8),
              Expanded(child: Text(
                t('Bank Receipt Proof', 'የባንክ ደረሰኝ ማረጋገጫ'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              )),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
            ]),

            // Payer info summary
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _levelColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _levelColor.withOpacity(0.2)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _proofInfoRow(Icons.person,        t('Name',    'ስም'),       (item['fullName'] ?? '—').toString()),
                _proofInfoRow(Icons.badge,         t('ID',      'መታወቂያ'),   (item['nationalId'] ?? item['uniqueId'] ?? '—').toString()),
                _proofInfoRow(Icons.email_outlined,t('Email',   'ኢሜይል'),    (item['email'] ?? '—').toString()),
                _proofInfoRow(Icons.payments,      t('Amount',  'መጠን'),      '${item['amount'] ?? 0} ETB'),
                _proofInfoRow(Icons.account_balance, t('Bank',  'ባንክ'),      (item['bankName'] ?? '—').toString()),
                _proofInfoRow(Icons.receipt_long,  t('Ref #',   'ቁጥር'),     (item['referenceNumber'] ?? '—').toString()),
              ]),
            ),
            const Divider(height: 20),

            // Screenshot image
            if (base64Str.isNotEmpty && base64Str.contains('base64,')) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.50,
                  ),
                  child: Image.memory(
                    base64Decode(base64Str.split('base64,').last),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      height: 150,
                      color: Colors.grey.shade200,
                      child: const Center(child: Text('Error loading image')),
                    ),
                  ),
                ),
              ),
            ] else ...[
              Container(
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.image_not_supported_rounded, color: Colors.grey.shade400, size: 40),
                  const SizedBox(height: 8),
                  Text(t('No screenshot attached', 'ምስል አልተያያዘም'),
                      style: const TextStyle(color: AppColors.textSecondary)),
                ])),
              ),
            ],

            // Security hash
            if (item['proofHash'] != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.25)),
                ),
                child: Row(children: [
                  const Icon(Icons.verified_user_rounded, color: Colors.green, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'SHA-256: ${item['proofHash'].toString().substring(0, 20)}…',
                    style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                  )),
                ]),
              ),
            ],

            // Approve / Reject from dialog
            const SizedBox(height: 14),
            if ((item['status'] ?? '').toString() == 'pending_verification' ||
                (item['status'] ?? '').toString() == 'pending') ...[
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showRejectReasonDialog((item['paymentId'] ?? item['id'] ?? '').toString());
                  },
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red),
                  label: Text(t('Reject', 'ሰርዝ'), style: const TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                )),
                const SizedBox(width: 12),
                Expanded(child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _verifyPayment((item['paymentId'] ?? item['id'] ?? '').toString(), 'verified');
                  },
                  icon: const Icon(Icons.check_circle_rounded),
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

  Widget _proofInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 14, color: _levelColor),
        const SizedBox(width: 6),
        SizedBox(width: 55, child: Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
        Expanded(child: Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── Reject reason dialog ──────────────────────────────────────────────────
  void _showRejectReasonDialog(String paymentId) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('Reason for Rejection', 'የመሰረዝ ምክንያት')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('Provide a reason so the member can resubmit correctly.',
                 'አባሉ ትክክለኛ ክፍያ ለማስገባት ያነሳሱ ምክንያት ያስፈልጋል።'),
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: t('e.g. Wrong bank, invalid reference, unclear screenshot',
                          'ለምሳሌ: የተሳሳተ ባንክ፣ ትክክለኛ ደረሰኝ ቁጥር አልተገኘም'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('Cancel', 'ሰርዝ')),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _verifyPayment(paymentId, 'rejected', reason: ctrl.text.trim());
            },
            icon: const Icon(Icons.cancel_rounded),
            label: Text(t('Confirm Reject', 'አረጋግጥና ሰርዝ')),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filtered = _payments.where((p) {
      if (_filterStatus == 'all') return true;
      final st = (p['status'] ?? 'pending_verification').toString();
      if (_filterStatus == 'pending_verification') {
        return st == 'pending_verification' || st == 'pending';
      }
      return st == _filterStatus;
    }).toList();

    final pendingCount = _payments.where((p) {
      final st = (p['status'] ?? '').toString();
      return st == 'pending_verification' || st == 'pending';
    }).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('$_levelLabel — ${t("Payment Verification", "ክፍያ ማረጋገጫ")}'),
        leading: const SmartBackButton(),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (pendingCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8, top: 10, bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.amber, borderRadius: BorderRadius.circular(12)),
              child: Text('$pendingCount ${t("pending", "በመጠበቅ")}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black)),
            ),
          IconButton(
            icon: Text(_isAmharic ? 'EN' : 'አማ',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () => setState(() => _isAmharic = !_isAmharic),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: t('Refresh', 'አድስ'),
            onPressed: _loadPayments,
          ),
        ],
      ),
      body: Column(children: [
        const OfflineBanner(),

        // Filter chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: Colors.white,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip('pending_verification', t('Pending', 'በመጠበቅ'), Colors.orange.shade800,
                  badge: pendingCount),
              const SizedBox(width: 8),
              _chip('verified',             t('Approved', 'ፀድቋል'), Colors.green),
              const SizedBox(width: 8),
              _chip('rejected',             t('Rejected', 'ተሰርዟል'), Colors.red),
              const SizedBox(width: 8),
              _chip('all',                  t('All', 'ሁሉም'), _levelColor),
            ]),
          ),
        ),

        // List
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.payments_outlined, size: 56, color: Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        _filterStatus == 'pending_verification'
                            ? t('No pending payments', 'ምንም ያልፀደቀ ክፍያ የለም')
                            : t('No payments found', 'ምንም ክፍያ አልተገኘም'),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _loadPayments,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) => _paymentCard(filtered[i]),
                      ),
                    ),
        ),
      ]),
    );
  }

  // ── Payment card ──────────────────────────────────────────────────────────
  Widget _paymentCard(Map<String, dynamic> item) {
    final pId      = (item['paymentId'] ?? item['id'] ?? '').toString();
    final fullName = (item['fullName'] ?? item['name'] ?? 'Equb Member').toString();
    final email    = (item['email'] ?? '').toString();
    final memberId = (item['nationalId'] ?? item['uniqueId'] ?? '—').toString();
    final bank     = (item['bankName'] ?? 'CBE').toString();
    final ref      = (item['referenceNumber'] ?? item['reference'] ?? '—').toString();
    final amount   = (item['amount'] ?? 0).toString();
    final status   = (item['status'] ?? 'pending_verification').toString();
    final isPending = status == 'pending_verification' || status == 'pending';
    final rejReason = (item['rejectionReason'] ?? '').toString();

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'verified':
        statusColor = Colors.green; statusLabel = t('APPROVED', 'ፀድቋል'); statusIcon = Icons.check_circle_rounded; break;
      case 'rejected':
        statusColor = Colors.red;   statusLabel = t('REJECTED', 'ተሰርዟል'); statusIcon = Icons.cancel_rounded; break;
      default:
        statusColor = Colors.orange.shade800; statusLabel = t('PENDING', 'በመጠበቅ'); statusIcon = Icons.hourglass_top_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.25), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0,3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Top status bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: statusColor.withOpacity(0.08),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(children: [
            Icon(statusIcon, color: statusColor, size: 18),
            const SizedBox(width: 6),
            Text(statusLabel,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
            const Spacer(),
            Text('$amount ETB',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _levelColor)),
          ]),
        ),

        // Body
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // Name + level badge
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _levelColor.withOpacity(0.15),
                child: Text(
                  fullName.isNotEmpty ? fullName[0].toUpperCase() : 'M',
                  style: TextStyle(color: _levelColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(fullName,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis),
                Text(email, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
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
                Icon(Icons.badge_rounded, size: 16, color: _levelColor),
                const SizedBox(width: 6),
                Text(t('Member ID: ', 'የአባል መታወቂያ: '),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                Text(memberId,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: _levelColor)),
              ]),
            ),

            const SizedBox(height: 10),

            // Bank + reference
            Row(children: [
              Icon(Icons.account_balance, size: 15, color: Colors.grey.shade500),
              const SizedBox(width: 5),
              Expanded(child: Text(bank,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              Icon(Icons.receipt_long, size: 15, color: Colors.grey.shade500),
              const SizedBox(width: 5),
              Text(ref,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
            ]),

            // Rejection reason
            if (status == 'rejected' && rejReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.2)),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.info_outline, color: Colors.red, size: 14),
                  const SizedBox(width: 6),
                  Expanded(child: Text(rejReason,
                      style: const TextStyle(fontSize: 11, color: Colors.red))),
                ]),
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(children: [
              // View proof screenshot
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _showProofDialog(item),
                icon: const Icon(Icons.remove_red_eye_rounded, size: 16),
                label: Text(t('View Receipt', 'ደረሰኝ ተመልከት')),
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    side: BorderSide(color: Colors.blue.shade300)),
              )),

              if (isPending) ...[
                const SizedBox(width: 8),
                // Reject
                IconButton(
                  icon: const Icon(Icons.cancel_rounded, color: Colors.red, size: 28),
                  tooltip: t('Reject', 'ሰርዝ'),
                  onPressed: () => _showRejectReasonDialog(pId),
                ),
                const SizedBox(width: 4),
                // Approve
                ElevatedButton.icon(
                  onPressed: () => _verifyPayment(pId, 'verified'),
                  icon: const Icon(Icons.check_circle_rounded, size: 16),
                  label: Text(t('Approve', 'አረጋግጥ')),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }

  // ── Filter chip ───────────────────────────────────────────────────────────
  Widget _chip(String key, String label, Color color, {int badge = 0}) {
    final sel = _filterStatus == key;
    return GestureDetector(
      onTap: () => setState(() => _filterStatus = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: sel ? color : Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  color: sel ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
          if (badge > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
              child: Text('$badge',
                  style: const TextStyle(fontSize: 9, color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
      ),
    );
  }
}
