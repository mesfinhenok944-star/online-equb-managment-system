// ─── Equb model ───────────────────────────────────────────────────────────────

class EqubModel {
  final String equbId;
  final String name;
  final String level; // low | medium | high
  final double price;
  final double netPrize;
  final double adminFee;
  final int currentParticipants;
  final int maxParticipants;
  final String status; // active | paused | completed
  final String adminId;
  final String description;
  final int drawsHeld;
  final double totalCollected;
  final String createdAt;

  EqubModel({
    this.equbId = '',
    required this.name,
    required this.level,
    this.price = 0,
    this.netPrize = 0,
    this.adminFee = 0,
    this.currentParticipants = 0,
    this.maxParticipants = 100,
    this.status = 'active',
    this.adminId = '',
    this.description = '',
    this.drawsHeld = 0,
    this.totalCollected = 0,
    this.createdAt = '',
  });

  factory EqubModel.fromMap(Map<String, dynamic> m) => EqubModel(
        equbId: m['equbId'] ?? m['id'] ?? '',
        name: m['name'] ?? '',
        level: m['level'] ?? 'low',
        price: (m['price'] as num?)?.toDouble() ?? 0,
        netPrize: (m['netPrize'] as num?)?.toDouble() ?? 0,
        adminFee: (m['adminFee'] as num?)?.toDouble() ?? 0,
        currentParticipants: (m['currentParticipants'] as num?)?.toInt() ?? 0,
        maxParticipants: (m['maxParticipants'] as num?)?.toInt() ?? 100,
        status: m['status'] ?? 'active',
        adminId: m['adminId'] ?? '',
        description: m['description'] ?? '',
        drawsHeld: (m['drawsHeld'] as num?)?.toInt() ?? 0,
        totalCollected: (m['totalCollected'] as num?)?.toDouble() ?? 0,
        createdAt: m['createdAt'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'equbId': equbId,
        'id': equbId,
        'name': name,
        'level': level,
        'price': price,
        'netPrize': netPrize,
        'adminFee': adminFee,
        'currentParticipants': currentParticipants,
        'maxParticipants': maxParticipants,
        'status': status,
        'adminId': adminId,
        'description': description,
        'drawsHeld': drawsHeld,
        'totalCollected': totalCollected,
        'createdAt': createdAt,
      };

  /// Default equb configs per level.
  static EqubModel defaultForLevel(String level, {String adminId = ''}) {
    switch (level) {
      case 'medium':
        return EqubModel(
          equbId: 'equb_medium',
          name: 'መካከለኛ · Medium Level EQUB',
          level: 'medium',
          price: 10000,
          netPrize: 465000,
          adminFee: 35000,
          maxParticipants: 50,
          status: 'active',
          adminId: adminId,
          description: 'Medium level EQUB for established business owners.',
        );
      case 'high':
        return EqubModel(
          equbId: 'equb_high',
          name: 'ከፍተኛ · High Level EQUB',
          level: 'high',
          price: 20000,
          netPrize: 360000,
          adminFee: 40000,
          maxParticipants: 20,
          status: 'active',
          adminId: adminId,
          description: 'High level EQUB for large investors.',
        );
      default: // low
        return EqubModel(
          equbId: 'equb_low',
          name: 'ዝቅተኛ · Low Level EQUB',
          level: 'low',
          price: 5000,
          netPrize: 465000,
          adminFee: 35000,
          maxParticipants: 100,
          status: 'active',
          adminId: adminId,
          description: 'Low level EQUB for small business owners.',
        );
    }
  }
}

// ─── Draw model ───────────────────────────────────────────────────────────────

class DrawModel {
  final String drawId;
  final String equbLevel;
  final String adminId;
  final String winnerId;
  final String winnerName;
  final String winnerUniqueId;
  final int drawNumber;
  final List<String> participants;
  final int totalParticipants;
  final String createdAt;
  final String status;

  DrawModel({
    this.drawId = '',
    required this.equbLevel,
    this.adminId = '',
    required this.winnerId,
    required this.winnerName,
    this.winnerUniqueId = '',
    required this.drawNumber,
    this.participants = const [],
    this.totalParticipants = 0,
    this.createdAt = '',
    this.status = 'completed',
  });

  factory DrawModel.fromMap(Map<String, dynamic> m) => DrawModel(
        drawId: m['drawId'] ?? m['id'] ?? '',
        equbLevel: m['equbLevel'] ?? '',
        adminId: m['adminId'] ?? '',
        winnerId: m['winnerId'] ?? '',
        winnerName: m['winnerName'] ?? '',
        winnerUniqueId: m['winnerUniqueId'] ?? '',
        drawNumber: (m['drawNumber'] as num?)?.toInt() ?? 0,
        participants: List<String>.from(m['participants'] ?? []),
        totalParticipants: (m['totalParticipants'] as num?)?.toInt() ?? 0,
        createdAt: m['createdAt'] ?? '',
        status: m['status'] ?? 'completed',
      );

  Map<String, dynamic> toMap() => {
        'drawId': drawId,
        'equbLevel': equbLevel,
        'adminId': adminId,
        'winnerId': winnerId,
        'winnerName': winnerName,
        'winnerUniqueId': winnerUniqueId,
        'drawNumber': drawNumber,
        'participants': participants,
        'totalParticipants': totalParticipants,
        'createdAt': createdAt,
        'status': status,
      };
}
