import 'dart:convert';
import 'package:shelf/shelf.dart';

/// Enforce the limit on bytes while reading, before allocating a full body.
Future<Map<String, dynamic>?> readJsonBody(
    Request request, int maxBytes) async {
  if ((request.contentLength ?? 0) > maxBytes) return null;
  try {
    final bytes = <int>[];
    await for (final chunk in request.read()) {
      if (bytes.length + chunk.length > maxBytes) return null;
      bytes.addAll(chunk);
    }
    final value = jsonDecode(utf8.decode(bytes));
    return value is Map<String, dynamic> ? value : null;
  } catch (_) {
    return null;
  }
}
