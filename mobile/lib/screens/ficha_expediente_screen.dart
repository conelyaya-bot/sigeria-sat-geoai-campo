import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
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
        _tarjeta('Daño', [
          _fila('Nivel preliminar', objeto['nivel_dano_preliminar']),
          _fila('Componentes afectados', objeto['resumen_componentes_dano']),
          _fila('Personas afectadas', objeto['personas_afectadas']?.toString()),
          _fila('Subsidio de arrendamiento',
              objeto['requiere_subsidio_arrendamiento'] == null
                  ? null
                  : (objeto['requiere_subsidio_arrendamiento'] == true ? 'Sí' : 'No')),
          _fila('Observaciones técnicas', objeto['observaciones_tecnicas']),
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
