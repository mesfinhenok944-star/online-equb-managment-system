// lib/models/admin.dart

class AdminModel {
  final String id;
  final String firstName;
  final String lastName;
  final String? middleName;
  final String email;
  final String username;
  final String? phoneNumber;
  final String assignedLevel;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<dynamic>? permissions;

  AdminModel({
    required this.id,
    required this.firstName,
    required this.lastName,
    this.middleName,
    required this.email,
    required this.username,
    this.phoneNumber,
    required this.assignedLevel,
    required this.status,
    this.createdAt,
    this.updatedAt,
    this.permissions,
  });

  String get fullName {
    if (middleName != null && middleName!.isNotEmpty) {
      return '$firstName $middleName $lastName';
    }
    return '$firstName $lastName';
  }

  factory AdminModel.fromJson(Map<String, dynamic> json) {
    return AdminModel(
      id: json['id'] ?? '',
      firstName: json['firstName'] ?? '',
      lastName: json['lastName'] ?? '',
      middleName: json['middleName'],
      email: json['email'] ?? '',
      username: json['username'] ?? '',
      phoneNumber: json['phoneNumber'],
      assignedLevel: json['assignedLevel'] ?? 'low',
      status: json['status'] ?? 'active',
      createdAt: json['createdAt'] is DateTime
          ? json['createdAt']
          : DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: json['updatedAt'] is DateTime
          ? json['updatedAt']
          : DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      permissions: json['permissions'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'middleName': middleName,
      'email': email,
      'username': username,
      'phoneNumber': phoneNumber,
      'assignedLevel': assignedLevel,
      'status': status,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'permissions': permissions,
    };
  }
}
