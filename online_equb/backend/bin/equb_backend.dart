import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
// Avoid using dotenv API to keep startup simple; rely on environment variables.

Future<void> main(List<String> args) async {
  final portEnv = Platform.environment['PORT'];
  final port = int.tryParse(portEnv ?? '') ?? 8080;

  final router = Router()
    ..get('/', (Request req) => Response.ok('Equb backend is running'))
    ..get('/health', (Request req) => Response.ok('OK'))
    ..get('/api/ping', (Request req) => Response.ok('pong'));

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router);

  // Try binding to the requested port; if it's in use, try a few ports above it.
  HttpServer? server;
  for (var p = port; p < port + 10; p++) {
    try {
      server = await io.serve(handler, InternetAddress.anyIPv4, p);
      print('Server listening on port ${server.port}');
      break;
    } catch (e) {
      // If bind fails (address in use), try next port.
      stderr.writeln('Port $p unavailable: $e');
    }
  }
  if (server == null) {
    stderr.writeln('Failed to bind to any port in range $port..${port + 9}');
    exit(1);
  }
}
