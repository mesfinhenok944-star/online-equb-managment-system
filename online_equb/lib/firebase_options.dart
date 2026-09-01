// Firebase configuration — auto-generated from Firebase project:
//   online-equb-managment-system
//   Android package: et.equb.equb_app
//   Generated: 2026-08-23

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        // Firebase SDK does not support Linux/Windows desktop natively.
        // The app falls back to the REST backend on these platforms.
        throw UnsupportedError(
          'Firebase SDK is not supported on Linux/Windows desktop. '
          'The app uses the REST backend on this platform.',
        );
      default:
        throw UnsupportedError(
            'Unsupported platform: $defaultTargetPlatform');
    }
  }

  // ── Android — et.equb.equb_app ────────────────────────────────────────
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAFPB1jqtEBDE5XJzfxe4tBieqKE5g6L6E',
    appId: '1:64783274886:android:0e441b6c94bac31ea69207',
    messagingSenderId: '64783274886',
    projectId: 'online-equb-managment-sy-b5517',
    storageBucket: 'online-equb-managment-sy-b5517.firebasestorage.app',
  );

  // ── iOS — et.equb.equbApp (placeholder — add real iOS app in console) ─
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAFPB1jqtEBDE5XJzfxe4tBieqKE5g6L6E',
    appId: '1:64783274886:ios:0e441b6c94bac31ea69207',
    messagingSenderId: '64783274886',
    projectId: 'online-equb-managment-sy-b5517',
    storageBucket: 'online-equb-managment-sy-b5517.firebasestorage.app',
    iosBundleId: 'et.equb.equbApp',
  );

  // ── Web ───────────────────────────────────────────────────────────────
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAFPB1jqtEBDE5XJzfxe4tBieqKE5g6L6E',
    appId: '1:64783274886:web:0e441b6c94bac31ea69207',
    messagingSenderId: '64783274886',
    projectId: 'online-equb-managment-sy-b5517',
    authDomain: 'online-equb-managment-sy-b5517.firebaseapp.com',
    storageBucket: 'online-equb-managment-sy-b5517.firebasestorage.app',
  );

  // ── macOS ─────────────────────────────────────────────────────────────
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAFPB1jqtEBDE5XJzfxe4tBieqKE5g6L6E',
    appId: '1:64783274886:ios:0e441b6c94bac31ea69207',
    messagingSenderId: '64783274886',
    projectId: 'online-equb-managment-sy-b5517',
    storageBucket: 'online-equb-managment-sy-b5517.firebasestorage.app',
    iosBundleId: 'et.equb.equbApp',
  );
}
