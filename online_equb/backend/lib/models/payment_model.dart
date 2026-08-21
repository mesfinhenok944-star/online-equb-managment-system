// ─── Payment model ────────────────────────────────────────────────────────────

class PaymentModel {
  final String paymentId;
  final String userId;
  final String equbId;
  final String equbLevel;
  final double amount;
  final String type; // contribution | prize
  final String status; // pending | completed | failed
  final String paymentMethod; // bank_transfer | mobile_money | cash
  final String transactionId;
  final String createdAt;
  final String updatedAt;

  PaymentModel({
    this.paymentId = '',
    required this.userId,
    this.equbId = '',
    this.equbLevel = '',
    required this.amount,
    this.type = 'contribution',
    this.status = 'pending',
    this.paymentMethod = 'bank_transfer',
    this.transactionId = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory PaymentModel.fromMap(Map<String, dynamic> m) => PaymentModel(
        paymentId: m['paymentId'] ?? m['id'] ?? '',
        userId: m['userId'] ?? '',
        equbId: m['equbId'] ?? '',
        equbLevel: m['equbLevel'] ?? '',
        amount: (m['amount'] as num?)?.toDouble() ?? 0,
        type: m['type'] ?? 'contribution',
        status: m['status'] ?? 'pending',
        paymentMethod: m['paymentMethod'] ?? 'bank_transfer',
        transactionId: m['transactionId'] ?? '',
        createdAt: m['createdAt'] ?? '',
        updatedAt: m['updatedAt'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'paymentId': paymentId,
        'userId': userId,
        'equbId': equbId,
        'equbLevel': equbLevel,
        'amount': amount,
        'type': type,
        'status': status,
        'paymentMethod': paymentMethod,
        'transactionId': transactionId,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}
