import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';

/// Mapa real de SIGERIA Campo — inspirado en la estructura de SW Maps
/// (mapa base + galería de capas + señalización de los datos levantados):
///
///  - Selector de mapa base: Calle (OpenStreetMap) / Satelital (Esri World
///    Imagery, equivalente libre a la vista "Google Earth" que usa SW Maps —
///    Google Satellite/Earth exige API key y facturación que este proyecto
///    no tiene configurada) / Híbrido (satélite + etiquetas de referencia).
///  - Botón "Mi ubicación" con GPS real (paquete geolocator).
///  - Capa "Objetos afectados" — señala en el mapa, con color por severidad,
///    la ubicación real de cada dato levantado (mismo criterio de color que
///    el dashboard web y el proyecto QGIS, para que los tres se vean igual).
///  - Al tocar un punto, se abre una ficha con los datos y la foto real de
///    esa vivienda — la "malla de puntos" se puede consultar una por una.
class MapaScreen extends StatefulWidget {
  /// backendUrl + idEvento -> mapa "en vivo" de un solo evento recién guardado.
  /// solo backendUrl (sin idEvento) -> mapa GENERAL en vivo con TODOS los
  /// expedientes guardados hasta el momento (la malla de puntos creciendo).
  /// Sin ninguno de los dos -> ejemplo estático de demostración.
  final String? backendUrl;
  final String? idEvento;

  const MapaScreen({super.key, this.backendUrl, this.idEvento});

  @override
  State<MapaScreen> createState() => _MapaScreenState();
}

enum _Basemap { calle, satelital, hibrido }

class _MapaScreenState extends State<MapaScreen> {
  MapLibreMapController? _controller;
  _Basemap _basemap = _Basemap.satelital;
  bool _capaObjetosVisible = true;
  bool _cargandoUbicacion = false;
  String? _estado;
  List<dynamic> _features = []; // features del último GeoJSON cargado, para la ficha al tocar

  static const _estilos = {
    _Basemap.calle: 'styles/calle.json',
    _Basemap.satelital: 'styles/satelital.json',
    _Basemap.hibrido: 'styles/hibrido.json',
  };

  static const _etiquetasBasemap = {
    _Basemap.calle: 'Calle (OpenStreetMap — edificios y vías)',
    _Basemap.satelital: 'Satelital (estilo Google Earth)',
    _Basemap.hibrido: 'Híbrido (satélite + etiquetas)',
  };

  static const _etiquetasSeveridad = {
    'sin_dano': 'Sin daño', 'leve': 'Leve', 'moderado': 'Parcial (no estructural)',
    'severo': 'Estructural', 'colapso': 'Colapso / destrucción total', null: 'Sin evaluar',
  };

