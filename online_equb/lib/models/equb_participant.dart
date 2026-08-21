/// Equb Level Tier
enum EqubLevel { low, medium, high }

extension EqubLevelExtension on EqubLevel {
  String get nameAmharic => switch (this) {
        EqubLevel.low => 'ዝቅተኛ · Low Level',
        EqubLevel.medium => 'መካከለኛ · Medium Level',
        EqubLevel.high => 'ከፍተኛ · High Level',
      };

  double get defaultContribution => switch (this) {
        EqubLevel.low => 5000.0,
        EqubLevel.medium => 10000.0,
        EqubLevel.high => 20000.0,
      };

  double get adminFeePercent => switch (this) {
        EqubLevel.low => 0.05,
        EqubLevel.medium => 0.07,
        EqubLevel.high => 0.10,
      };
}

/// Participant Model
class EqubParticipant {
  final String id;
  final String name;
  final String phoneNumber;
  final String email;
  final EqubLevel level;
  bool isPaid;
  bool isSelected;
  DateTime? selectedDate;
  int? roundNumber;

  EqubParticipant({
    required this.id,
    required this.name,
    required this.phoneNumber,
    this.email = '',
    required this.level,
    this.isPaid = true,
    this.isSelected = false,
    this.selectedDate,
    this.roundNumber,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phoneNumber': phoneNumber,
        'email': email,
        'level': level.name,
        'isPaid': isPaid,
        'isSelected': isSelected,
        'selectedDate': selectedDate?.toIso8601String(),
        'roundNumber': roundNumber,
      };

  factory EqubParticipant.fromJson(Map<String, dynamic> json) =>
      EqubParticipant(
        id: json['id'],
        name: json['name'],
        phoneNumber: json['phoneNumber'] ?? '',
        email: json['email'] ?? '',
        level: EqubLevel.values.firstWhere(
          (e) => e.name == json['level'],
          orElse: () => EqubLevel.low,
        ),
        isPaid: json['isPaid'] ?? true,
        isSelected: json['isSelected'] ?? false,
        selectedDate: json['selectedDate'] != null
            ? DateTime.parse(json['selectedDate'])
            : null,
        roundNumber: json['roundNumber'],
      );
}

/// Draw History Record
class EqubDrawRecord {
  final int roundNumber;
  final EqubLevel level;
  final EqubParticipant winner;
  final double prizeAmount;
  final DateTime drawnAt;

  EqubDrawRecord({
    required this.roundNumber,
    required this.level,
    required this.winner,
    required this.prizeAmount,
    required this.drawnAt,
  });
}
