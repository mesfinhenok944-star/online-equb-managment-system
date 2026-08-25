import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart';
import 'config/theme.dart';
import 'config/router.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'services/offline_service.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase on supported platforms (Android, iOS, Web, macOS).
  // Linux/Windows desktop fall back to REST backend — no Firebase SDK needed.
  bool firebaseReady = false;
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
      debugPrint('[Firebase] Linux desktop — using REST backend only.');
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
      debugPrint('[Firebase] ✅ Initialised successfully for ${defaultTargetPlatform.name}.');
    }
  } catch (e) {
    debugPrint('[Firebase] ⚠️ initializeApp skipped: $e');
  }

  // Offline cache + connectivity watcher (also syncs queued writes to backend)
  await OfflineService.init();
  // Detect correct server URL (real device vs emulator)
  await ApiService.detectServerUrl();

  runApp(EqubApp(firebaseReady: firebaseReady));
}

class EqubApp extends StatelessWidget {
  final bool firebaseReady;
  const EqubApp({super.key, required this.firebaseReady});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider(firebaseReady: firebaseReady)
        ..loadFromStorage(),
      child: Consumer<AuthProvider>(
        builder: (_, auth, __) => MaterialApp.router(
          title: 'Online Equb',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          routerConfig: appRouter(auth),
        ),
      ),
    );
  }
}
