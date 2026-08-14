import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../data/inspeccion_ais_opciones.dart';
import '../services/api_client.dart';
import 'editar_expediente_screen.dart';

/// Ficha de un expediente ya guardado — la pantalla que faltaba para
/// CONSULTAR lo levantado (no solo capturarlo): todos los datos, las fotos
/// reales, el punto GPS en un mini-mapa, y botones para editar o eliminar
/// por si algo quedó mal digitado.
class FichaExpedienteScreen extends StatefulWidget {
  final String backendUrl;
  final String idObjeto;
  const FichaExpedienteScreen({super.key, required this.backendUrl, required this.idObjeto});

  @override
  State<FichaExpedienteScreen> createState() => _FichaExpedienteScreenState();
}

class _FichaExpedienteScreenState extends State<FichaExpedienteScreen> {
  bool _cargando = true;
  String? _error;
  Map<String, dynamic>? _datos;
  MapLibreMapController? _mapController;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final api = ApiClient(baseUrl: widget.backendUrl);
      final datos = await api.get('/api/expedientes/${widget.idObjeto}/detalle');
      if (!mounted) return;
      setState(() {
        _datos = datos;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  Future<void> _editar() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditarExpedienteScreen(backendUrl: widget.backendUrl, idObjeto: widget.idObjeto),
      ),
    );
    if (resultado == true) _cargar();
  }

  Future<void> _eliminar() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Eliminar este expediente?'),
        content: Text(
          '${widget.idObjeto}\n\nEsto borra el registro, sus fotos, su ubicación y sus '
          'mediciones. No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final api = ApiClient(baseUrl: widget.backendUrl);
      await api.delete('/api/expedientes/${widget.idObjeto}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expediente eliminado.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.idObjeto, style: const TextStyle(fontSize: 14)),
        actions: [
          if (_datos != null) ...[
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar', onPressed: _editar),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar', onPressed: _eliminar),
          ],
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')))
              : _contenido(),
    );
  }

  Widget _contenido() {
    final objeto = _datos!['objeto_afectado'] as Map<String, dynamic>;
    final evento = _datos!['evento'] as Map<String, dynamic>?;
    final geometrias = _datos!['geometrias'] as List<dynamic>;
    final necesidades = _datos!['necesidades'] as List<dynamic>;
    final mediciones = _datos!['mediciones'] as List<dynamic>;
    final evidencias = (_datos!['evidencias'] as List<dynamic>)
        .where((e) => e['tipo'] == 'foto')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _tarjeta('Evento', [
          _fila('Fenómeno', evento?['fenomeno']),
          _fila('Fecha', evento?['fecha_evento']),
          _fila('Municipio (DIVIPOLA)', evento?['municipio_divipola']),
        ]),
        _tarjeta('Objeto afectado', [
          _fila('Tipo', objeto['tipo_objeto']),
          _fila('Estado operativo', objeto['estado_operativo']),
          _fila('Departamento', objeto['departamento']),
          _fila('Barrio/vereda', objeto['barrio_vereda']),
          _fila('Dirección', objeto['direccion']),
        ]),
        _tarjeta('Responsable / informante', [
          _fila('Recolector', objeto['recolector_nombre']),
          _fila('Entidad', objeto['recolector_entidad']),
          _fila('Informante', objeto['informante_nombre']),
          _fila('Teléfono informante', objeto['informante_telefono']),
        ]),
        _tarjetaInspeccionAis(_datos!['inspeccion_ais'] as Map<String, dynamic>?),
        _tarjeta('Necesidades humanitarias', [
          _fila('Personas afectadas', objeto['personas_afectadas']?.toString()),
          _fila('Subsidio de arrendamiento',
              objeto['requiere_subsidio_arrendamiento'] == null
                  ? null
                  : (objeto['requiere_subsidio_arrendamiento'] == true ? 'Sí' : 'No')),
        ]),
        if (necesidades.isNotEmpty)
          _tarjeta(
            'Necesidades',
            [Wrap(spacing: 6, children: [for (final n in necesidades) Chip(label: Text(n['tipo']))])],
          ),
        if (mediciones.isNotEmpty)
          _tarjeta('Mediciones', [
            for (final m in mediciones) _fila(m['tipo'], '${m['valor']} ${m['unidad']}'),
          ]),
        _tarjetaUbicacion(geometrias),
        _tarjetaFotos(evidencias),
        const SizedBox(height: 24),
      ],
    );
  }

  /// Inspección técnica AIS ("Guía Técnica para la Inspección de
  /// Edificaciones Después de un Sismo") — formulario oficial que reemplazó
  /// el checklist simplificado. Muestra lo más relevante para una lectura
  /// rápida: clasificación de habitabilidad con su color oficial primero
  /// (lo que de verdad importa a simple vista), luego el resto por
  /// secciones iguales al formulario en papel.
  Widget _tarjetaInspeccionAis(Map<String, dynamic>? ais) {
    if (ais == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.rule_folder_outlined, color: Colors.grey),
          title: const Text('Sin inspección técnica AIS'),
          subtitle: const Text('Toca Editar para diligenciarla.'),
        ),
      );
    }
    final colorHab = ais['clasificacion_habitabilidad'] as String?;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inspección técnica AIS', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (colorHab != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _colorHabitabilidad(colorHab).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _colorHabitabilidad(colorHab)),
                ),
                child: Row(children: [
                  Icon(Icons.warning_amber, color: _colorHabitabilidad(colorHab)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      etiquetaHabitabilidad[colorHab] ?? colorHab,
                      style: TextStyle(color: _colorHabitabilidad(colorHab), fontWeight: FontWeight.bold),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            // Las 5 evaluaciones independientes (sección 2.9 de la guía
            // IDIGER 2018) — la habitabilidad de arriba es la más
            // conservadora de estas 5, no un cálculo aparte.
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chipClasificacionAis('A: Estado general', ais['clasificacion_a_estado_general']),
                _chipClasificacionAis('B: Geotécnico', ais['clasificacion_b_geotecnico']),
                _chipClasificacionAis('C: No estructural', ais['clasificacion_c_no_estructural']),
                _chipClasificacionAis('D: Estructural', ais['clasificacion_d_estructural']),
                _chipClasificacionAis('E: Entorno', ais['clasificacion_e_entorno']),
              ],
            ),
            const SizedBox(height: 8),
            _fila('% de daño global (estimado, no decide habitabilidad)',
                ais['pct_dano_global']?.toString()),
            _fila('Sistema estructural',
                _etiquetaOpcion(sistemasEstructurales, ais['sistema_estructural'])),
            _fila('Tipo de entrepiso', _etiquetaOpcion(tiposEntrepiso, ais['tipo_entrepiso'])),
            _fila('Año de construcción',
                _etiquetaOpcion(aniosConstruccion, ais['anio_construccion'])),
            _fila('¿Existe colapso?', _etiquetaOpcion(existeColapsoOpciones, ais['existe_colapso'])),
            _fila('Desviación / inclinación',
                _etiquetaOpcion(siNoIndeterminado, ais['desviacion_inclinacion'])),
            _fila('Falla en cimentación',
                _etiquetaOpcion(siNoIndeterminado, ais['falla_asentamiento_cimentacion'])),
            _fila('Muros de fachada', _etiquetaOpcion(gradoDanoAis, ais['dano_muros_fachada'])),
            _fila('Cubierta', _etiquetaOpcion(gradoDanoAis, ais['dano_cubierta'])),
            _fila('Columnas o muros portantes',
                _etiquetaOpcion(gradoDanoAis, ais['dano_columnas_muros_portantes'])),
            if ((ais['instalaciones_afectadas'] as List<dynamic>? ?? []).isNotEmpty)
              _fila('Instalaciones afectadas',
                  (ais['instalaciones_afectadas'] as List<dynamic>)
                      .map((v) => _etiquetaOpcion(instalacionesOpciones, v))
                      .join(', ')),
            if ((ais['medidas_seguridad'] as List<dynamic>? ?? []).isNotEmpty)
              _fila('Medidas de seguridad',
                  (ais['medidas_seguridad'] as List<dynamic>)
                      .map((v) => _etiquetaOpcion(medidasSeguridadOpciones, v))
                      .join(', ')),
            _fila('¿Edificación habitada?',
                ais['edificacion_habitada'] == null ? null : (ais['edificacion_habitada'] == true ? 'Sí' : 'No')),
            _fila('Hubo muertos o heridos',
                _etiquetaOpcion(huboMuertosHeridosOpciones, ais['hubo_muertos_heridos'])),
            _fila('Comentarios', ais['comentarios']),
            _fila('Código de la comisión', ais['codigo_comision']),
            _fila('Líder de la comisión', ais['nombre_lider_comision']),
            _fila('Fecha de inspección', ais['fecha_inspeccion']),
          ],
        ),
      ),
    );
  }

  /// Chip pequeño para una de las 5 sub-clasificaciones A-E — mismo color
  /// que tendría si esa fuera la clasificación final (verde/amarillo/
  /// naranja/rojo), para poder ver de un vistazo cuál de las 5 fue la que
  /// definió el resultado (la más conservadora).
  Widget _chipClasificacionAis(String etiqueta, dynamic valor) {
    const colorPorClasificacion = {
      'habitable': 'verde', 'uso_restringido': 'amarillo',
      'no_habitable': 'naranja', 'peligro_colapso': 'rojo',
    };
    final color = colorPorClasificacion[valor];
    return Chip(
      label: Text(
        '$etiqueta: ${etiquetaClasificacionAbcde[valor] ?? '—'}',
        style: const TextStyle(fontSize: 11),
      ),
      backgroundColor: color != null ? _colorHabitabilidad(color).withValues(alpha: 0.15) : null,
      side: color != null ? BorderSide(color: _colorHabitabilidad(color)) : null,
      visualDensity: VisualDensity.compact,
    );
  }

  String? _etiquetaOpcion(List<Map<String, String>> opciones, dynamic valor) {
    if (valor == null) return null;
    for (final o in opciones) {
      if (o['valor'] == valor) return o['etiqueta'];
    }
    return valor.toString();
  }

  Color _colorHabitabilidad(String colorNombre) {
    switch (colorNombre) {
      case 'verde':
        return const Color(0xFF2E8B57);
      case 'amarillo':
        return const Color(0xFFC9B400);
      case 'naranja':
        return const Color(0xFFE08A1E);
      case 'rojo':
        return const Color(0xFFD1392B);
      default:
        return Colors.grey;
    }
  }

  Widget _tarjetaUbicacion(List<dynamic> geometrias) {
    if (geometrias.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.gps_off, color: Colors.grey),
          title: const Text('Sin ubicación GPS capturada'),
          subtitle: const Text('Toca Editar para agregarla ahora.'),
          trailing: TextButton(onPressed: _editar, child: const Text('Agregar')),
        ),
      );
    }
    final geom = geometrias.first as Map<String, dynamic>;
    final coords = (geom['geom_geojson'] as Map<String, dynamic>)['coordinates'] as List<dynamic>;
    final lon = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Ubicación', style: Theme.of(context).textTheme.titleMedium),
          ),
          ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(4)),
            child: SizedBox(
              height: 180,
              child: MapLibreMap(
                styleString: 'styles/satelital.json',
                initialCameraPosition: CameraPosition(target: LatLng(lat, lon), zoom: 16),
                onMapCreated: (c) => _mapController = c,
                onStyleLoadedCallback: () async {
                  await _mapController?.addCircle(CircleOptions(
                    geometry: LatLng(lat, lon),
                    circleRadius: 9,
                    circleColor: '#e08a1e',
                    circleStrokeColor: '#ffffff',
                    circleStrokeWidth: 2,
                  ));
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Lat ${lat.toStringAsFixed(5)}, Lon ${lon.toStringAsFixed(5)}'
              '${geom['precision_gnss_m'] != null ? ' (±${(geom['precision_gnss_m'] as num).toStringAsFixed(1)} m)' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaFotos(List<dynamic> evidencias) {
    if (evidencias.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.no_photography, color: Colors.grey),
          title: const Text('Sin fotos guardadas'),
          subtitle: const Text('Toca Editar para agregar una ahora.'),
          trailing: TextButton(onPressed: _editar, child: const Text('Agregar')),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Fotos (${evidencias.length})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in evidencias)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '${widget.backendUrl}/api/edan/evidencias/${e['id_evidencia']}/archivo',
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 100,
                        height: 100,
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.broken_image),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(String titulo, List<Widget> hijos) {
    final visibles = hijos.where((h) => h is! SizedBox).toList();
    if (visibles.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ...hijos,
          ],
        ),
      ),
    );
  }

  Widget _fila(String etiqueta, String? valor) {
    if (valor == null || valor.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13),
          children: [
            TextSpan(text: '$etiqueta: ', style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: valor),
          ],
        ),
      ),
    );
  }
}
