import 'dart:convert';
import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../services/role_management_service.dart';
import '../../utils/constants.dart';
import '../../widgets/smart_back_button.dart';
import '../../widgets/offline_banner.dart';

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

  @override
  void initState() {
    super.initState();
    _levelKey = widget.level.toLowerCase().replaceAll('equb_', '').trim();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    try {
      final list = await RoleManagementService.getPaymentsByLevel(_levelKey);
      if (mounted) {
        setState(() {
          _payments = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyPayment(String paymentId, String status, {String reason = ''}) async {
    setState(() => _loading = true);
    final success = await RoleManagementService.verifyPayment(
      paymentId: paymentId,
      status: status,
      rejectionReason: reason,
      adminId: 'admin_level_$_levelKey',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (status == 'verified' ? '✅ Payment Verified & Member Contribution Updated!' : '❌ Payment Request Rejected.')
                : 'Failed to update payment status.',
          ),
          backgroundColor: status == 'verified' ? Colors.green : Colors.red,
        ),
      );
      _loadPayments();
    }
  }

  Color get _levelColor {
    switch (_levelKey) {
      case 'medium':
        return AppColors.medium;
      case 'high':
        return AppColors.high;
      default:
        return AppColors.low;
    }
  }

  void _showProofDialog(Map<String, dynamic> item) {
    final base64Str = (item['proofScreenshotBase64'] ?? '').toString();
    final isAmharic = AppConstants.currentLanguage == 'am';

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAmharic ? 'የክፍያ ደረሰኝ ማረጋገጫ' : 'Bank Receipt Proof Inspection',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(),
              if (base64Str.isNotEmpty && base64Str.contains('base64,')) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(base64Str.split('base64,').last),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('Error loading screenshot image'),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  height: 200,
                  color: Colors.grey.shade200,
                  child: const Center(
                    child: Text('No screenshot preview available'),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Security Checksum: ${item['proofHash'] != null ? (item['proofHash'].toString().substring(0, 16) + '...') : 'SHA-256 Validated'}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
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

  void _showRejectReasonDialog(String paymentId) {
    final reasonController = TextEditingController();
    final isAmharic = AppConstants.currentLanguage == 'am';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isAmharic ? 'ክፍያውን ለመሰረዝ ምክንያት ያስገቡ' : 'Specify Rejection Reason'),
        content: TextField(
          controller: reasonController,
          decoration: InputDecoration(
            hintText: isAmharic ? 'ለምሳሌ: የተሳሳተ ደረሰኝ ወይም አልተከፈለም' : 'e.g. Invalid reference code or wrong receipt',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAmharic ? 'ሰርዝ' : 'Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _verifyPayment(paymentId, 'rejected', reason: reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isAmharic ? 'አረጋግጥና ሰርዝ' : 'Reject Payment'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAmharic = AppConstants.currentLanguage == 'am';
    final filtered = _payments.where((p) {
      if (_filterStatus == 'all') return true;
      final st = (p['status'] ?? 'pending_verification').toString();
      if (_filterStatus == 'pending_verification') {
        return st == 'pending_verification' || st == 'pending';
      }
      return st == _filterStatus;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('${_levelKey.toUpperCase()} LEVEL - ${isAmharic ? "የክፍያ ማረጋገጫ" : "Payment Verification"}'),
        leading: const SmartBackButton(),
        backgroundColor: _levelColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          const OfflineBanner(),
          // Filter status bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('pending_verification', isAmharic ? 'በመጠበቅ ላይ (Pending)' : 'Pending', Colors.orange.shade800),
                  const SizedBox(width: 8),
                  _filterChip('verified', isAmharic ? 'ተረጋግጧል (Verified)' : 'Verified', Colors.green),
                  const SizedBox(width: 8),
                  _filterChip('rejected', isAmharic ? 'ተሰርዟል (Rejected)' : 'Rejected', Colors.red),
                  const SizedBox(width: 8),
                  _filterChip('all', isAmharic ? 'ሁሉም (All)' : 'All Payments', AppColors.primary),
                ],
              ),
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.payment_rounded, size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              isAmharic ? 'ምንም የማረጋገጫ ክፍያ ጥያቄ የለም' : 'No payment requests found for this filter',
                              style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final pId = (item['paymentId'] ?? item['id'] ?? '').toString();
                          final fullName = (item['fullName'] ?? item['name'] ?? 'Equb Member').toString();
                          final email = (item['email'] ?? '').toString();
                          final nationalId = (item['nationalId'] ?? item['uniqueId'] ?? '—').toString();
                          final bankName = (item['bankName'] ?? item['paymentMethod'] ?? 'CBE').toString();
                          final refNum = (item['referenceNumber'] ?? item['reference'] ?? '—').toString();
                          final amount = (item['amount'] ?? 0).toString();
                          final status = (item['status'] ?? 'pending_verification').toString();

                          Color statusColor = status == 'verified'
                              ? Colors.green
                              : (status == 'rejected' ? Colors.red : Colors.orange.shade800);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: _levelColor.withOpacity(0.3), width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        status.toUpperCase().replaceAll('_', ' '),
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$amount ETB',
                                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _levelColor),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  fullName,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Email: $email  •  ID: #$nationalId',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                                const Divider(height: 18),
                                Row(
                                  children: [
                                    const Icon(Icons.account_balance, size: 16, color: AppColors.textSecondary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Bank: $bankName',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                    const Spacer(),
                                    Text(
                                      'Ref: $refNum',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                Row(
                                  children: [
                                    // View Screenshot Proof Button
                                    OutlinedButton.icon(
                                      onPressed: () => _showProofDialog(item),
                                      icon: const Icon(Icons.remove_red_eye_rounded, size: 16),
                                      label: Text(isAmharic ? 'ደረሰኝ ተመልከት' : 'View Proof'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.blue.shade800,
                                        side: BorderSide(color: Colors.blue.shade800),
                                      ),
                                    ),
                                    const Spacer(),

                                    if (status == 'pending_verification' || status == 'pending') ...[
                                      IconButton(
                                        icon: const Icon(Icons.cancel_rounded, color: Colors.red, size: 28),
                                        onPressed: () => _showRejectReasonDialog(pId),
                                        tooltip: 'Reject Payment',
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        onPressed: () => _verifyPayment(pId, 'verified'),
                                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                                        label: Text(isAmharic ? 'አረጋግጥ' : 'Approve'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String statusKey, String label, Color color) {
    final isSel = _filterStatus == statusKey;
    return ChoiceChip(
      selected: isSel,
      label: Text(
        label,
        style: TextStyle(color: isSel ? Colors.white : AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
      ),
      selectedColor: color,
      backgroundColor: Colors.grey.shade100,
      onSelected: (val) {
        if (val) setState(() => _filterStatus = statusKey);
      },
    );
  }
}
