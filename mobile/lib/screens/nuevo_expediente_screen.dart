import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../data/colombia_departamentos.dart';
import '../data/colombia_municipios.dart';
import '../data/componentes_dano.dart';
import '../data/departamentos_capitales.dart';
import '../services/api_client.dart';
import 'camara_captura_screen.dart';
import 'mapa_screen.dart';

/// Expediente único — reemplaza los 4 módulos como pantallas sueltas.
///
/// Antes: "Evento y objetos", "EDAN", "GIS" y "Medición" eran 4 formularios
/// desconectados (cada uno abría su propio `FormularioAdaptativo` sin
/// compartir datos). El usuario señaló correctamente que eso duplica trabajo
/// y no deja claro que es UN SOLO expediente por vivienda/familia.
///
/// Ahora: un solo `Stepper` con 4 pasos que llenan el MISMO mapa de
/// respuestas y se guardan como UN SOLO expediente al final — el objeto
/// afectado (código único tipo `SIGERIA-CHO-27001-SIS-2026-000001`) se crea
/// una sola vez, y la geometría, las necesidades, las mediciones y la foto
/// quedan todas vinculadas a ESE MISMO código. Captura única de verdad.
class NuevoExpedienteScreen extends StatefulWidget {
  final String backendUrl;
  const NuevoExpedienteScreen({super.key, required this.backendUrl});

  @override
  State<NuevoExpedienteScreen> createState() => _NuevoExpedienteScreenState();
}

class _TipoMedicion {
  String tipo = 'distancia';
  final valorCtrl = TextEditingController();
  String unidad = 'm';
  Uint8List? foto;
  XFile? fotoArchivo;
}

class _NuevoExpedienteScreenState extends State<NuevoExpedienteScreen> {
  int _paso = 0;
  bool _guardando = false;
  bool _obteniendoUbicacion = false;
  Uint8List? _foto;
  XFile? _fotoArchivo;
  Map<String, dynamic>? _ubicacion; // {lat, lon, precision_m}
  final List<_TipoMedicion> _mediciones = [];
  final Set<String> _necesidades = {};

  // --- Paso 1: evento, ubicación, objeto, responsables ---
  String _fenomeno = 'sismo';
  String _departamento = departamentosColombia.first['nombre']!;
  MunicipioColombia? _municipioSeleccionado; // trae DIVIPOLA + coordenadas reales solo
  final _barrioCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  String _tipoObjeto = 'vivienda';
  String _estadoOperativo = 'sin_evaluar';
  final _recolectorNombreCtrl = TextEditingController();
  final _recolectorDocCtrl = TextEditingController();
  final _recolectorCargoCtrl = TextEditingController();
  final _recolectorEntidadCtrl = TextEditingController();
  final _informanteNombreCtrl = TextEditingController();
  final _informanteDocCtrl = TextEditingController();
  final _informanteParentescoCtrl = TextEditingController();
  final _informanteTelCtrl = TextEditingController();

  // --- Paso 2: EDAN — lista de chequeo por componente, no texto libre ---
  // id de componente -> severidad ('sin_dano' si no se ha tocado)
  final Map<String, String> _severidadComponentes = {
    for (final c in componentesDano) c['id']!: 'sin_dano',
  };
  bool? _requiereSubsidioArrendamiento;
  final _personasAfectadasCtrl = TextEditingController();
  // Espacio libre opcional — si quien levanta el dato SÍ es ingeniero/a,
  // puede detallar aquí lo evidenciado técnicamente. No reemplaza la lista
  // de chequeo (que sigue siendo obligatoria y la que usa cualquier
  // persona); es un anexo adicional, a pedido del usuario.
  final _observacionesTecnicasCtrl = TextEditingController();

  // --- Paso 3: mini-mapa de georreferenciación ---
  MapLibreMapController? _miniMapController;

