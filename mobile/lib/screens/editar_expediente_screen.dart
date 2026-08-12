import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../data/colombia_departamentos.dart';
import '../data/inspeccion_ais_opciones.dart';
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
  bool? _requiereSubsidioArrendamiento;

  // Inspección técnica AIS — mismos campos clave que el formulario oficial
  // (ver nuevo_expediente_screen.dart para el formulario completo al
  // crear). Aquí se editan los que más se corrigen después: clasificación,
  // estructura y recomendaciones — no se repite el formulario de 50+
  // campos completo por espacio, pero si hace falta corregir algo de
  // identificación catastral/ubicación de la vía, se puede volver a crear
  // una inspección desde cero.
  String? _idInspeccionAis; // null = todavía no existe, el guardado la crea
  String? _aisSistemaEstructural;
  String? _aisTipoEntrepiso;
  String? _aisAnioConstruccion;
  String? _aisExisteColapso;
  String? _danoMurosFachada;
  String? _danoCubierta;
  String? _danoColumnasMurosPortantes;
  final Set<String> _instalacionesAfectadas = {};
  final _pctDanoGlobalCtrl = TextEditingController();
  final Set<String> _medidasSeguridad = {};
  bool? _edificacionHabitada;
  String? _huboMuertosHeridos;
  final _comentariosAisCtrl = TextEditingController();

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
      final geometrias = datos['geometrias'] as List<dynamic>? ?? [];
      final ais = datos['inspeccion_ais'] as Map<String, dynamic>?;
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
        _requiereSubsidioArrendamiento = o['requiere_subsidio_arrendamiento'];
        if (ais != null) {
          _idInspeccionAis = ais['id_inspeccion'];
          _aisSistemaEstructural = ais['sistema_estructural'];
          _aisTipoEntrepiso = ais['tipo_entrepiso'];
          _aisAnioConstruccion = ais['anio_construccion'];
          _aisExisteColapso = ais['existe_colapso'];
          _danoMurosFachada = ais['dano_muros_fachada'];
          _danoCubierta = ais['dano_cubierta'];
          _danoColumnasMurosPortantes = ais['dano_columnas_muros_portantes'];
          _instalacionesAfectadas.addAll(
              (ais['instalaciones_afectadas'] as List<dynamic>? ?? []).cast<String>());
          _pctDanoGlobalCtrl.text = ais['pct_dano_global']?.toString() ?? '';
          _medidasSeguridad.addAll(
              (ais['medidas_seguridad'] as List<dynamic>? ?? []).cast<String>());
          _edificacionHabitada = ais['edificacion_habitada'];
          _huboMuertosHeridos = ais['hubo_muertos_heridos'];
          _comentariosAisCtrl.text = ais['comentarios'] ?? '';
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
      };
      if (_ubicacion != null) {
        payload['lat'] = _ubicacion!['lat'];
        payload['lon'] = _ubicacion!['lon'];
        payload['precision_gnss_m'] = _ubicacion!['precision_m'];
      }
      await api.put('/api/expedientes/${widget.idObjeto}', payload);

      // Inspección técnica AIS — PUT si ya existía (corrige la misma fila,
      // el backend recalcula clasificación/habitabilidad y vuelve a
      // sincronizar objeto_afectado.nivel_dano_preliminar), o POST si el
      // expediente todavía no tenía ninguna inspección AIS.
      final payloadAis = <String, dynamic>{
        'id_objeto': widget.idObjeto,
        'sistema_estructural': _aisSistemaEstructural,
        'tipo_entrepiso': _aisTipoEntrepiso,
        'anio_construccion': _aisAnioConstruccion,
        'existe_colapso': _aisExisteColapso,
        'dano_muros_fachada': _danoMurosFachada,
        'dano_cubierta': _danoCubierta,
        'dano_columnas_muros_portantes': _danoColumnasMurosPortantes,
        'instalaciones_afectadas': _instalacionesAfectadas.toList(),
        'pct_dano_global': double.tryParse(_pctDanoGlobalCtrl.text.replaceAll(',', '.').trim()),
        'medidas_seguridad': _medidasSeguridad.toList(),
        'edificacion_habitada': _edificacionHabitada,
        'hubo_muertos_heridos': _huboMuertosHeridos,
        'comentarios': _comentariosAisCtrl.text.trim(),
      };
      if (_idInspeccionAis != null) {
        await api.put('/api/inspeccion-ais/$_idInspeccionAis', payloadAis);
      } else {
        await api.post('/api/inspeccion-ais', payloadAis);
      }

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
        const Text('Inspección técnica AIS', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text(
          'Campos más corregidos después de la captura inicial. Para editar '
          'identificación catastral u otros datos del formulario completo, '
          'hazlo desde un nuevo expediente.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        _campoOpcionAis('Sistema estructural', _aisSistemaEstructural, sistemasEstructurales,
            (v) => setState(() => _aisSistemaEstructural = v)),
        _campoOpcionAis('Tipo de entrepiso', _aisTipoEntrepiso, tiposEntrepiso,
            (v) => setState(() => _aisTipoEntrepiso = v)),
        _campoOpcionAis('Año de construcción', _aisAnioConstruccion, aniosConstruccion,
            (v) => setState(() => _aisAnioConstruccion = v)),
        _campoOpcionAis('¿Existe colapso?', _aisExisteColapso, existeColapsoOpciones,
            (v) => setState(() => _aisExisteColapso = v)),
        _campoOpcionAis('Muros de fachada', _danoMurosFachada, gradoDanoAis,
            (v) => setState(() => _danoMurosFachada = v)),
        _campoOpcionAis('Cubierta', _danoCubierta, gradoDanoAis,
            (v) => setState(() => _danoCubierta = v)),
        _campoOpcionAis('Columnas o muros portantes', _danoColumnasMurosPortantes, gradoDanoAis,
            (v) => setState(() => _danoColumnasMurosPortantes = v)),
        _campoMultipleAis('Instalaciones afectadas', instalacionesOpciones, _instalacionesAfectadas),
        _campo(_pctDanoGlobalCtrl, '% de daño global de la edificación',
            teclado: const TextInputType.numberWithOptions(decimal: true)),
        _campoMultipleAis('Medidas de seguridad', medidasSeguridadOpciones, _medidasSeguridad),
        SwitchListTile(
          dense: true,
          title: const Text('Edificación habitada'),
          value: _edificacionHabitada ?? false,
          onChanged: (v) => setState(() => _edificacionHabitada = v),
        ),
        _campoOpcionAis('Hubo muertos o heridos', _huboMuertosHeridos, huboMuertosHeridosOpciones,
            (v) => setState(() => _huboMuertosHeridos = v)),
        TextFormField(
          controller: _comentariosAisCtrl,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Comentarios', border: OutlineInputBorder()),
        ),
        const Divider(height: 24),
        const Text('Necesidades humanitarias', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _campoOpcionAis(String etiqueta, String? valor, List<Map<String, String>> opciones,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: valor,
        decoration: InputDecoration(labelText: etiqueta, isDense: true, border: const OutlineInputBorder()),
        items: opciones
            .map((o) => DropdownMenuItem(value: o['valor'], child: Text(o['etiqueta']!)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _campoMultipleAis(
      String etiqueta, List<Map<String, String>> opciones, Set<String> seleccionadas) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: opciones.map((o) {
              final seleccionado = seleccionadas.contains(o['valor']);
              return FilterChip(
                label: Text(o['etiqueta']!, style: const TextStyle(fontSize: 12)),
                selected: seleccionado,
                onSelected: (v) => setState(() {
                  if (v) {
                    seleccionadas.add(o['valor']!);
                  } else {
                    seleccionadas.remove(o['valor']);
                  }
                }),
              );
            }).toList(),
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
