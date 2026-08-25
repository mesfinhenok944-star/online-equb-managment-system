import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/theme.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../widgets/equb_level_card.dart';
import '../../widgets/page_header_banner.dart';
import '../../widgets/smart_back_button.dart';

class EqubListScreen extends StatefulWidget {
  const EqubListScreen({super.key});
  @override
  State<EqubListScreen> createState() => _EqubListScreenState();
}

class _EqubListScreenState extends State<EqubListScreen> {
  List<dynamic> _equbs = [];
  String _filter = 'all';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      List<dynamic> fsEqubs = [];
      try {
        fsEqubs = await FirestoreService.getEqubs();
      } catch (_) {}

      final apiEqubs = await ApiService.getEqubs();

      final combined = [...fsEqubs];
      for (final item in apiEqubs) {
        final key = (item['level'] ?? item['equbId'] ?? item['id'] ?? '').toString();
        if (!combined.any((e) => (e['level'] ?? e['equbId'] ?? e['id'] ?? '').toString() == key)) {
          combined.add(item);
        }
      }

      if (mounted) {
        setState(() {
          _equbs = combined.isNotEmpty ? combined : apiEqubs;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered => _filter == 'all'
      ? _equbs
      : _equbs.where((e) => e['level'] == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Equb Levels'),
        leading: const SmartBackButton(),
      ),
      body: Column(children: [
        // ── Animated page header banner ──────────────────────────────────
        PageHeaderBanner(
          color: AppColors.primary,
          icon: Icons.savings_rounded,
          phrases: PageHeaderBanner.equbPhrases,
          staticTitle: 'Ethiopian Digital Equb',
          height: 100,
        ),
        // Filter chips
        Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip('All', 'all', AppColors.primary),
              const SizedBox(width: 8),
              _chip('ዝቅተኛ Low', 'low', AppColors.low),
              const SizedBox(width: 8),
              _chip('መካከለኛ Medium', 'medium', AppColors.medium),
              const SizedBox(width: 8),
              _chip('ከፍተኛ High', 'high', AppColors.high),
            ]),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _filtered.isEmpty
                      ? const Center(child: Text('No equbs found'))
                      : LayoutBuilder(builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          int cols = 1;
                          if (width >= 900) cols = 3;
                          else if (width >= 600) cols = 2;
                          else cols = 1;

                          return GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1.0,
                            ),
                            itemCount: _filtered.length,
                            itemBuilder: (context, i) {
                              final item = _filtered[i];
                              return EqubLevelCard(
                                equb: item,
                                onTap: () => context.go('/equbs/${item['equbId'] ?? item['id']}'),
                              );
                            },
                          );
                        }),
                ),
        ),
      ]),
      floatingActionButton: auth.isAdmin ? FloatingActionButton.extended(
        onPressed: () => context.go('/equbs/create'),
        label: const Text('Create'),
        icon: const Icon(Icons.add),
      ) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/home');
              break;
            case 1:
              context.go('/equbs');
              break;
            case 2:
              if (!auth.isLoggedIn) {
                context.go('/login');
              } else if (auth.isAdmin) {
                context.go(auth.isSuperAdmin ? '/super-admin' : '/admin');
              } else {
                context.go('/profile');
              }
              break;
          }
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.savings_outlined),
              selectedIcon: Icon(Icons.savings),
              label: 'Equb'),
          NavigationDestination(
              icon: Icon(Icons.person_outlined),
              selectedIcon: Icon(Icons.person),
              label: 'Profile'),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, Color color) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label,
            style: TextStyle(
              color: selected ? Colors.white : color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            )),
      ),
    );
  }
}
