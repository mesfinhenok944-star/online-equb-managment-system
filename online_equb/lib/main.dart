import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'config/theme.dart';
import 'config/router.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    // Firebase not available on this platform (e.g., Linux desktop) or failed to initialize.
    // Log and continue — the app will run with Firestore/Auth features disabled or using fallbacks.
    debugPrint('Firebase.initializeApp() failed: $e');
    debugPrint('$st');
  }
  runApp(const EqubApp());
}

class EqubApp extends StatelessWidget {
  const EqubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthProvider()..loadFromStorage(),
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
