import 'dart:math';
import '../models/equb_participant.dart';

class EqubSelectionService {
  final Map<EqubLevel, List<EqubParticipant>> _levelParticipants = {
    EqubLevel.low: [],
    EqubLevel.medium: [],
    EqubLevel.high: [],
  };

  final Map<EqubLevel, List<EqubDrawRecord>> _levelHistory = {
    EqubLevel.low: [],
    EqubLevel.medium: [],
    EqubLevel.high: [],
  };

  final Map<EqubLevel, int> _currentRounds = {
    EqubLevel.low: 0,
    EqubLevel.medium: 0,
    EqubLevel.high: 0,
  };

  final Random _secureRandom = Random.secure();

  /// Initialize users across low, medium, high levels
  void initializeLevelData(List<EqubParticipant> users) {
    for (var level in EqubLevel.values) {
      _levelParticipants[level] = users.where((u) => u.level == level).toList();
      _levelHistory[level] = [];
      _currentRounds[level] = 0;
    }
  }

  /// Get remaining unselected & paid participants for a level
  List<EqubParticipant> getEligibleParticipants(EqubLevel level) {
    return (_levelParticipants[level] ?? [])
        .where((p) => !p.isSelected && p.isPaid)
        .toList();
  }

  /// Execute Fisher-Yates random selection without replacement
  EqubDrawRecord? selectWinnerForLevel(EqubLevel level) {
    final available = getEligibleParticipants(level);
    if (available.isEmpty) return null;

    // Cryptographically secure random selection
    int randomIndex = _secureRandom.nextInt(available.length);
    EqubParticipant selected = available[randomIndex];

    int nextRound = (_currentRounds[level] ?? 0) + 1;
    _currentRounds[level] = nextRound;

    selected.isSelected = true;
    selected.selectedDate = DateTime.now();
    selected.roundNumber = nextRound;

    int totalMembers = (_levelParticipants[level] ?? []).length;
    double grossPool = totalMembers * level.defaultContribution;
    double netPrize = grossPool * (1.0 - level.adminFeePercent);

    final record = EqubDrawRecord(
      roundNumber: nextRound,
      level: level,
      winner: selected,
      prizeAmount: netPrize,
      drawnAt: DateTime.now(),
    );

    _levelHistory[level]?.add(record);
    return record;
  }

  /// Get level statistics
  Map<String, dynamic> getStatistics(EqubLevel level) {
    final list = _levelParticipants[level] ?? [];
    final selectedCount = list.where((p) => p.isSelected).length;
    final remainingCount = list.where((p) => !p.isSelected && p.isPaid).length;
    final currentRound = _currentRounds[level] ?? 0;
    final grossPool = list.length * level.defaultContribution;
    final netPrize = grossPool * (1.0 - level.adminFeePercent);

    return {
      'totalParticipants': list.length,
      'selectedCount': selectedCount,
      'remainingCount': remainingCount,
      'currentRound': currentRound,
      'contribution': level.defaultContribution,
      'prizePool': netPrize,
      'progress': list.isNotEmpty ? (selectedCount / list.length) : 0.0,
    };
  }

  List<EqubDrawRecord> getHistory(EqubLevel level) {
    return List.unmodifiable(_levelHistory[level] ?? []);
  }

  void resetLevel(EqubLevel level) {
    for (var p in _levelParticipants[level] ?? []) {
      p.isSelected = false;
      p.selectedDate = null;
      p.roundNumber = null;
    }
    _levelHistory[level]?.clear();
    _currentRounds[level] = 0;
  }
}
