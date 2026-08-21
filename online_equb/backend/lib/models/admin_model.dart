// ─── Admin model ──────────────────────────────────────────────────────────────

class AdminModel {
  final String adminId;
  final String firstName;
  final String middleName;
  final String lastName;
  final String fullName;
  final String email;
  final String username;
  final String password;
  final String phone;
  final String address;
  final String level; // low | medium | high
  final String status; // active | suspended | deleted
  final String role;
  final Map<String, dynamic> contactInfo;
  final Map<String, dynamic> permissions;
  final String createdAt;
  final String updatedAt;

  AdminModel({
    this.adminId = '',
    required this.firstName,
    this.middleName = '',
    required this.lastName,
    this.fullName = '',
    required this.email,
    this.username = '',
    this.password = '',
    this.phone = '',
    this.address = '',
    this.level = 'low',
    this.status = 'active',
    this.role = 'admin',
    this.contactInfo = const {},
    this.permissions = const {},
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory AdminModel.fromMap(Map<String, dynamic> m) => AdminModel(
        adminId: m['adminId'] ?? m['id'] ?? '',
        firstName: m['firstName'] ?? '',
        middleName: m['middleName'] ?? '',
        lastName: m['lastName'] ?? '',
        fullName: m['fullName'] ?? '',
        email: m['email'] ?? '',
        username: m['username'] ?? '',
        password: m['password'] ?? '',
        phone: m['phone'] ?? '',
        address: m['address'] ?? '',
        level: m['level'] ?? 'low',
        status: m['status'] ?? 'active',
        role: m['role'] ?? 'admin',
        contactInfo: Map<String, dynamic>.from(m['contactInfo'] ?? {}),
        permissions: Map<String, dynamic>.from(m['permissions'] ?? {}),
        createdAt: m['createdAt'] ?? '',
        updatedAt: m['updatedAt'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'adminId': adminId,
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'fullName': fullName.isEmpty
            ? '$firstName $middleName $lastName'.trim().replaceAll(RegExp(r'\s+'), ' ')
            : fullName,
        'email': email,
        'username': username,
        'password': password,
        'phone': phone,
        'address': address,
        'level': level,
        'status': status,
        'role': role,
        'contactInfo': contactInfo,
        'permissions': permissions,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  /// Default permissions for a given level.
  static Map<String, dynamic> defaultPermissions(String level) => {
        'canAddUsers': true,
        'canEditUsers': true,
        'canDeleteUsers': true,
        'canViewUsers': true,
        'canManageEqubs': true,
        'canRunAlgorithms': true,
        'canManagePayments': true,
        'canViewReports': true,
        'canSendNotifications': true,
        'canViewAnalytics': true,
        'canExportData': level == 'medium' || level == 'high',
        'canManageAdmins': false,
      };
}
