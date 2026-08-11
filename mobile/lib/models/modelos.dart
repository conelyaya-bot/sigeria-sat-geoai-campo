/// Modelos de dominio de SIGERIA Campo — reflejan 1:1 las tablas de
/// backend/db/schema_sqlite.sql para que la sincronización sea directa.
library modelos;

class Evento {
  final String idEvento;
  final String fenomeno; // sismo | inundacion | deslizamiento | vendaval | incendio | ...
  final DateTime fechaEvento;
  final String municipioDivipola;
  final String? descripcion;

  Evento({
    required this.idEvento,
    required this.fenomeno,
    required this.fechaEvento,
    required this.municipioDivipola,
    this.descripcion,
  });

  Map<String, dynamic> toMap() => {
        'id_evento': idEvento,
        'fenomeno': fenomeno,
        'fecha_evento': fechaEvento.toIso8601String(),
        'municipio_divipola': municipioDivipola,
        'descripcion': descripcion,
      };

  factory Evento.fromMap(Map<String, dynamic> m) => Evento(
        idEvento: m['id_evento'],
        fenomeno: m['fenomeno'],
        fechaEvento: DateTime.parse(m['fecha_evento']),
        municipioDivipola: m['municipio_divipola'],
        descripcion: m['descripcion'],
      );
}

enum EstadoOperativo { operativo, parcial, fueraDeServicio, sinEvaluar }
enum NivelDano { sinDano, leve, moderado, severo, colapso }
enum EstadoSincronizacion { pendiente, sincronizado, error }

class ObjetoAfectado {
  final String idObjeto; // generado por el backend al sincronizar; localmente usa UUID temporal
  final String idEvento;
  final String tipoObjeto;
  EstadoOperativo estadoOperativo;
  NivelDano? nivelDanoPreliminar;
  EstadoSincronizacion sync;

  ObjetoAfectado({
    required this.idObjeto,
    required this.idEvento,
    required this.tipoObjeto,
    this.estadoOperativo = EstadoOperativo.sinEvaluar,
    this.nivelDanoPreliminar,
    this.sync = EstadoSincronizacion.pendiente,
  });
}

class GeometriaCapturada {
  final String idObjeto;
  final String geomTipo; // Point | LineString | Polygon
  final Map<String, dynamic> geomGeoJson;
  final double? precisionGnssM;
  final String fuentePosicion; // gnss_interno | gnss_externo | manual

  GeometriaCapturada({
    required this.idObjeto,
    required this.geomTipo,
    required this.geomGeoJson,
    this.precisionGnssM,
    this.fuentePosicion = 'gnss_interno',
  });

  /// Regla de calidad (sección 21 del documento base): advertir si la
  /// precisión GNSS supera el umbral, sin bloquear la captura.
  bool get precisionBaja => (precisionGnssM ?? 0) > 15;
}

class MedicionMovil {
  final String idObjeto;
  final String tipo; // distancia | area | pendiente | altura | grieta
  final double valor;
  final String unidad;
  final String metodo; // sensor_telefono | equipo_externo
  final String precisionCategoria; // orientativa | certificada

  MedicionMovil({
    required this.idObjeto,
    required this.tipo,
    required this.valor,
    required this.unidad,
    this.metodo = 'sensor_telefono',
    this.precisionCategoria = 'orientativa',
  });
}

class NecesidadUrgente {
  final String idObjeto;
  final String tipo; // agua | alimento | refugio | salud | otro
  String estado; // abierta | atendida | cerrada

  NecesidadUrgente({
    required this.idObjeto,
    required this.tipo,
    this.estado = 'abierta',
  });
}
