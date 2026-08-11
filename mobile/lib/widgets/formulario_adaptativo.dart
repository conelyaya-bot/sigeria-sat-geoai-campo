import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../data/colombia_departamentos.dart';
import '../screens/mapa_screen.dart';

/// NOTA (2026-08-11): la pantalla de inicio ya no abre este widget de forma
/// aislada por módulo — usa `screens/nuevo_expediente_screen.dart`, que junta
/// los 4 módulos en UN SOLO expediente continuo (el usuario señaló que 4
/// formularios sueltos duplicaban trabajo y no dejaban clara la integración).
/// Este archivo se conserva como motor de formulario dirigido por la Matriz
/// Maestra — reutilizable si más adelante se necesita un formulario 100%
/// data-driven fuera del expediente guiado.
///
/// Motor de formularios adaptativos (sección 7 del documento base): arma el
/// formulario dinámicamente a partir de `assets/matriz_maestra.json`,
/// mostrando solo los campos cuya `condicion_mostrar` se cumple para el
/// fenómeno/objeto/perfil actuales. Mismo principio que la columna
/// `relevant` de XLSForm (ver research/HALLAZGOS.md).
///
/// Campos "vivos" (no solo maqueta): fotografía con cámara real
/// (image_picker), ubicación con GPS real (geolocator) y enlace al mapa
/// real con capas — mismo comportamiento que SW Maps: capturar, ver en el
/// mapa dónde quedó y seguir con el formulario.
class FormularioAdaptativo extends StatefulWidget {
  final String fenomeno;
  final String tipoObjeto;
  final void Function(Map<String, dynamic> respuestas) onGuardar;

  const FormularioAdaptativo({
    super.key,
    required this.fenomeno,
    required this.tipoObjeto,
    required this.onGuardar,
  });

  @override
  State<FormularioAdaptativo> createState() => _FormularioAdaptativoState();
}

class _FormularioAdaptativoState extends State<FormularioAdaptativo> {
  List<dynamic> _campos = [];
  final Map<String, dynamic> _respuestas = {};
  final Map<String, Uint8List> _fotos = {}; // vista previa en memoria por campo
  bool _obteniendoUbicacion = false;

  @override
  void initState() {
    super.initState();
    _cargarMatriz();
  }

  Future<void> _cargarMatriz() async {
    final texto = await rootBundle.loadString('assets/matriz_maestra.json');
    final data = jsonDecode(texto);
    setState(() => _campos = data['campos']);
  }

  /// Evaluación MUY simplificada de la condición para mostrar el campo.
  /// En producción esto debe reemplazarse por un evaluador de expresiones
  /// real (p.ej. mismo subset de expresiones que usa XLSForm/pyxform).
  bool _debeMostrarse(Map<String, dynamic> campo) {
    final condicion = campo['condicion_mostrar'] as String? ?? 'siempre';
    if (condicion == 'siempre') return true;
    if (condicion.contains("fenomeno == '${widget.fenomeno}'")) return true;
    if (condicion.contains("objeto == '${widget.tipoObjeto}'")) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (_campos.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final visibles = _campos.where((c) => _debeMostrarse(c)).toList();

    return ListView(
      children: [
        for (final campo in visibles) ...[
          _campoDinamico(campo),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.save),
          label: const Text('Guardar (captura única)'),
          onPressed: () => widget.onGuardar(_respuestas),
        ),
      ],
    );
  }

  Widget _campoDinamico(Map<String, dynamic> campo) {
    final id = campo['id'] as String;
    final etiqueta = campo['etiqueta'] as String;
    final tipo = campo['tipo_entrada'] as String;

    switch (tipo) {
      case 'select_one':
        final opciones = (campo['opciones'] as List).cast<String>();
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder()),
          items: opciones
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) => setState(() => _respuestas[id] = v),
        );

      case 'select_one_departamento_colombia':
        return DropdownButtonFormField<String>(
          decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder()),
          items: departamentosColombia
              .map((d) => DropdownMenuItem(value: d['nombre'], child: Text(d['nombre']!)))
              .toList(),
          onChanged: (v) => setState(() => _respuestas[id] = v),
        );

      case 'integer':
      case 'decimal':
      case 'decimal_automatico':
        return TextFormField(
          decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder()),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => _respuestas[id] = v,
        );

      case 'image':
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                if (_fotos.containsKey(id))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.memory(_fotos[id]!, width: 48, height: 48, fit: BoxFit.cover),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.image_outlined, size: 40, color: Colors.grey),
                  ),
                Expanded(
                  child: Text(
                    _fotos.containsKey(id) ? '$etiqueta — foto capturada' : etiqueta,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  tooltip: 'Tomar foto',
                  onPressed: () => _tomarFoto(id),
                ),
              ],
            ),
          ),
        );

      case 'geopoint_o_geoshape':
        final coords = _respuestas[id] as Map<String, dynamic>?;
        return Card(
          child: ListTile(
            leading: Icon(_obteniendoUbicacion ? Icons.hourglass_top : Icons.gps_fixed),
            title: Text(etiqueta),
            subtitle: Text(
              coords != null
                  ? 'Lat ${coords['lat'].toStringAsFixed(5)}, Lon ${coords['lon'].toStringAsFixed(5)} '
                    '(±${(coords['precision_m'] as double).toStringAsFixed(1)} m)'
                  : 'Sin capturar — toca el GPS o abre el mapa',
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  icon: const Icon(Icons.gps_fixed),
                  tooltip: 'Capturar con GPS',
                  onPressed: _obteniendoUbicacion ? null : () => _capturarUbicacion(id),
                ),
                IconButton(
                  icon: const Icon(Icons.map),
                  tooltip: 'Ver en el mapa',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MapaScreen()),
                  ),
                ),
              ],
            ),
          ),
        );

      default:
        return TextFormField(
          decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder()),
          onChanged: (v) => _respuestas[id] = v,
        );
    }
  }

  Future<void> _tomarFoto(String id) async {
    try {
      final picker = ImagePicker();
      final archivo = await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (archivo == null) return; // el usuario canceló
      final bytes = await archivo.readAsBytes();
      setState(() {
        _fotos[id] = bytes;
        _respuestas[id] = archivo.path; // ruta local — se sube en la sincronización
      });
    } catch (_) {
      // Sin cámara disponible (p.ej. escritorio sin webcam): usar galería como respaldo,
      // igual que hace SW Maps cuando no hay cámara accesible.
      try {
        final picker = ImagePicker();
        final archivo = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
        if (archivo == null) return;
        final bytes = await archivo.readAsBytes();
        setState(() {
          _fotos[id] = bytes;
          _respuestas[id] = archivo.path;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo tomar la foto: $e')),
          );
        }
      }
    }
  }

  Future<void> _capturarUbicacion(String id) async {
    setState(() => _obteniendoUbicacion = true);
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        throw Exception('Permiso de ubicación denegado');
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _respuestas[id] = {
          'lat': pos.latitude,
          'lon': pos.longitude,
          'precision_m': pos.accuracy,
        };
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener el GPS: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _obteniendoUbicacion = false);
    }
  }
}