  static const _opcionesFenomeno = [
    'sismo', 'inundacion', 'deslizamiento', 'vendaval', 'incendio',
    'erosion_socavacion', 'creciente_subita', 'otro',
  ];
  static const _opcionesObjeto = [
    'vivienda', 'edificio_publico', 'salud', 'educacion', 'via', 'puente',
    'muelle', 'acueducto', 'energia', 'telecomunicaciones', 'comercio',
    'ambiente', 'animal', 'otro',
  ];
  static const _opcionesEstado = ['sin_evaluar', 'operativo', 'parcial', 'fuera_de_servicio'];
  static const _opcionesNecesidad = ['agua', 'alimento', 'refugio', 'salud', 'otro'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo expediente')),
      body: Stepper(
        currentStep: _paso,
        onStepContinue: () {
          if (_paso < 3) {
            setState(() => _paso++);
          } else {
            _guardarExpediente();
          }
        },
        onStepCancel: _paso == 0 ? null : () => setState(() => _paso--),
        onStepTapped: (i) => setState(() => _paso = i),
        controlsBuilder: (context, details) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              FilledButton(
                onPressed: _guardando ? null : details.onStepContinue,
                child: Text(_paso == 3
                    ? (_guardando ? 'Guardando…' : 'Guardar expediente completo')
                    : 'Siguiente'),
              ),
              if (_paso > 0) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: details.onStepCancel, child: const Text('Atrás')),
              ],
            ],
          ),
        ),
        steps: [
          Step(
            title: const Text('1. Evento y objeto'),
            isActive: _paso >= 0,
            state: _paso > 0 ? StepState.complete : StepState.indexed,
            content: _pasoEventoObjeto(),
          ),
          Step(
            title: const Text('2. EDAN básico'),
            isActive: _paso >= 1,
            state: _paso > 1 ? StepState.complete : StepState.indexed,
            content: _pasoEdan(),
          ),
          Step(
            title: const Text('3. GIS — ubicación real'),
            isActive: _paso >= 2,
            state: _paso > 2 ? StepState.complete : StepState.indexed,
            content: _pasoGis(),
          ),
          Step(
            title: const Text('4. Medición móvil'),
            isActive: _paso >= 3,
            content: _pasoMedicion(),
          ),
        ],
      ),
    );
  }

  Widget _pasoEventoObjeto() {
    final codigoDepto = _codigoDepartamento(_departamento);
    final municipios = municipiosPorDepartamento[codigoDepto] ?? const <MunicipioColombia>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6), // evita que el label del primer campo se corte arriba
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Fenómeno', border: OutlineInputBorder()),
          initialValue: _fenomeno,
          items: _opcionesFenomeno.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _fenomeno = v!),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Departamento', border: OutlineInputBorder()),
          initialValue: _departamento,
          items: departamentosColombia
              .map((d) => DropdownMenuItem(value: d['nombre'], child: Text(d['nombre']!)))
              .toList(),
          onChanged: (v) => setState(() {
            _departamento = v!;
            _municipioSeleccionado = null; // cambia la lista de municipios, hay que reelegir
          }),
        ),
        const SizedBox(height: 8),
        // Municipio REAL de Colombia (1.122, catálogo oficial DANE/DIVIPOLA),
        // filtrado por el departamento ya elegido — nada de escribirlo a mano.
        DropdownButtonFormField<MunicipioColombia>(
          isExpanded: true,
          initialValue: _municipioSeleccionado,
          decoration: const InputDecoration(labelText: 'Municipio', border: OutlineInputBorder()),
          items: municipios
              .map((m) => DropdownMenuItem(value: m, child: Text(m.nombre)))
              .toList(),
          onChanged: (v) => setState(() => _municipioSeleccionado = v),
          validator: (v) => v == null ? 'Elige el municipio' : null,
        ),
        if (_municipioSeleccionado != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Código DIVIPOLA: ${_municipioSeleccionado!.divipola} (generado automáticamente)',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _barrioCtrl,
          decoration: const InputDecoration(
              labelText: 'Barrio, corregimiento o vereda', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _direccionCtrl,
          decoration: const InputDecoration(labelText: 'Dirección', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration:
              const InputDecoration(labelText: 'Tipo de objeto afectado', border: OutlineInputBorder()),
          initialValue: _tipoObjeto,
          items: _opcionesObjeto.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _tipoObjeto = v!),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Estado operativo', border: OutlineInputBorder()),
          initialValue: _estadoOperativo,
          items: _opcionesEstado.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) => setState(() => _estadoOperativo = v!),
        ),
        const SizedBox(height: 8),
        _campoFoto(),
        const Divider(height: 32),
        const Text('Responsable de la recolección', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        _campoTexto(_recolectorNombreCtrl, 'Nombre del recolector'),
        _campoTexto(_recolectorDocCtrl, 'Documento'),
        _campoTexto(_recolectorCargoCtrl, 'Cargo (brigadista, ingeniero, etc.)'),
        _campoTexto(_recolectorEntidadCtrl, 'Entidad'),
        const Divider(height: 32),
        const Text('Informante en la vivienda (beneficiario)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        _campoTexto(_informanteNombreCtrl, 'Nombre de quien entrega la información'),
        _campoTexto(_informanteDocCtrl, 'Documento'),
        _campoTexto(_informanteParentescoCtrl, 'Parentesco / relación con el hogar'),
        _campoTexto(_informanteTelCtrl, 'Teléfono de contacto'),
      ],
    );
  }

  Widget _pasoEdan() {
    final peor = _calcularNivelDano();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Marca qué componente ves afectado y qué tan grave se ve — no hace '
          'falta ser ingeniero/a, solo observar. El nivel de daño general se '
          'calcula solo, tomando el componente más grave.',
        ),
        const SizedBox(height: 12),
        for (final c in componentesDano) _filaComponente(c),
        const SizedBox(height: 12),
        Card(
          color: _colorSeveridad(peor).withValues(alpha: 0.15),
          child: ListTile(
            leading: Icon(Icons.rule, color: _colorSeveridad(peor)),
            title: const Text('Nivel de daño preliminar (calculado)'),
            subtitle: Text(
              severidadComponente.firstWhere((s) => s['valor'] == peor)['etiqueta']!,
              style: TextStyle(color: _colorSeveridad(peor), fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Necesidad urgente', style: TextStyle(fontWeight: FontWeight.bold)),
        for (final n in _opcionesNecesidad)
          CheckboxListTile(
            dense: true,
            title: Text(n),
            value: _necesidades.contains(n),
            onChanged: (v) => setState(() {
              if (v == true) {
                _necesidades.add(n);
              } else {
                _necesidades.remove(n);
              }
            }),
          ),
        const SizedBox(height: 8),
        _campoTexto(_personasAfectadasCtrl, 'Personas afectadas en el hogar',
            teclado: TextInputType.number),
        const SizedBox(height: 8),
        const Text('¿Requiere subsidio de arrendamiento?',
            style: TextStyle(fontWeight: FontWeight.bold)),
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
        const Divider(height: 32),
        const Text('Observaciones técnicas (opcional)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'Espacio adicional solo si quien evalúa es ingeniero/a y quiere '
          'detallar por escrito lo evidenciado en la vivienda. No reemplaza '
          'la lista de chequeo de arriba, que sigue siendo obligatoria.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _observacionesTecnicasCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Ej.: fisuras diagonales en muro sur, ancho aprox. 3 mm, '
                'compatibles con esfuerzo cortante…',
            border: OutlineInputBorder(),
          ),
        ),
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

  /// Toma el componente más grave marcado — así el nivel de daño preliminar
  /// no se vuelve a preguntar aparte, sale solo de la lista de chequeo.
  /// `no_aplica` (NP) se ignora a propósito: no es un nivel de gravedad, es
  /// que el componente no existe en esta vivienda, así que no debe pesar en
  /// el cálculo del peor caso.
  String _calcularNivelDano() {
    var peor = 'sin_dano';
    for (final v in _severidadComponentes.values) {
      if (v == 'no_aplica') continue;
      if (ordenSeveridad.indexOf(v) > ordenSeveridad.indexOf(peor)) peor = v;
    }
    return peor;
  }

  /// Texto legible generado automáticamente a partir de la lista de chequeo
  /// (reemplaza la descripción libre que antes había que redactar a mano).
  /// Excluye tanto "sin daño" como "no aplica" — ninguno de los dos es un
  /// componente afectado.
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

  Color _colorSeveridad(String valor) {
    switch (valor) {
      case 'sin_dano':
        return const Color(0xFF2E8B57);
      case 'leve':
        return const Color(0xFFC9B400);
      case 'moderado':
        return const Color(0xFFE08A1E);
      case 'severo':
        return const Color(0xFFD1392B);
      case 'colapso':
        return const Color(0xFF6B0F1A);
      default:
        return Colors.grey;
    }
  }

  /// Código DANE del departamento elegido — mismo campo `codigo` de
  /// `colombia_departamentos.dart`, usado para filtrar `municipiosPorDepartamento`.
  String? _codigoDepartamento(String nombreDepartamento) {
    for (final d in departamentosColombia) {
      if (d['nombre'] == nombreDepartamento) return d['codigo'];
    }
    return null;
  }

  Widget _pasoGis() {
    // Preferimos la coordenada exacta del municipio elegido (dato real DANE);
    // si aún no se eligió municipio, centramos en la capital del departamento.
    final referencia = _municipioSeleccionado != null
        ? [_municipioSeleccionado!.lat, _municipioSeleccionado!.lon]
        : (capitalesPorDepartamento[_departamento] ?? [5.6947, -76.6413]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _municipioSeleccionado != null
              ? 'El mapa ya está centrado en ${_municipioSeleccionado!.nombre} '
                '(coordenada real DANE). Toca "Capturar GPS" para marcar la ubicación '
                'exacta de la vivienda.'
              : 'El mapa está centrado en el departamento elegido en el paso 1 — '
                'vuelve al paso 1 y elige el municipio para una referencia más precisa. '
                'Toca "Capturar GPS" para marcar la ubicación real de la vivienda.',
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 220,
            child: MapLibreMap(
              styleString: 'styles/satelital.json',
              initialCameraPosition: CameraPosition(
                target: LatLng(referencia[0], referencia[1]),
                zoom: _ubicacion != null ? 15 : 7,
              ),
              onMapCreated: (c) => _miniMapController = c,
              onStyleLoadedCallback: () {
                if (_ubicacion != null) _dibujarPuntoMiniMapa();
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: Icon(_obteniendoUbicacion ? Icons.hourglass_top : Icons.gps_fixed),
            title: Text(
              _ubicacion != null
                  ? 'Lat ${_ubicacion!['lat'].toStringAsFixed(5)}, '
                    'Lon ${_ubicacion!['lon'].toStringAsFixed(5)} '
                    '(±${(_ubicacion!['precision_m'] as double).toStringAsFixed(1)} m)'
                  : 'Sin capturar — el mapa muestra el departamento como referencia',
            ),
            trailing: FilledButton.icon(
              icon: const Icon(Icons.gps_fixed),
              label: const Text('Capturar GPS'),
              onPressed: _obteniendoUbicacion ? null : _capturarUbicacion,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _dibujarPuntoMiniMapa() async {
    final c = _miniMapController;
    if (c == null || _ubicacion == null) return;
    final punto = LatLng(_ubicacion!['lat'], _ubicacion!['lon']);
    try {
      await c.clearCircles();
      await c.addCircle(CircleOptions(
        geometry: punto,
        circleRadius: 9,
        circleColor: '#e08a1e',
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
    } catch (_) {
      // Si el círculo falla por cualquier razón, al menos centramos el mapa.
    }
    await c.animateCamera(CameraUpdate.newLatLngZoom(punto, 16));
  }

  Widget _pasoMedicion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _mediciones.length; i++) _filaMedicion(i),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Agregar medición'),
          onPressed: () => setState(() => _mediciones.add(_TipoMedicion())),
        ),
      ],
    );
  }

  Widget _filaMedicion(int i) {
    final m = _mediciones[i];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: m.tipo,
                    decoration: const InputDecoration(labelText: 'Tipo', isDense: true),
                    items: const ['distancia', 'area', 'pendiente', 'altura', 'grieta']
                        .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: (v) => setState(() => m.tipo = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: m.valorCtrl,
                    decoration: InputDecoration(
                        labelText: 'Valor (${m.unidad})', isDense: true),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => setState(() => _mediciones.removeAt(i)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (m.foto != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.memory(m.foto!, width: 40, height: 40, fit: BoxFit.cover),
                  )
                else
                  const Icon(Icons.image_outlined, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    m.foto != null ? 'Foto calibrada tomada' : 'Foto calibrada (opcional)',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.camera_alt, size: 18),
                  label: const Text('Foto'),
                  onPressed: () => _tomarFotoMedicion(i),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _tomarFotoMedicion(int i) async {
    final resultado = await _capturarFoto();
    if (resultado == null) return;
    setState(() {
      _mediciones[i].foto = resultado.$1;
      _mediciones[i].fotoArchivo = resultado.$2;
    });
  }

  Widget _campoTexto(TextEditingController c, String etiqueta, {TextInputType? teclado}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: c,
        keyboardType: teclado,
        decoration: InputDecoration(labelText: etiqueta, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }

  Widget _campoFoto() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (_foto != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(_foto!, width: 48, height: 48, fit: BoxFit.cover),
              )
            else
              const Icon(Icons.image_outlined, size: 40, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_foto != null
                  ? 'Foto de la vivienda tomada — se guardará con el código del expediente'
                  : 'Fotografía general de la vivienda/objeto'),
            ),
            IconButton(
              icon: const Icon(Icons.camera_alt),
              tooltip: 'Tomar foto con la cámara',
              onPressed: _tomarFoto,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _tomarFoto() async {
    final resultado = await _capturarFoto();
    if (resultado == null) return;
    setState(() {
      _foto = resultado.$1;
      _fotoArchivo = resultado.$2;
    });
  }

  /// Cámara real, blindada: intenta la cámara del dispositivo primero
  /// (`ImageSource.camera`, así funciona igual que en SW Maps: toma la foto
  /// de la vivienda en el momento). Si el dispositivo no tiene cámara
  /// accesible (p.ej. algunos navegadores de escritorio sin webcam, o el
  /// usuario la niega), cae a la galería en vez de dejar el botón sin
  /// respuesta — y si ambas fallan, avisa con un mensaje claro en vez de
  /// quedarse en silencio.
  Future<(Uint8List, XFile)?> _capturarFoto() async {
    // Cámara real en vivo (paquete `camera`, con getUserMedia en navegador).
    // Antes se usaba solo `image_picker` con ImageSource.camera, que en
    // navegadores de escritorio no abre cámara — solo el buscador de
    // archivos, porque el atributo HTML "capture" solo lo respetan
    // navegadores móviles. La pantalla de cámara ya trae su propio respaldo
    // a galería si no hay cámara disponible.
    final resultado = await Navigator.push<(Uint8List, XFile)?>(
      context,
      MaterialPageRoute(builder: (_) => const CamaraCapturaScreen()),
    );
    return resultado;
  }

  Future<void> _capturarUbicacion() async {
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
        _ubicacion = {'lat': pos.latitude, 'lon': pos.longitude, 'precision_m': pos.accuracy};
      });
      await _dibujarPuntoMiniMapa();
    } catch (e) {
      _mensaje('No se pudo obtener el GPS: $e');
    } finally {
      if (mounted) setState(() => _obteniendoUbicacion = false);
    }
  }

  Future<void> _guardarExpediente() async {
    if (_municipioSeleccionado == null) {
      _mensaje('Falta elegir el municipio (paso 1)');
      setState(() => _paso = 0);
      return;
    }
    setState(() => _guardando = true);
    final api = ApiClient(baseUrl: widget.backendUrl);
    try {
      // 1) Evento — encabezado del expediente. El código DIVIPOLA sale solo
      // del municipio elegido — nadie tiene que saberse ni escribir el código.
      final evento = await api.post('/api/eventos', {
        'fenomeno': _fenomeno,
        'fecha_evento': DateTime.now().toIso8601String(),
        'municipio_divipola': _municipioSeleccionado!.divipola,
        'descripcion': 'Municipio: ${_municipioSeleccionado!.nombre}',
        'creado_por': _recolectorNombreCtrl.text.trim(),
      });
      final idEvento = evento['id_evento'] as String;

      // 2) Objeto afectado — UN SOLO registro con ubicación + responsables.
      // El nivel de daño sale de la lista de chequeo por componente, no de
      // una pregunta aparte (evita que alguien sin formación técnica tenga
      // que calificar el daño "a ojo" sin apoyo).
      final objeto = await api.post('/api/eventos/objetos', {
        'id_evento': idEvento,
        'tipo_objeto': _tipoObjeto,
        'estado_operativo': _estadoOperativo,
        'nivel_dano_preliminar': _calcularNivelDano(),
        'resumen_componentes_dano': _resumenComponentesDano(),
        'observaciones_tecnicas': _observacionesTecnicasCtrl.text.trim().isEmpty
            ? null
            : _observacionesTecnicasCtrl.text.trim(),
        'personas_afectadas': int.tryParse(_personasAfectadasCtrl.text.trim()),
        // Detalle fila por fila — antes solo se mandaba el resumen en texto;
        // esto es lo que permite calcular de verdad "qué componentes se
        // dañan más" en la pantalla de Estadísticas.
        'componentes': [
          for (final c in componentesDano)
            {'componente': c['id'], 'severidad': _severidadComponentes[c['id']]},
        ],
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
        'creado_por': _recolectorNombreCtrl.text.trim(),
      });
      final idObjeto = objeto['id_objeto'] as String;

      // 3) Geometría — MISMO id_objeto
      if (_ubicacion != null) {
        await api.post('/api/gis/geometrias', {
          'id_objeto': idObjeto,
          'geom_tipo': 'Point',
          'geom_geojson': {
            'type': 'Point',
            'coordinates': [_ubicacion!['lon'], _ubicacion!['lat']],
          },
          'precision_gnss_m': _ubicacion!['precision_m'],
          'fuente_posicion': 'gnss_interno',
        });
      }

      // 4) Necesidades — MISMO id_objeto
      for (final n in _necesidades) {
        await api.post('/api/edan/necesidades', {'id_objeto': idObjeto, 'tipo': n});
      }

      // 5) Mediciones — MISMO id_objeto (con su foto calibrada si se tomó)
      for (final m in _mediciones) {
        final valor = double.tryParse(m.valorCtrl.text.trim());
        if (valor == null) continue;
        await api.post('/api/mediciones', {
          'id_objeto': idObjeto,
          'tipo': m.tipo,
          'valor': valor,
          'unidad': m.unidad,
          'metodo': 'sensor_telefono',
          'precision_categoria': 'orientativa',
        });
        if (m.fotoArchivo != null && m.foto != null) {
          await api.post('/api/edan/evidencias', {
            'id_objeto': idObjeto,
            'tipo': 'foto',
            'url_almacenamiento': 'medicion_${m.tipo}_${m.fotoArchivo!.name}',
            'usuario_id': _recolectorNombreCtrl.text.trim(),
            'contenido_base64': base64Encode(m.foto!),
          });
        }
      }

      // 6) Foto general — MISMO id_objeto (queda archivada con el código de
      // la vivienda; se sube el contenido real, no solo el nombre, para que
      // el reporte PDF pueda mostrarla de verdad).
      if (_fotoArchivo != null && _foto != null) {
        await api.post('/api/edan/evidencias', {
          'id_objeto': idObjeto,
          'tipo': 'foto',
          'url_almacenamiento': _fotoArchivo!.name,
          'usuario_id': _recolectorNombreCtrl.text.trim(),
          'contenido_base64': base64Encode(_foto!),
        });
      }

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Expediente guardado'),
          content: Text(
            'Código del expediente:\n$idObjeto\n\n'
            'Evento: $idEvento\n'
            'Georreferenciado: ${_ubicacion != null ? "sí" : "no"} · '
            'Necesidades: ${_necesidades.length} · '
            'Mediciones: ${_mediciones.length} · '
            'Foto: ${_fotoArchivo != null ? "sí" : "no"}\n\n'
            'Todo quedó archivado bajo el mismo código — captura única. '
            'A continuación se muestra en el mapa real.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ver en el mapa')),
          ],
        ),
      );
      if (!mounted) return;
      // Cierra el ciclo: deja ver el punto georreferenciado en tiempo real
      // (si hay conexión al backend) y, al volver, cae directo en el menú
      // principal listo para "Nuevo expediente" otra vez — sin arrastrar
      // el estado del formulario anterior.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MapaScreen(backendUrl: widget.backendUrl, idEvento: idEvento),
        ),
        (route) => route.isFirst,
      );
    } catch (e) {
      _mensaje(
        'No se pudo guardar contra el backend ($e). '
        'Nota: esta pantalla todavía no encola en la cola offline local — '
        'eso queda para la siguiente iteración (ver mobile/README_MOBILE.md).',
      );
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }
}
