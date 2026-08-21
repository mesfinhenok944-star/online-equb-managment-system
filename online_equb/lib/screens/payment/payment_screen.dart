import 'package:flutter/material.dart';
import '../../widgets/smart_back_button.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme.dart';
import '../../services/api_service.dart';

class PaymentScreen extends StatefulWidget {
  final String equbId;
  final String participantId;
  final double amount;
  const PaymentScreen(
      {super.key,
      required this.equbId,
      required this.participantId,
      required this.amount});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _ref = TextEditingController();
  String _method = 'bank_transfer';
  bool _loading = false;

  Future<void> _pay() async {
    if (_ref.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter payment reference number')));
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ApiService.initiatePayment({
        'equbId': widget.equbId,
        'participantId': widget.participantId,
        'amount': widget.amount,
        'paymentMethod': _method,
        'referenceNumber': _ref.text.trim(),
      });
      if (!mounted) return;
      if (res['transactionId'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('✅ Payment submitted for verification'),
            backgroundColor: AppColors.success));
        context.go('/home');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(res['error'] ?? 'Payment failed'),
            backgroundColor: AppColors.error));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Connection error')));
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Make Payment'),
        leading: const SmartBackButton(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Amount card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(children: [
              const Text('Amount to Pay',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 8),
              Text('${widget.amount.toStringAsFixed(0)} ETB',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      fontWeight: FontWeight.bold)),
            ]),
          ),
          const SizedBox(height: 24),

          // Payment method
          const Text('Payment Method',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          _methodTile('bank_transfer', 'Bank Transfer',
              'CBE, Dashen, Awash, etc.', Icons.account_balance),
          const SizedBox(height: 8),
          _methodTile('telebirr', 'Telebirr', 'Ethio Telecom mobile money',
              Icons.phone_android),
          const SizedBox(height: 24),

          // Bank details
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Payment Instructions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_method == 'bank_transfer') ...[
                _instruction('Bank', 'Commercial Bank of Ethiopia'),
                _instruction('Account Name', 'Online Equb PLC'),
                _instruction('Account No.', '1000123456789'),
              ] else ...[
                _instruction('Telebirr No.', '+251900000000'),
                _instruction('Account Name', 'Online Equb'),
              ],
              const SizedBox(height: 8),
              const Text('After payment, enter your reference number below.',
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          const SizedBox(height: 20),

          // Reference number
          const Text('Reference Number',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _ref,
            decoration: const InputDecoration(
              hintText: 'e.g. CBE-2025-001234',
              prefixIcon: Icon(Icons.receipt_outlined),
            ),
          ),
          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _loading ? null : _pay,
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Text('Submit Payment'),
          ),
        ]),
      ),
    );
  }

  Widget _methodTile(String value, String title, String sub, IconData icon) {
    final sel = _method == value;
    return GestureDetector(
      onTap: () => setState(() => _method = value),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: sel ? AppColors.primary.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: sel ? AppColors.primary : AppColors.divider,
              width: sel ? 2 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: sel ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color:
                            sel ? AppColors.primary : AppColors.textPrimary)),
                Text(sub,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ])),
          if (sel) const Icon(Icons.check_circle, color: AppColors.primary),
        ]),
      ),
    );
  }

  Widget _instruction(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
              width: 110,
              child: Text(label,
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13))),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      );
}
