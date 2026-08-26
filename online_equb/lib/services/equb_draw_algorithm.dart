import 'dart:math';

// ─────────────────────────────────────────────────────────────────────────────
// EqubDrawAlgorithm
//
// FREE RANDOM SELECTION — cryptographically secure draw for Ethiopian Equb.
//
// WINNER EXCLUSION RULE:
//   Once a participant wins (hasWon = true), they are permanently removed
//   from all future draw rounds at their equb level.
//
//   Example with 100 users:
//     Round 1: 100 eligible → 1 winner drawn → hasWon = true
//     Round 2:  99 eligible → 1 winner drawn → hasWon = true
//     Round 3:  98 eligible → ...continues until all have won
//
// Works identically for Low, Medium, and High equb levels.
// ─────────────────────────────────────────────────────────────────────────────

class EqubDrawAlgorithm {
  static final Random _secure = Random.secure();

  // ── Eligible participants ─────────────────────────────────────────────────
  // Only participants who:
  //   • Have NOT won before  (hasWon != true)
  //   • Are currently active (status == 'active')
  // This enforces the winner-exclusion rule.
  static List<Map<String, dynamic>> eligibleParticipants(
      List<Map<String, dynamic>> all) {
    return all.where((p) {
      final won    = p['hasWon'] == true;
      final status = (p['status'] ?? 'active').toString().toLowerCase();
      return !won && status == 'active';
    }).toList();
  }

  // ── Counts ────────────────────────────────────────────────────────────────
  static int remainingCount(List<Map<String, dynamic>> all) =>
      eligibleParticipants(all).length;

  static int winnersCount(List<Map<String, dynamic>> all) =>
      all.where((p) => p['hasWon'] == true).length;

  // ── FREE RANDOM SELECTION ─────────────────────────────────────────────────
  // Returns the index of the selected winner inside the FULL participants list.
  // Returns null if there are no eligible participants.
  //
  // Uses dart:math Random.secure() — cryptographically secure PRNG.
  // Every eligible participant has an exactly equal probability of winning.
  static int? chooseWinnerIndex(List<Map<String, dynamic>> all) {
    final eligible = eligibleParticipants(all);
    if (eligible.isEmpty) return null;

    // Cryptographically secure free random pick
    final picked = eligible[_secure.nextInt(eligible.length)];

    // Map back to the full list index
    final pickedId = _id(picked);
    return all.indexWhere((p) =>
        _id(p) == pickedId ||
        p['participantId'] == pickedId ||
        p['userId']        == pickedId ||
        p['id']            == pickedId);
  }

  // ── Mark winner ───────────────────────────────────────────────────────────
  // Mutates the participant map:  hasWon = true, status = 'selected'.
  // Adds a draw record to drawHistory.
  static Map<String, dynamic>? markWinnerByIndex(
    int index,
    List<Map<String, dynamic>> all,
    List<Map<String, dynamic>> drawHistory,
    String level,
  ) {
    if (index < 0 || index >= all.length) return null;
    final p = all[index];

    if (p['hasWon'] == true) return null; // already won — skip
    final st = (p['status'] ?? 'active').toString().toLowerCase();
    if (st == 'removed' || st == 'deleted') return null;

    final now       = DateTime.now().toLocal();
    final eth       = _ethDate(now);
    final drawDate  = '${_pad(eth['day']!)}/${_pad(eth['month']!)}/${eth['year']}';
    final drawTime  = '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}';
    final roundNum  = drawHistory.length + 1;

    // Mark winner permanently
    p['hasWon']     = true;
    p['status']     = 'selected';
    p['selectedAt'] = now.toIso8601String();
    p['roundNumber'] = roundNum;

    drawHistory.add({
      'drawNumber':   roundNum,
      'winnerName':   _name(p),
      'winnerId':     _id(p),
      'winnerUniqueId': (p['uniqueId'] ?? _id(p)).toString(),
      'participantId': p['participantId'] ?? _id(p),
      'drawDate':     drawDate,
      'drawTime':     drawTime,
      'equbLevel':    level,
      'prizeAmount':  _prize(level, all.length),
      'createdAt':    now.toIso8601String(),
      'status':       'completed',
    });

    return p;
  }

  // ── selectWinner (convenience wrapper) ───────────────────────────────────
  // Picks a winner and marks them.  Returns the winner map or null.
  static Map<String, dynamic>? selectWinner(
    List<Map<String, dynamic>> all,
    List<Map<String, dynamic>> drawHistory,
    String level,
  ) {
    final idx = chooseWinnerIndex(all);
    if (idx == null) return null;
    return markWinnerByIndex(idx, all, drawHistory, level);
  }

  // ── Add / remove participant ──────────────────────────────────────────────
  static void addParticipant(
      List<Map<String, dynamic>> all, Map<String, dynamic> user) {
    final uid = _id(user);
    if (all.any((p) => _id(p) == uid)) return; // already in list

    final fullName = (user['fullName'] ?? '').toString().trim();
    final first    = (user['firstName'] ?? '').toString().trim();
    final last     = (user['lastName']  ?? '').toString().trim();
    final display  = fullName.isNotEmpty
        ? fullName
        : '$first $last'.trim().isNotEmpty
            ? '$first $last'.trim()
            : 'Participant ${all.length + 1}';

    all.add({
      'participantId':      user['uniqueId'] ?? user['participantId'] ?? 'p_${DateTime.now().millisecondsSinceEpoch}',
      'userId':             uid,
      'uniqueId':           user['uniqueId'] ?? '',
      'fullName':           display,
      'firstName':          first,
      'lastName':           last,
      'phoneNumber':        user['phoneNumber'] ?? '',
      'email':              user['email'] ?? '',
      'hasWon':             false,
      'status':             'active',
      'equbLevel':          user['equbLevel'] ?? user['level'] ?? '',
      'numberOfShares':     1,
    });
  }

  static void removeParticipant(List<Map<String, dynamic>> all, String uid) {
    all.removeWhere((p) =>
        _id(p) == uid ||
        p['participantId'] == uid);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _id(Map<String, dynamic> p) =>
      (p['userId'] ?? p['id'] ?? p['participantId'] ?? '').toString();

  static String _name(Map<String, dynamic> p) =>
      (p['fullName'] ?? p['firstName'] ?? 'Winner').toString().trim();

  static String _pad(int? n) => (n ?? 0).toString().padLeft(2, '0');

  // Prize pool per level (90–95% of collected contributions)
  static double _prize(String level, int count) {
    switch (level.toLowerCase().replaceAll('equb_', '')) {
      case 'high':   return count * 50000.0 * 0.90;
      case 'medium': return count * 10000.0 * 0.93;
      default:       return count *  1000.0 * 0.95;
    }
  }

  // Ethiopian calendar conversion
  static Map<String, int> _ethDate(DateTime d) {
    final jd  = _gjd(d.year, d.month, d.day);
    const ep  = 1723856;
    final r   = (jd - ep) % 1461;
    final n   = r % 365 + 365 * (r ~/ 1461);
    return {
      'year':  4 * ((jd - ep) ~/ 1461) + (r ~/ 365) + 1,
      'month': (n ~/ 30) + 1,
      'day':   (n % 30) + 1,
    };
  }

  static int _gjd(int y, int m, int d) {
    final a = (14 - m) ~/ 12;
    final yr = y + 4800 - a;
    final mo = m + 12 * a - 3;
    return d + ((153 * mo + 2) ~/ 5) + 365 * yr +
           (yr ~/ 4) - (yr ~/ 100) + (yr ~/ 400) - 32045;
  }
}
