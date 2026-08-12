import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../data/colombia_departamentos.dart';
import '../data/componentes_dano.dart';
import '../services/api_client.dart';
import 'camara_captura_screen.dart';

/// Editar un expediente ya guardado — corrige datos mal digitados, o
/// completa foto/GPS que faltaron en el momento de la captura en campo.
/// No es un Stepper (ya no hace falta guiar paso a paso): un solo
/// formulario con todo visible, prellenado con lo que ya existe.
class EditarExpedienteScreen extends StatefulWidget {
  final String backendUrl;
  final String idObjeto;
  const EditarExpedienteScreen({super.key, required this.backendUrl, required this.idObjeto});

  @override
  State<EditarExpedienteScreen> createState() => _EditarExpedienteScreenState();
}

class _EditarExpedienteScreenState extends State<EditarExpedienteScreen> {
  bool _cargando = true;
  bool _guardando = false;
  bool _obteniendoUbicacion = false;
  String? _error;

  String _tipoObjeto = 'vivienda';
  String _estadoOperativo = 'sin_evaluar';
  String? _departamento;
  final _barrioCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _recolectorNombreCtrl = TextEditingController();
  final _recolectorDocCtrl = TextEditingController();
  final _recolectorCargoCtrl = TextEditingController();
  final _recolectorEntidadCtrl = TextEditingController();
  final _informanteNombreCtrl = TextEditingController();
  final _informanteDocCtrl = TextEditingController();
  final _informanteParentescoCtrl = TextEditingController();
  final _informanteTelCtrl = TextEditingController();
  final _personasAfectadasCtrl = TextEditingController();
  final _observacionesTecnicasCtrl = TextEditingController();
  bool? _requiereSubsidioArrendamiento;
  final Map<String, String> _severidadComponentes = {
    for (final c in componentesDano) c['id']!: 'sin_dano',
  };

  Map<String, dynamic>? _ubicacion; // {lat, lon, precision_m} — solo si se recaptura
  bool _teniaUbicacion = false;
  List<dynamic> _fotosExistentes = [];
  Uint8List? _fotoNueva;
  XFile? _fotoNuevaArchivo;

