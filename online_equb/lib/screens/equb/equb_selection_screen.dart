import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/equb_participant.dart';
import '../../services/equb_selection_service.dart';

class EqubSelectionScreen extends StatefulWidget {
  const EqubSelectionScreen({super.key});

  @override
  State<EqubSelectionScreen> createState() => _EqubSelectionScreenState();
}

class _EqubSelectionScreenState extends State<EqubSelectionScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final EqubSelectionService _service = EqubSelectionService();
  EqubLevel _activeLevel = EqubLevel.low;
  bool _isSelecting = false;
  String _spinnerText = 'Tap to Draw';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _activeLevel = EqubLevel.values[_tabController.index];
        });
      }
    });
    _initMockData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _initMockData() {
    List<EqubParticipant> mockList = [];

    // Low Level (100 members)
    for (int i = 1; i <= 100; i++) {
      mockList.add(EqubParticipant(
        id: 'low_$i',
        name: 'Low Member #$i',
        phoneNumber: '+25191100${i.toString().padLeft(3, '0')}',
        level: EqubLevel.low,
      ));
    }

    // Medium Level (50 members)
    for (int i = 1; i <= 50; i++) {
      mockList.add(EqubParticipant(
        id: 'med_$i',
        name: 'Medium Member #$i',
        phoneNumber: '+25192200${i.toString().padLeft(3, '0')}',
        level: EqubLevel.medium,
      ));
    }

    // High Level (20 members)
    for (int i = 1; i <= 20; i++) {
      mockList.add(EqubParticipant(
        id: 'high_$i',
        name: 'High Member #$i',
        phoneNumber: '+25193300${i.toString().padLeft(3, '0')}',
        level: EqubLevel.high,
      ));
    }

    _service.initializeLevelData(mockList);
  }

  Future<void> _selectRandomWinner() async {
    final eligible = _service.getEligibleParticipants(_activeLevel);
    if (eligible.isEmpty) {
      _showCompletionDialog();
      return;
    }

    setState(() => _isSelecting = true);

    // Shuffle animation loop
    for (int i = 0; i < 12; i++) {
      await Future.delayed(Duration(milliseconds: 70 + (i * 12)));
      final temp = eligible[Random().nextInt(eligible.length)];
      if (mounted) {
        setState(() => _spinnerText = '🎲 ${temp.name}');
      }
    }

    final result = _service.selectWinnerForLevel(_activeLevel);

    if (mounted) {
      setState(() {
        _isSelecting = false;
        _spinnerText = 'Tap to Draw';
      });

      if (result != null) {
        _showWinnerDialog(result);
      }
    }
  }

  Color _getLevelColor(EqubLevel level) => switch (level) {
        EqubLevel.low => const Color(0xFF2E7D32),
        EqubLevel.medium => const Color(0xFFED6C02),
        EqubLevel.high => const Color(0xFFD32F2F),
      };

  @override
  Widget build(BuildContext context) {
    final stats = _service.getStatistics(_activeLevel);
    final history = _service.getHistory(_activeLevel);
    final levelColor = _getLevelColor(_activeLevel);

    return Scaffold(
      appBar: AppBar(
        title: const Text('🇪🇹 Multi-Level EQUB Draw'),
        backgroundColor: levelColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'ዝቅተኛ (Low)'),
            Tab(text: 'መካከለኛ (Med)'),
            Tab(text: 'ከፍተኛ (High)'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Level Header Cards
          Container(
            padding: const EdgeInsets.all(16),
            color: levelColor.withAlpha(20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatCard(
                      'Prize Pool',
                      '${(stats['prizePool'] as double).toStringAsFixed(0)} ETB',
                      Icons.payments,
                      levelColor,
                    ),
                    _buildStatCard(
                      'Round',
                      '#${stats['currentRound']}',
                      Icons.workspace_premium,
                      levelColor,
                    ),
                    _buildStatCard(
                      'Remaining',
                      '${stats['remainingCount']} / ${stats['totalParticipants']}',
                      Icons.people,
                      levelColor,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: stats['progress'],
                    minHeight: 8,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(levelColor),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${((stats['progress'] as double) * 100).toStringAsFixed(1)}% Cycle Completed',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),

          // Action Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: _isSelecting ? null : _selectRandomWinner,
              style: ElevatedButton.styleFrom(
                backgroundColor: levelColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isSelecting
                  ? Text(
                      _spinnerText,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    )
                  : Text(
                      '🎲 Execute Round #${stats['currentRound'] + 1} Draw',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold),
                    ),
            ),
          ),

          // History Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '📜 ${_activeLevel.nameAmharic} History',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    setState(() => _service.resetLevel(_activeLevel));
                  },
                  tooltip: 'Reset Level',
                ),
              ],
            ),
          ),

          Expanded(
            child: history.isEmpty
                ? Center(
                    child: Text(
                      'No winners drawn yet for ${_activeLevel.nameAmharic}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[history.length - 1 - index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: levelColor,
                            foregroundColor: Colors.white,
                            child: Text('#${item.roundNumber}'),
                          ),
                          title: Text(
                            item.winner.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Won ${item.prizeAmount.toStringAsFixed(0)} ETB',
                          ),
                          trailing: const Icon(Icons.check_circle,
                              color: Colors.green),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 11)),
      ],
    );
  }

  void _showWinnerDialog(EqubDrawRecord result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Center(child: Text('🎉 Winner Selected!')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: _getLevelColor(result.level),
              child:
                  const Icon(Icons.emoji_events, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              result.winner.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            Text('Round #${result.roundNumber} Winner'),
            const SizedBox(height: 12),
            Text(
              'Payout Prize: ${result.prizeAmount.toStringAsFixed(0)} ETB',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _getLevelColor(result.level),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: _getLevelColor(result.level),
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          )
        ],
      ),
    );
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎉 All Participants Selected!'),
        content: Text(
            'All participants in ${_activeLevel.nameAmharic} have been drawn for this cycle.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _service.resetLevel(_activeLevel));
            },
            child: const Text('Reset Cycle'),
          )
        ],
      ),
    );
  }
}
