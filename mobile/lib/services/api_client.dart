import 'dart:convert';
import 'package:http/http.dart' as http;

/// Cliente HTTP mínimo hacia el backend SIGERIA (`backend/app/main.py`).
/// Se usa cuando hay conexión directa; si falla, la pantalla que lo llama
/// debe encolar la operación en [SyncQueue] (services/sync_queue.dart) para
/// reintentar offline-first — mismo contrato, mismos endpoints.
class ApiClient {
  final String baseUrl;
  const ApiClient({required this.baseUrl});

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final resp = await http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> get(String path) async {
    final resp = await http.get(Uri.parse('$baseUrl$path')).timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  /// GET que devuelve una lista (p. ej. `/api/expedientes/lista`), en vez de
  /// un solo objeto — mismo cliente, distinto tipo de respuesta esperada.
  Future<List<dynamic>> getLista(String path) async {
    final resp = await http.get(Uri.parse('$baseUrl$path')).timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final resp = await http
        .put(
          Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('${resp.statusCode}: ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<void> delete(String path) async {
    final resp = await http.delete(Uri.parse('$baseUrl$path')).timeout(const Duration(seconds: 15));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('${resp.statusCode}: ${resp.body}');
    }
  }
}
