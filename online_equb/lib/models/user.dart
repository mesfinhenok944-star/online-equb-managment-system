// lib/models/user_model.dart

class UserModel {
  final String id;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String email;
  final String phoneNumber;
  final String nationalId;
  final String equbLevel;
  final String status;
  final bool hasWon;
  final double balance;
  final String? adminId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  UserModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.email,
    required this.phoneNumber,
    required this.nationalId,
    required this.equbLevel,
    required this.status,
    required this.hasWon,
    required this.balance,
    this.adminId,
    this.createdAt,
    this.updatedAt,
  });

  String get fullName {
    if (middleName != null && middleName!.isNotEmpty) {
      return '$firstName $middleName $lastName';
    }
    return '$firstName $lastName';
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      middleName: json['middleName'],
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      nationalId: json['nationalId'] ?? '',
      equbLevel: json['equbLevel'] ?? 'low',
      status: json['status'] ?? 'pending',
      hasWon: json['hasWon'] ?? false,
      balance: (json['balance'] ?? 0).toDouble(),
      adminId: json['adminId'],
      createdAt: json['createdAt'] is DateTime
          ? json['createdAt']
          : DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: json['updatedAt'] is DateTime
          ? json['updatedAt']
          : DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'email': email,
      'phoneNumber': phoneNumber,
      'nationalId': nationalId,
      'equbLevel': equbLevel,
      'status': status,
      'hasWon': hasWon,
      'balance': balance,
      'adminId': adminId,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
