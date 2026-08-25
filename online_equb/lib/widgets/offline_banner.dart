import 'package:flutter/material.dart';
import '../services/offline_service.dart';

/// Clean banner displayed at top of screens when app is offline
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key});

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _isOffline = !OfflineService.isOnline;
    OfflineService.onConnectivityChanged.listen((isOnline) {
      if (mounted) {
        setState(() => _isOffline = !isOnline);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isOffline) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      color: Colors.amber.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '⚡ Offline Mode — Displaying Cached Data (Actions will sync automatically when back online)',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
