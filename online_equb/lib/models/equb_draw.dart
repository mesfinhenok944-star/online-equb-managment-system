// lib/models/equb_draw.dart

class EqubDrawModel {
  final String id;
  final String equbLevel;
  final String adminId;
  final String winnerId;
  final String winnerName;
  final String? winnerNationalId;
  final int totalParticipants;
  final List<String> participants;
  final DateTime? createdAt;

  EqubDrawModel({
    required this.id,
    required this.equbLevel,
    required this.adminId,
    required this.winnerId,
    required this.winnerName,
    this.winnerNationalId,
    required this.totalParticipants,
    required this.participants,
    this.createdAt,
  });

  factory EqubDrawModel.fromJson(Map<String, dynamic> json) {
    return EqubDrawModel(
      id: json['id'] ?? '',
      equbLevel: json['equbLevel'] ?? 'low',
      adminId: json['adminId'] ?? '',
      winnerId: json['winnerId'] ?? '',
      winnerName: json['winnerName'] ?? '',
      winnerNationalId: json['winnerNationalId'],
      totalParticipants: json['totalParticipants'] ?? 0,
      participants: List<String>.from(json['participants'] ?? []),
      createdAt: json['createdAt'] is DateTime
          ? json['createdAt']
          : DateTime.tryParse(json['createdAt']?.toString() ?? ''),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'equbLevel': equbLevel,
      'adminId': adminId,
      'winnerId': winnerId,
      'winnerName': winnerName,
      'winnerNationalId': winnerNationalId,
      'totalParticipants': totalParticipants,
      'participants': participants,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