  static const _opcionesObjeto = [
    'vivienda', 'edificio_publico', 'salud', 'educacion', 'via', 'puente',
    'muelle', 'acueducto', 'energia', 'telecomunicaciones', 'comercio',
    'ambiente', 'animal', 'otro',
  ];
  static const _opcionesEstado = ['sin_evaluar', 'operativo', 'parcial', 'fuera_de_servicio'];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final api = ApiClient(baseUrl: widget.backendUrl);
      final datos = await api.get('/api/expedientes/${widget.idObjeto}/detalle');
      final o = datos['objeto_afectado'] as Map<String, dynamic>;
      final componentes = (datos['componentes'] as List<dynamic>? ?? []);
      final geometrias = datos['geometrias'] as List<dynamic>? ?? [];
      setState(() {
        _tipoObjeto = o['tipo_objeto'] ?? 'vivienda';
        _estadoOperativo = o['estado_operativo'] ?? 'sin_evaluar';
        _departamento = o['departamento'];
        _barrioCtrl.text = o['barrio_vereda'] ?? '';
        _direccionCtrl.text = o['direccion'] ?? '';
        _recolectorNombreCtrl.text = o['recolector_nombre'] ?? '';
        _recolectorDocCtrl.text = o['recolector_documento'] ?? '';
        _recolectorCargoCtrl.text = o['recolector_cargo'] ?? '';
        _recolectorEntidadCtrl.text = o['recolector_entidad'] ?? '';
        _informanteNombreCtrl.text = o['informante_nombre'] ?? '';
        _informanteDocCtrl.text = o['informante_documento'] ?? '';
        _informanteParentescoCtrl.text = o['informante_parentesco'] ?? '';
        _informanteTelCtrl.text = o['informante_telefono'] ?? '';
        _personasAfectadasCtrl.text = o['personas_afectadas']?.toString() ?? '';
        _observacionesTecnicasCtrl.text = o['observaciones_tecnicas'] ?? '';
        _requiereSubsidioArrendamiento = o['requiere_subsidio_arrendamiento'];
        for (final c in componentes) {
          _severidadComponentes[c['componente']] = c['severidad'];
        }
        _fotosExistentes = (datos['evidencias'] as List<dynamic>)
            .where((e) => e['tipo'] == 'foto')
            .toList();
        _teniaUbicacion = geometrias.isNotEmpty;
        _cargando = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _cargando = false;
      });
    }
  }

  String _calcularNivelDano() {
    var peor = 'sin_dano';
    for (final v in _severidadComponentes.values) {
      if (v == 'no_aplica') continue;
      if (ordenSeveridad.indexOf(v) > ordenSeveridad.indexOf(peor)) peor = v;
    }
    return peor;
  }

  String _resumenComponentesDano() {
    final afectados = componentesDano.where(
      (c) => _severidadComponentes[c['id']] != 'sin_dano' &&
          _severidadComponentes[c['id']] != 'no_aplica',
    );
    if (afectados.isEmpty) return 'Sin componentes con daño marcado.';
    return afectados.map((c) {
      final etiqueta = severidadComponente
          .firstWhere((s) => s['valor'] == _severidadComponentes[c['id']])['etiqueta']!;
      return '${c['nombre']}: $etiqueta';
    }).join(' · ');
  }

  Future<void> _capturarUbicacion() async {
    setState(() => _obteniendoUbicacion = true);
    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled().catchError((_) => true);
      if (!servicioActivo) {
        throw Exception('La ubicación está desactivada en el dispositivo o navegador.');
      }
      Position pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
      } catch (_) {
        var permiso = await Geolocator.checkPermission();
        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission();
        }
        if (permiso == LocationPermission.deniedForever || permiso == LocationPermission.denied) {
          throw Exception('Permiso de ubicación denegado. Permítelo en el navegador e intenta de nuevo.');
        }
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
      }
      setState(() {
        _ubicacion = {'lat': pos.latitude, 'lon': pos.longitude, 'precision_m': pos.accuracy};
      });
      _mensaje('Ubicación capturada.');
    } catch (e) {
      _mensaje('No se pudo obtener el GPS: $e');
    } finally {
      if (mounted) setState(() => _obteniendoUbicacion = false);
    }
  }

  Future<void> _tomarFoto() async {
    final resultado = await Navigator.push<(Uint8List, XFile)?>(
      context,
      MaterialPageRoute(builder: (_) => const CamaraCapturaScreen()),
    );
    if (resultado == null) return;
    setState(() {
      _fotoNueva = resultado.$1;
      _fotoNuevaArchivo = resultado.$2;
    });
  }

  Future<void> _eliminarFotoExistente(String idEvidencia) async {
    try {
      final api = ApiClient(baseUrl: widget.backendUrl);
      await api.delete('/api/edan/evidencias/$idEvidencia');
      setState(() {
        _fotosExistentes.removeWhere((e) => e['id_evidencia'] == idEvidencia);
      });
    } catch (e) {
      _mensaje('No se pudo borrar la foto: $e');
    }
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      final api = ApiClient(baseUrl: widget.backendUrl);
      final payload = <String, dynamic>{
        'tipo_objeto': _tipoObjeto,
        'estado_operativo': _estadoOperativo,
        'nivel_dano_preliminar': _calcularNivelDano(),
        'resumen_componentes_dano': _resumenComponentesDano(),
        'departamento': _departamento,
        'barrio_vereda': _barrioCtrl.text.trim(),
        'direccion': _direccionCtrl.text.trim(),
        'recolector_nombre': _recolectorNombreCtrl.text.trim(),
        'recolector_documento': _recolectorDocCtrl.text.trim(),
        'recolector_cargo': _recolectorCargoCtrl.text.trim(),
        'recolector_entidad': _recolectorEntidadCtrl.text.trim(),
        'informante_nombre': _informanteNombreCtrl.text.trim(),
        'informante_documento': _informanteDocCtrl.text.trim(),
        'informante_parentesco': _informanteParentescoCtrl.text.trim(),
        'informante_telefono': _informanteTelCtrl.text.trim(),
        'requiere_subsidio_arrendamiento': _requiereSubsidioArrendamiento,
        'personas_afectadas': int.tryParse(_personasAfectadasCtrl.text.trim()),
        'observaciones_tecnicas':
            _observacionesTecnicasCtrl.text.trim().isEmpty ? null : _observacionesTecnicasCtrl.text.trim(),
        'componentes': [
          for (final c in componentesDano)
            {'componente': c['id'], 'severidad': _severidadComponentes[c['id']]},
        ],
      };
      if (_ubicacion != null) {
        payload['lat'] = _ubicacion!['lat'];
        payload['lon'] = _ubicacion!['lon'];
        payload['precision_gnss_m'] = _ubicacion!['precision_m'];
      }
      await api.put('/api/expedientes/${widget.idObjeto}', payload);

      if (_fotoNuevaArchivo != null && _fotoNueva != null) {
        await api.post('/api/edan/evidencias', {
          'id_objeto': widget.idObjeto,
          'tipo': 'foto',
          'url_almacenamiento': _fotoNuevaArchivo!.name,
          'usuario_id': _recolectorNombreCtrl.text.trim(),
          'contenido_base64': base64Encode(_fotoNueva!),
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expediente actualizado.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      _mensaje('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editar ${widget.idObjeto}', style: const TextStyle(fontSize: 14))),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')))
              : _formulario(),
      bottomNavigationBar: _cargando || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  icon: const Icon(Icons.save),
                  label: Text(_guardando ? 'Guardando…' : 'Guardar cambios'),
                  onPressed: _guardando ? null : _guardar,
                ),
              ),
            ),
    );
  }

  Widget _formulario() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _tipoObjeto,
          decoration: const InputDecoration(labelText: 'Tipo de objeto', border: OutlineInputBorder()),
          items: _opcionesObjeto.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _tipoObjeto = v!),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _estadoOperativo,
          decoration: const InputDecoration(labelText: 'Estado operativo', border: OutlineInputBorder()),
          items: _opcionesEstado.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _estadoOperativo = v!),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _departamento,
          decoration: const InputDecoration(labelText: 'Departamento', border: OutlineInputBorder()),
          items: departamentosColombia
              .map((d) => DropdownMenuItem(value: d['nombre'], child: Text(d['nombre']!)))
              .toList(),
          onChanged: (v) => setState(() => _departamento = v),
        ),
        const SizedBox(height: 8),
        _campo(_barrioCtrl, 'Barrio, corregimiento o vereda'),
        _campo(_direccionCtrl, 'Dirección'),
        const Divider(height: 24),
        const Text('Responsable de la recolección', style: TextStyle(fontWeight: FontWeight.bold)),
        _campo(_recolectorNombreCtrl, 'Nombre'),
        _campo(_recolectorDocCtrl, 'Documento'),
        _campo(_recolectorCargoCtrl, 'Cargo'),
        _campo(_recolectorEntidadCtrl, 'Entidad'),
        const Divider(height: 24),
        const Text('Informante en la vivienda', style: TextStyle(fontWeight: FontWeight.bold)),
        _campo(_informanteNombreCtrl, 'Nombre'),
        _campo(_informanteDocCtrl, 'Documento'),
        _campo(_informanteParentescoCtrl, 'Parentesco'),
        _campo(_informanteTelCtrl, 'Teléfono'),
        const Divider(height: 24),
        const Text('Lista de chequeo de daños', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final c in componentesDano) _filaComponente(c),
        const SizedBox(height: 8),
        _campo(_personasAfectadasCtrl, 'Personas afectadas', teclado: TextInputType.number),
        const Text('¿Requiere subsidio de arrendamiento?', style: TextStyle(fontWeight: FontWeight.bold)),
        RadioListTile<bool?>(
          dense: true,
          title: const Text('Sí'),
          value: true,
          groupValue: _requiereSubsidioArrendamiento,
          onChanged: (v) => setState(() => _requiereSubsidioArrendamiento = v),
        ),
        RadioListTile<bool?>(
          dense: true,
          title: const Text('No'),
          value: false,
          groupValue: _requiereSubsidioArrendamiento,
          onChanged: (v) => setState(() => _requiereSubsidioArrendamiento = v),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _observacionesTecnicasCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
              labelText: 'Observaciones técnicas', border: OutlineInputBorder()),
        ),
        const Divider(height: 24),
        const Text('Ubicación GPS', style: TextStyle(fontWeight: FontWeight.bold)),
        Card(
          child: ListTile(
            leading: Icon(_obteniendoUbicacion ? Icons.hourglass_top : Icons.gps_fixed),
            title: Text(
              _ubicacion != null
                  ? 'Nueva: Lat ${_ubicacion!['lat'].toStringAsFixed(5)}, Lon ${_ubicacion!['lon'].toStringAsFixed(5)}'
                  : (_teniaUbicacion ? 'Ya tiene ubicación guardada' : 'Sin ubicación guardada'),
            ),
            trailing: FilledButton.icon(
              icon: const Icon(Icons.gps_fixed),
              label: Text(_teniaUbicacion ? 'Recapturar' : 'Capturar GPS'),
              onPressed: _obteniendoUbicacion ? null : _capturarUbicacion,
            ),
          ),
        ),
        const Divider(height: 24),
        const Text('Fotos', style: TextStyle(fontWeight: FontWeight.bold)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in _fotosExistentes)
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '${widget.backendUrl}/api/edan/evidencias/${e['id_evidencia']}/archivo',
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: -8,
                    right: -8,
                    child: IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () => _eliminarFotoExistente(e['id_evidencia'] as String),
                    ),
                  ),
                ],
              ),
            if (_fotoNueva != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_fotoNueva!, width: 90, height: 90, fit: BoxFit.cover),
              ),
            InkWell(
              onTap: _tomarFoto,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_a_photo),
              ),
            ),
          ],
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _filaComponente(Map<String, String> componente) {
    final id = componente['id']!;
    final valor = _severidadComponentes[id]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(componente['nombre']!)),
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: valor,
              decoration: const InputDecoration(isDense: true),
              items: severidadComponente
                  .map((s) => DropdownMenuItem(value: s['valor'], child: Text(s['etiqueta']!)))
                  .toList(),
              onChanged: (v) => setState(() => _severidadComponentes[id] = v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _campo(TextEditingController c, String etiqueta, {TextInputType? teclado}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: c,
        keyboardType: teclado,
        decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }
}
