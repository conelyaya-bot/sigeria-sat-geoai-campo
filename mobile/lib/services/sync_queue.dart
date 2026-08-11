import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'db_local.dart';

/// Cola de sincronización offline→online (sección 18 del documento base).
/// Reintenta cuando hay conectividad; no sobrescribe en silencio (guarda el
/// estado de cada intento). El backend es la app FastAPI en `backend/`.
class SyncQueue {
  final String baseUrl;
  SyncQueue({required this.baseUrl});

  Future<bool> hayConexion() async {
    final resultado = await Connectivity().checkConnectivity();
    return !resultado.contains(ConnectivityResult.none);
  }

  /// Recorre la cola local y sube cada operación pendiente al backend.
  /// Devuelve un resumen {enviados, fallidos} para mostrar en la UI
  /// (indicador "Porcentaje sincronizado vs. pendiente offline" — sección 26).
  Future<Map<String, int>> sincronizar() async {
    var enviados = 0;
    var fallidos = 0;

    if (!await hayConexion()) {
      return {'enviados': 0, 'fallidos': 0, 'sin_conexion': 1};
    }

    final pendientes = await DbLocal.instancia.pendientesDeSincronizar();
    for (final item in pendientes) {
      try {
        final resp = await http.post(
          Uri.parse('$baseUrl${item['endpoint']}'),
          headers: {'Content-Type': 'application/json'},
          body: item['payload_json'] as String,
        );
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          final base = await DbLocal.instancia.db;
          await base.update(
            'cola_sync',
            {'estado': 'sincronizado'},
            where: 'id = ?',
            whereArgs: [item['id']],
          );
          enviados++;
        } else {
          fallidos++;
        }
      } catch (_) {
        // Sin conexión real o error de red: se reintenta en el próximo ciclo.
        fallidos++;
      }
    }
    return {'enviados': enviados, 'fallidos': fallidos};
  }
}
