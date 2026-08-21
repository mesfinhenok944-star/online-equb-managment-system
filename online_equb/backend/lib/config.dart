import 'dart:io';
import 'package:shelf/shelf.dart';

// ─────────────────────────────────────────────────────────────────────────────
// App Configuration
// Reads from environment variables (set in .env or exported in shell).
// ─────────────────────────────────────────────────────────────────────────────

class Config {
  // Firebase
  static String get projectId =>
      Platform.environment['FIREBASE_PROJECT_ID'] ?? 'your-firebase-project-id';

  static String get webApiKey =>
      Platform.environment['FIREBASE_WEB_API_KEY'] ?? 'your-firebase-web-api-key';

  // Firebase REST base URLs
  static String get firestoreBase =>
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  static String get authBase =>
      'https://identitytoolkit.googleapis.com/v1';

  // Super Admin defaults
  static String get superAdminEmail =>
      Platform.environment['SUPER_ADMIN_EMAIL'] ?? 'superadmin@equb.et';

  static String get superAdminUsername =>
      Platform.environment['SUPER_ADMIN_USERNAME'] ?? 'superadmin';

  static String get superAdminPassword =>
      Platform.environment['SUPER_ADMIN_PASSWORD'] ?? 'admin123';

  // Server
  static int get port =>
      int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;

  static String get host =>
      Platform.environment['HOST'] ?? '0.0.0.0';
}

// ─────────────────────────────────────────────────────────────────────────────
// CORS + JSON middleware
// ─────────────────────────────────────────────────────────────────────────────

Middleware corsMiddleware() {
  const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
    'Access-Control-Allow-Headers':
        'Origin, Content-Type, Accept, Authorization',
  };

  return (Handler inner) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: corsHeaders);
      }
      final response = await inner(request);
      return response.change(headers: corsHeaders);
    };
  };
}

Middleware logMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      final start = DateTime.now();
      final response = await inner(request);
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      print('[${DateTime.now().toIso8601String()}] '
          '${request.method} ${request.requestedUri.path} '
          '→ ${response.statusCode} (${elapsed}ms)');
      return response;
    };
  };
}