  @override
  void dispose() {
    _controller?.onFeatureTapped.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tituloMapa),
        actions: [
          IconButton(
            icon: _cargandoUbicacion
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.my_location),
            tooltip: 'Mi ubicación (GPS real)',
            onPressed: _cargandoUbicacion ? null : _irAMiUbicacion,
          ),
        ],
      ),
      body: Stack(
        children: [
          MapLibreMap(
            styleString: _estilos[_basemap]!,
            initialCameraPosition: const CameraPosition(
              target: LatLng(5.6947, -76.6413), // Quibdó, Chocó
              zoom: 8,
            ),
            myLocationEnabled: false, // se activa con permiso al pulsar el botón GPS
            onMapCreated: _alCrearMapa,
            onStyleLoadedCallback: _alCargarEstilo,
          ),
          if (_estado != null)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Card(
                color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_estado!, style: const TextStyle(fontSize: 13)),
                ),
              ),
            ),
          Positioned(
            bottom: 16,
            left: 16,
            child: Chip(
              avatar: const Icon(Icons.circle, size: 12, color: Colors.transparent),
              label: Text('${_features.length} punto(s) en el mapa'),
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              onPressed: _abrirCapas,
              icon: const Icon(Icons.layers),
              label: const Text('Capas'),
            ),
          ),
        ],
      ),
    );
  }

  String get _tituloMapa {
    if (widget.idEvento != null) return 'Georreferenciación en tiempo real';
    if (widget.backendUrl != null) return 'Mapa general — malla de puntos';
    return 'Mapa — GIS de campo (demo)';
  }

  bool get _esEnVivo => widget.backendUrl != null;

  void _alCrearMapa(MapLibreMapController c) {
    _controller = c;
    c.onFeatureTapped.add(_alTocarFeature);
  }

  Future<void> _alCargarEstilo() async {
    final c = _controller;
    if (c == null) return;
    setState(() => _estado = _esEnVivo
        ? 'Cargando georreferenciación en tiempo real…'
        : 'Cargando objetos afectados…');
    try {
      Map<String, dynamic> geojson;
      if (widget.idEvento != null) {
        final resp = await http
            .get(Uri.parse('${widget.backendUrl}/api/gis/geojson/${widget.idEvento}'))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) throw Exception('Backend respondió ${resp.statusCode}');
        geojson = jsonDecode(resp.body) as Map<String, dynamic>;
      } else if (widget.backendUrl != null) {
        final resp = await http
            .get(Uri.parse('${widget.backendUrl}/api/gis/geojson_general'))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode != 200) throw Exception('Backend respondió ${resp.statusCode}');
        geojson = jsonDecode(resp.body) as Map<String, dynamic>;
      } else {
        final texto = await rootBundle.loadString('assets/gis/objetos_afectados_demo.geojson');
        geojson = jsonDecode(texto) as Map<String, dynamic>;
      }

      _features = geojson['features'] as List<dynamic>? ?? [];

      // Si el estilo se recargó (cambio de basemap), la fuente ya no existe: recrearla.
      await c.addGeoJsonSource('objetos_afectados', geojson);
      await c.addCircleLayer(
        'objetos_afectados',
        'objetos_afectados_circulos',
        CircleLayerProperties(
          circleRadius: 8,
          circleStrokeWidth: 2,
          circleStrokeColor: '#ffffff',
          circleColor: [
            'match',
            ['get', 'nivel_dano_preliminar'],
            'sin_dano', '#2e8b57',
            'leve', '#c9b400',
            'moderado', '#e08a1e',
            'severo', '#d1392b',
            'colapso', '#6b0f1a',
            '#8a8f98', // valor por defecto: sin evaluar
          ],
        ),
      );
      setState(() => _estado = null);
    } catch (e) {
      setState(() => _estado = 'No se pudo cargar la capa de objetos afectados: $e');
    }
  }

  /// Al tocar un punto: busca la feature más cercana a la coordenada tocada
  /// (el callback de maplibre_gl no siempre trae el id tal cual del GeoJSON)
  /// y abre la ficha con sus datos + foto real.
  void _alTocarFeature(
      Point<double> point, LatLng coordinates, String id, String layerId, Annotation? anotacion) {
    if (layerId != 'objetos_afectados_circulos' || _features.isEmpty) return;

    dynamic mejor;
    var mejorDistancia = double.infinity;
    for (final f in _features) {
      final geom = f['geometry'];
      if (geom == null || geom['type'] != 'Point') continue;
      final coords = geom['coordinates'] as List<dynamic>;
      final lon = (coords[0] as num).toDouble();
      final lat = (coords[1] as num).toDouble();
      final d = _distanciaAprox(lat, lon, coordinates.latitude, coordinates.longitude);
      if (d < mejorDistancia) {
        mejorDistancia = d;
        mejor = f;
      }
    }
    if (mejor != null) _abrirFicha(mejor as Map<String, dynamic>);
  }

  double _distanciaAprox(double lat1, double lon1, double lat2, double lon2) {
    final dLat = lat1 - lat2, dLon = lon1 - lon2;
    return dLat * dLat + dLon * dLon; // suficiente para comparar, no hace falta la distancia real
  }

  void _abrirFicha(Map<String, dynamic> feature) {
    final p = feature['properties'] as Map<String, dynamic>;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => FichaObjeto(
          properties: p,
          backendUrl: widget.backendUrl,
          etiquetasSeveridad: _etiquetasSeveridad,
          scrollController: scrollController,
        ),
      ),
    );
  }

  Future<void> _irAMiUbicacion() async {
    setState(() => _cargandoUbicacion = true);
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        setState(() => _estado = 'Permiso de ubicación denegado — actívalo en el navegador/SO.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      await _controller?.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 16),
      );
      setState(() => _estado =
          'Ubicación real: ${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)} '
          '(±${pos.accuracy.toStringAsFixed(1)} m)');
    } catch (e) {
      setState(() => _estado = 'No se pudo obtener el GPS: $e');
    } finally {
      setState(() => _cargandoUbicacion = false);
    }
  }

  void _abrirCapas() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Capas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const Divider(height: 1),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Mapa base', style: TextStyle(color: Colors.grey)),
                ),
              ),
              for (final b in _Basemap.values)
                RadioListTile<_Basemap>(
                  title: Text(_etiquetasBasemap[b]!),
                  value: b,
                  groupValue: _basemap,
                  onChanged: (v) {
                    setState(() => _basemap = v!);
                    setSheetState(() {});
                  },
                ),
              const Divider(),
              SwitchListTile(
                title: const Text('Objetos afectados (datos levantados)'),
                subtitle: const Text('Señala en el mapa la ubicación real de cada registro'),
                value: _capaObjetosVisible,
                onChanged: (v) async {
                  setState(() => _capaObjetosVisible = v);
                  setSheetState(() {});
                  if (_controller != null) {
                    await _controller!.setLayerVisibility('objetos_afectados_circulos', v);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ficha que se abre al tocar un punto del mapa: datos del objeto afectado +
/// foto real (si el backend está disponible y la evidencia se guardó con
/// contenido, ver backend/app/routers/edan.py:descargar_evidencia).
class FichaObjeto extends StatefulWidget {
  final Map<String, dynamic> properties;
  final String? backendUrl;
  final Map<String?, String> etiquetasSeveridad;
  final ScrollController scrollController;

  const FichaObjeto({
    required this.properties,
    required this.backendUrl,
    required this.etiquetasSeveridad,
    required this.scrollController,
  });

  @override
  State<FichaObjeto> createState() => FichaObjetoState();
}

class FichaObjetoState extends State<FichaObjeto> {
  List<dynamic> _fotos = [];
  bool _cargandoFotos = true;

  @override
  void initState() {
    super.initState();
    _cargarFotos();
  }

  Future<void> _cargarFotos() async {
    if (widget.backendUrl == null) {
      setState(() => _cargandoFotos = false);
      return;
    }
    try {
      final idObjeto = widget.properties['id_objeto'];
      final resp = await http
          .get(Uri.parse('${widget.backendUrl}/api/expedientes/$idObjeto/exportar'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _fotos = (data['evidencias'] as List<dynamic>? ?? [])
            .where((e) => e['tipo'] == 'foto')
            .toList();
      }
    } catch (_) {
      // Sin conexión al backend — la ficha igual muestra los datos ya conocidos.
    } finally {
      if (mounted) setState(() => _cargandoFotos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.properties;
    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        const SizedBox(height: 12),
        Text(p['id_objeto']?.toString() ?? '—',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        _fila('Tipo de objeto', p['tipo_objeto']),
        _fila('Fenómeno', p['fenomeno']),
        _fila('Municipio (DIVIPOLA)', p['municipio_divipola']),
        _fila('Departamento', p['departamento']),
        _fila('Barrio/vereda', p['barrio_vereda']),
        _fila('Dirección', p['direccion']),
        _fila('Estado operativo', p['estado_operativo']),
        _fila('Nivel de daño',
            widget.etiquetasSeveridad[p['nivel_dano_preliminar']] ?? p['nivel_dano_preliminar']),
        _fila('Recolector', p['recolector_nombre']),
        _fila('Precisión GNSS', p['precision_gnss_m'] != null ? '${p['precision_gnss_m']} m' : null),
        const SizedBox(height: 12),
        const Text('Evidencia fotográfica', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_cargandoFotos)
          const Center(child: CircularProgressIndicator())
        else if (widget.backendUrl == null)
          const Text('Sin conexión al backend — no se puede traer la foto en este modo demo.',
              style: TextStyle(color: Colors.grey))
        else if (_fotos.isEmpty)
          const Text('Este expediente no tiene foto guardada en el servidor.',
              style: TextStyle(color: Colors.grey))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _fotos.map((f) {
              final url = '${widget.backendUrl}/api/edan/evidencias/${f['id_evidencia']}/archivo';
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url, width: 140, height: 140, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 140, height: 140, color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _fila(String etiqueta, dynamic valor) {
    if (valor == null || valor.toString().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 150, child: Text(etiqueta, style: const TextStyle(color: Colors.grey))),
          Expanded(child: Text(valor.toString())),
        ],
      ),
    );
  }
}
