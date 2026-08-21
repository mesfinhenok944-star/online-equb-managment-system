import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Return a JSON response with the given status code.
Response jsonResponse(dynamic data, {int status = 200}) {
  return Response(
    status,
    body: jsonEncode(data),
    headers: {'Content-Type': 'application/json'},
  );
}

/// Return a JSON error response.
Response jsonError(String message, {int status = 400}) {
  return jsonResponse({'error': message}, status: status);
}

/// Parse the request body as a JSON map. Returns null on failure.
Future<Map<String, dynamic>?> parseBody(Request request) async {
  try {
    final raw = await request.readAsString();
    if (raw.isEmpty) return {};
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

/// Generate a timestamp string (ISO 8601).
String nowIso() => DateTime.now().toUtc().toIso8601String();

/// Simple unique ID generator (no external package dependency on server side).
String generateId([String prefix = 'id']) {
  final ms = DateTime.now().millisecondsSinceEpoch;
  final rnd = (ms % 999999).toString().padLeft(6, '0');
  return '${prefix}_$ms$rnd';
}
