import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Base local offline-first del dispositivo (sección 18 del documento base:
/// "Base local cifrada en el dispositivo" — el cifrado a nivel de archivo se
/// añade con `sqflite_sqlcipher` en la fase de piloto territorial; este
/// scaffold usa sqflite estándar para mantener el MVP simple).
///
/// Espejo del esquema de backend/db/schema_sqlite.sql, más una tabla
/// `cola_sync` para la sincronización offline→online.
class DbLocal {
  DbLocal._();
  static final DbLocal instancia = DbLocal._();
  Database? _db;

  Future<Database> get db async {
    _db ??= await _abrir();
    return _db!;
  }

  Future<Database> _abrir() async {
    final ruta = join(await getDatabasesPath(), 'sigeria_campo.db');
    return openDatabase(
      ruta,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE evento (
            id_evento TEXT PRIMARY KEY,
            fenomeno TEXT NOT NULL,
            fecha_evento TEXT NOT NULL,
            municipio_divipola TEXT NOT NULL,
            descripcion TEXT,
            creado_en TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
        await db.execute('''
          CREATE TABLE objeto_afectado (
            id_objeto TEXT PRIMARY KEY,
            id_evento TEXT NOT NULL,
            tipo_objeto TEXT NOT NULL,
            estado_operativo TEXT NOT NULL DEFAULT 'sin_evaluar',
            nivel_dano_preliminar TEXT,
            creado_en TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
        await db.execute('''
          CREATE TABLE geometria (
            id_geometria TEXT PRIMARY KEY,
            id_objeto TEXT NOT NULL,
            geom_tipo TEXT NOT NULL,
            geom_geojson TEXT NOT NULL,
            precision_gnss_m REAL,
            fuente_posicion TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE medicion (
            id_medicion TEXT PRIMARY KEY,
            id_objeto TEXT NOT NULL,
            tipo TEXT NOT NULL,
            valor REAL NOT NULL,
            unidad TEXT NOT NULL,
            metodo TEXT NOT NULL,
            precision_categoria TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE necesidad (
            id_necesidad TEXT PRIMARY KEY,
            id_objeto TEXT NOT NULL,
            tipo TEXT NOT NULL,
            estado TEXT NOT NULL DEFAULT 'abierta'
          )
        ''');
        // Cola de sincronización: un registro por operación pendiente de subir.
        await db.execute('''
          CREATE TABLE cola_sync (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            tabla TEXT NOT NULL,
            id_registro TEXT NOT NULL,
            endpoint TEXT NOT NULL,
            payload_json TEXT NOT NULL,
            estado TEXT NOT NULL DEFAULT 'pendiente',
            intentos INTEGER NOT NULL DEFAULT 0,
            creado_en TEXT NOT NULL DEFAULT (datetime('now'))
          )
        ''');
      },
    );
  }

  Future<void> encolarSincronizacion({
    required String tabla,
    required String idRegistro,
    required String endpoint,
    required String payloadJson,
  }) async {
    final base = await db;
    await base.insert('cola_sync', {
      'tabla': tabla,
      'id_registro': idRegistro,
      'endpoint': endpoint,
      'payload_json': payloadJson,
      'estado': 'pendiente',
    });
  }

  Future<List<Map<String, Object?>>> pendientesDeSincronizar() async {
    final base = await db;
    return base.query('cola_sync', where: "estado = 'pendiente'");
  }
}
