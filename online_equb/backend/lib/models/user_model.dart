// ─── User (equb member) model ─────────────────────────────────────────────────

class UserModel {
  final String userId;
  final String firstName;
  final String middleName;
  final String lastName;
  final String fullName;
  final String email;
  final String phoneNumber;
  final String uniqueId; // one-to-one national/custom ID
  final String equbLevel;
  final String adminId;
  final String status; // active | suspended | deleted
  final String role;
  final bool hasWon;
  final List<dynamic> participationHistory;
  final double balance;
  final String createdAt;
  final String updatedAt;

  UserModel({
    this.userId = '',
    required this.firstName,
    this.middleName = '',
    required this.lastName,
    this.fullName = '',
    required this.email,
    this.phoneNumber = '',
    this.uniqueId = '',
    this.equbLevel = 'low',
    this.adminId = '',
    this.status = 'active',
    this.role = 'user',
    this.hasWon = false,
    this.participationHistory = const [],
    this.balance = 0,
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory UserModel.fromMap(Map<String, dynamic> m) => UserModel(
        userId: m['userId'] ?? m['id'] ?? '',
        firstName: m['firstName'] ?? '',
        middleName: m['middleName'] ?? '',
        lastName: m['lastName'] ?? '',
        fullName: m['fullName'] ?? '',
        email: m['email'] ?? '',
        phoneNumber: m['phoneNumber'] ?? '',
        uniqueId: m['uniqueId'] ?? '',
        equbLevel: m['equbLevel'] ?? 'low',
        adminId: m['adminId'] ?? '',
        status: m['status'] ?? 'active',
        role: m['role'] ?? 'user',
        hasWon: m['hasWon'] == true,
        participationHistory: List<dynamic>.from(m['participationHistory'] ?? []),
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
        createdAt: m['createdAt'] ?? '',
        updatedAt: m['updatedAt'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'fullName': fullName.isEmpty
            ? '$firstName $middleName $lastName'.trim().replaceAll(RegExp(r'\s+'), ' ')
            : fullName,
        'email': email,
        'phoneNumber': phoneNumber,
        'uniqueId': uniqueId,
        'equbLevel': equbLevel,
        'adminId': adminId,
        'status': status,
        'role': role,
        'hasWon': hasWon,
        'participationHistory': participationHistory,
        'balance': balance,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}
