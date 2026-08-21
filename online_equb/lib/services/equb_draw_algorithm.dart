import 'dart:math';

/// A reusable local draw algorithm for EQUB administration.
///
/// This service performs secure random draws without replacement, marks
/// winners as excluded from future rounds, and helps generate draw records.
class EqubDrawAlgorithm {
  static final Random _secureRandom = Random.secure();

  static List<Map<String, dynamic>> eligibleParticipants(
      List<Map<String, dynamic>> participants) {
    return participants
        .where((p) => p['hasWon'] != true && p['status'] != 'removed')
        .toList();
  }

  static int remainingCount(List<Map<String, dynamic>> participants) {
    return eligibleParticipants(participants).length;
  }

  static int selectedCount(List<Map<String, dynamic>> participants) {
    return participants.where((p) => p['hasWon'] == true).length;
  }

  static int? chooseWinnerIndex(List<Map<String, dynamic>> participants) {
    final eligible = eligibleParticipants(participants);
    if (eligible.isEmpty) return null;
    final eligibleWinner = eligible[_secureRandom.nextInt(eligible.length)];
    return participants.indexWhere((p) =>
        p['participantId'] == eligibleWinner['participantId'] ||
        p['userId'] == eligibleWinner['userId'] ||
        p['id'] == eligibleWinner['id']);
  }

  static Map<String, dynamic>? markWinnerByIndex(
    int index,
    List<Map<String, dynamic>> participants,
    List<Map<String, dynamic>> drawHistory,
    String level,
  ) {
    if (index < 0 || index >= participants.length) return null;
    final participant = participants[index];
    if (participant['hasWon'] == true || participant['status'] == 'removed') {
      return null;
    }
    final selectedAt = DateTime.now().toLocal();
    final ethiopian = _ethiopianDateFromGregorian(selectedAt);
    final drawDate =
        '${ethiopian['day'].toString().padLeft(2, '0')}/${ethiopian['month'].toString().padLeft(2, '0')}/${ethiopian['year']}';
    final drawTime =
        '${selectedAt.hour.toString().padLeft(2, '0')}:${selectedAt.minute.toString().padLeft(2, '0')}:${selectedAt.second.toString().padLeft(2, '0')}';

    participant['hasWon'] = true;
    participant['selectedAt'] = selectedAt.toIso8601String();
    participant['status'] = 'selected';
    participant['roundNumber'] = drawHistory.length + 1;

    final drawRecord = {
      'drawNumber': drawHistory.length + 1,
      'winnerName': participant['firstName'] ??
          participant['fullName'] ??
          participant['name'] ??
          'Winner',
      'participantId': participant['participantId'] ??
          participant['userId'] ??
          participant['id'],
      'drawDate': drawDate,
      'drawTime': drawTime,
      'prizeAmount': _levelPrize(level, participants.length),
    };
    drawHistory.add(drawRecord);
    return participant;
  }

  static Map<String, dynamic>? selectWinner(
    List<Map<String, dynamic>> participants,
    List<Map<String, dynamic>> drawHistory,
    String level,
  ) {
    final eligible = eligibleParticipants(participants);
    if (eligible.isEmpty) return null;

    final winnerIndex = _secureRandom.nextInt(eligible.length);
    final winner = eligible[winnerIndex];
    final selectedAt = DateTime.now().toLocal();
    final ethiopian = _ethiopianDateFromGregorian(selectedAt);
    final drawDate =
        '${ethiopian['day'].toString().padLeft(2, '0')}/${ethiopian['month'].toString().padLeft(2, '0')}/${ethiopian['year']}';
    final drawTime =
        '${selectedAt.hour.toString().padLeft(2, '0')}:${selectedAt.minute.toString().padLeft(2, '0')}:${selectedAt.second.toString().padLeft(2, '0')}';

    winner['hasWon'] = true;
    winner['selectedAt'] = selectedAt.toIso8601String();
    winner['status'] = 'selected';
    winner['roundNumber'] = drawHistory.length + 1;

    final drawRecord = {
      'drawNumber': drawHistory.length + 1,
      'winnerName': winner['firstName'] ??
          winner['fullName'] ??
          winner['name'] ??
          'Winner',
      'participantId':
          winner['participantId'] ?? winner['userId'] ?? winner['id'],
      'drawDate': drawDate,
      'drawTime': drawTime,
      'prizeAmount': _levelPrize(level, participants.length),
    };

    drawHistory.add(drawRecord);
    return winner;
  }

  static Map<String, int> _ethiopianDateFromGregorian(DateTime date) {
    final jd = _gregorianToJdn(date.year, date.month, date.day);
    const ethioEpoch = 1723856;
    final int r = (jd - ethioEpoch) % 1461;
    final int n = r % 365 + 365 * (r ~/ 1461);
    final year = 4 * ((jd - ethioEpoch) ~/ 1461) + (r ~/ 365) + 1;
    final month = (n ~/ 30) + 1;
    final day = (n % 30) + 1;
    return {'year': year, 'month': month, 'day': day};
  }

  static int _gregorianToJdn(int year, int month, int day) {
    final a = ((14 - month) ~/ 12);
    final y = year + 4800 - a;
    final m = month + 12 * a - 3;
    return day +
        ((153 * m + 2) ~/ 5) +
        365 * y +
        (y ~/ 4) -
        (y ~/ 100) +
        (y ~/ 400) -
        32045;
  }

  static double _levelPrize(String level, int totalParticipants) {
    switch (level) {
      case 'high':
        return totalParticipants * 50000.0 * 0.9;
      case 'medium':
        return totalParticipants * 10000.0 * 0.93;
      case 'low':
      default:
        return totalParticipants * 5000.0 * 0.95;
    }
  }

  static void addParticipant(
      List<Map<String, dynamic>> participants, Map<String, dynamic> user) {
    final userId = (user['userId'] ?? user['id'] ?? '').toString();
    final exists = participants.any((p) =>
        p['userId'] == userId ||
        p['id'] == userId ||
        p['participantId'] == userId);
    if (exists) return;

    final fullName = (user['fullName'] ?? '').toString().trim();
    final firstName = (user['firstName'] ?? '').toString().trim();
    final lastName = (user['lastName'] ?? '').toString().trim();
    final displayName = fullName.isNotEmpty
        ? fullName
        : '$firstName $lastName'.trim().isNotEmpty
            ? '$firstName $lastName'.trim()
            : 'Unnamed User';

    participants.add({
      'participantId': user['uniqueId'] ??
          user['participantId'] ??
          'local_${DateTime.now().millisecondsSinceEpoch}',
      'userId': userId,
      'fullName': displayName,
      'firstName': firstName,
      'lastName': lastName,
      'phoneNumber': user['phoneNumber'] ?? '',
      'email': user['email'] ?? '',
      'verificationStatus': user['verificationStatus'] ?? 'verified',
      'isPaid': user['isPaid'] ?? true,
      'hasWon': false,
      'status': 'active',
      'numberOfShares': 1,
    });
  }

  static void removeParticipant(
      List<Map<String, dynamic>> participants, String participantId) {
    participants.removeWhere((p) =>
        p['participantId'] == participantId ||
        p['id'] == participantId ||
        p['userId'] == participantId);
  }
}
