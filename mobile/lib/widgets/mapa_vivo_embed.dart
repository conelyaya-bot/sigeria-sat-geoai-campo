import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import '../screens/mapa_screen.dart' show FichaObjeto, ControlZoomMapa;

/// Mapa en vivo embebido en la pantalla principal — a pedido del usuario:
/// "hacer visible en ese espacio el mapa de llenado en tiempo real donde se
/// vaya viendo la malla de puntos". Antes esa zona de Inicio solo tenía las
/// 4 tarjetas de módulos (que ahora también están en el menú lateral); este
/// widget muestra el mapa REAL con los expedientes ya guardados, tocable
/// igual que en la pantalla de mapa completo (abre la misma ficha con foto).
class MapaVivoEmbed extends StatefulWidget {
  final String backendUrl;
  final double height;
  // Filtro opcional por zona — a pedido del usuario, para el visor de
  // Estadísticas: elegir departamento/municipio y ver solo la malla de
  // puntos de esa zona, no el país entero mezclado.
  final String? departamento;
  final String? municipioDivipola;
  const MapaVivoEmbed({
    super.key,
    required this.backendUrl,
    this.height = 260,
    this.departamento,
    this.municipioDivipola,
  });

  @override
  State<MapaVivoEmbed> createState() => _MapaVivoEmbedState();
}

class _MapaVivoEmbedState extends State<MapaVivoEmbed> {
  MapLibreMapController? _controller;
  List<dynamic> _features = [];
  String? _estado;
  bool _capaCreada = false;
  // "Mapa en vivo" de verdad: se refresca solo, sin que la persona tenga que
  // salir y volver a entrar — así un punto georreferenciado por cualquiera
  // (incluida esta misma sesión al capturar GPS) aparece en la malla sin
  // acción manual. A pedido explícito del usuario: "debe de una vez
  // aparecer georreferenciados los puntos".
  Timer? _timerAutoRefresco;

  @override
  void initState() {
    super.initState();
    _timerAutoRefresco = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _cargar(silencioso: true),
    );
  }

  @override
  void dispose() {
    _timerAutoRefresco?.cancel();
    _controller?.onFeatureTapped.clear();
    super.dispose();
  }

  @override
  void didUpdateWidget(MapaVivoEmbed old) {
    super.didUpdateWidget(old);
    if (old.departamento != widget.departamento ||
        old.municipioDivipola != widget.municipioDivipola) {
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            MapLibreMap(
              styleString: 'styles/satelital.json',
              initialCameraPosition: const CameraPosition(
                target: LatLng(5.6947, -76.6413), // Quibdó, Chocó
                zoom: 7,
              ),
              onMapCreated: (c) {
                _controller = c;
                c.onFeatureTapped.add(_alTocarFeature);
              },
              onStyleLoadedCallback: _cargar,
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: Chip(
                label: Text(_estado ?? '${_features.length} punto(s) en vivo'),
                backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                labelStyle: const TextStyle(fontSize: 11),
                visualDensity: VisualDensity.compact,
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: ControlZoomMapa(onAcercar: _acercar, onAlejar: _alejar),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _acercar() =>
      _controller?.animateCamera(CameraUpdate.zoomIn()) ?? Future.value();
  Future<void> _alejar() =>
      _controller?.animateCamera(CameraUpdate.zoomOut()) ?? Future.value();

  Uri _urlGeojson() {
    final params = <String, String>{};
    if (widget.departamento != null) params['departamento'] = widget.departamento!;
    if (widget.municipioDivipola != null) params['municipio_divipola'] = widget.municipioDivipola!;
    return Uri.parse('${widget.backendUrl}/api/gis/geojson_general')
        .replace(queryParameters: params.isEmpty ? null : params);
  }

  /// `silencioso: true` en los refrescos automáticos de fondo — no muestra
  /// "Cargando…" cada 12 s (se vería como parpadeo constante) ni reemplaza un
  /// mensaje de error visible por uno nuevo si el punto no cambió; solo
  /// actualiza el conteo/malla cuando sí trae datos frescos.
  Future<void> _cargar({bool silencioso = false}) async {
    final c = _controller;
    if (c == null) return;
    if (!silencioso) setState(() => _estado = 'Cargando…');
    try {
      final resp = await http.get(_urlGeojson()).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) throw Exception('Backend respondió ${resp.statusCode}');
      final geojson = jsonDecode(resp.body) as Map<String, dynamic>;
      _features = geojson['features'] as List<dynamic>? ?? [];

      if (_capaCreada) {
        // Ya existe la capa (filtro cambiado o refresco automático) — solo
        // actualizar los datos, sin recrear la capa (evita parpadeo).
        await c.setGeoJsonSource('objetos_afectados', geojson);
      } else {
        await c.addGeoJsonSource('objetos_afectados', geojson);
        _capaCreada = true;
        await c.addCircleLayer(
          'objetos_afectados',
          'objetos_afectados_circulos',
          CircleLayerProperties(
            circleRadius: 7,
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
              '#8a8f98',
            ],
          ),
        );
      }
      if (mounted) setState(() => _estado = null);
    } catch (e) {
      // En un refresco silencioso, no tapar el mapa con un error si ya había
      // datos cargados antes — solo se reintenta en el siguiente ciclo.
      if (mounted && !(silencioso && _features.isNotEmpty)) {
        setState(() => _estado = 'Sin conexión al backend');
      }
    }
  }

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
      final dLat = lat - coordinates.latitude, dLon = lon - coordinates.longitude;
      final d = dLat * dLat + dLon * dLon;
      if (d < mejorDistancia) {
        mejorDistancia = d;
        mejor = f;
      }
    }
    if (mejor == null) return;
    final p = (mejor as Map<String, dynamic>)['properties'] as Map<String, dynamic>;
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
          etiquetasSeveridad: const {
            'sin_dano': 'Sin daño', 'leve': 'Leve', 'moderado': 'Parcial (no estructural)',
            'severo': 'Estructural', 'colapso': 'Colapso / destrucción total', null: 'Sin evaluar',
          },
          scrollController: scrollController,
        ),
      ),
    );
  }
}
