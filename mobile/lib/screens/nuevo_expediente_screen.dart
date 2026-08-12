import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import '../data/colombia_departamentos.dart';
import '../data/colombia_municipios.dart';
import '../data/departamentos_capitales.dart';
import '../data/inspeccion_ais_opciones.dart';
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

/// Una foto de evidencia general con su etiqueta (fachada, interior, etc.).
/// A pedido del usuario: la app debe aceptar como mínimo 6 fotos por
/// vivienda, no solo una — se arrancan 6 categorías sugeridas típicas de un
/// EDAN de campo, y se puede agregar más si hace falta. Cada categoría es
/// opcional en sí misma (no todas las viviendas tienen escalera, por
/// ejemplo) pero el espacio para las 6 siempre está disponible.
class _FotoGeneral {
  String etiqueta;
  Uint8List? foto;
  XFile? archivo;
  _FotoGeneral(this.etiqueta);
}

class _NuevoExpedienteScreenState extends State<NuevoExpedienteScreen> {
  int _paso = 0;
  bool _guardando = false;
  bool _obteniendoUbicacion = false;
  // Mínimo 6 fotos aceptadas — categorías típicas de una inspección EDAN de
  // campo. Se puede agregar más con "Agregar otra foto"; ninguna es
  // obligatoria por sí sola (una casa puede no tener escalera), pero el
  // espacio para las 6 siempre está disponible desde el inicio.
  final List<_FotoGeneral> _fotosGenerales = [
    _FotoGeneral('Fachada / frente'),
    _FotoGeneral('Interior / adentro'),
    _FotoGeneral('Cocina'),
    _FotoGeneral('Escalera'),
    _FotoGeneral('Grietas / fisuras'),
    _FotoGeneral('Otra evidencia'),
  ];
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

  // --- Paso 2: Inspección técnica AIS — formulario oficial de la Unidad de
  // Gestión del Riesgo ("Guía Técnica para la Inspección de Edificaciones
  // Después de un Sismo"), reemplaza el checklist simplificado que tenía
  // SIGERIA antes. Mismos campos y opciones que el formulario en papel.
  // Encabezado / identificación catastral
  final _localidadCtrl = TextEditingController();
  final _nombreBarrioAisCtrl = TextEditingController();
  final _catastralBarrioCtrl = TextEditingController();
  final _catastralManzanaCtrl = TextEditingController();
  final _catastralPredioCtrl = TextEditingController();
  final _catastralConstruccionCtrl = TextEditingController();
  final _formularioNumeroCtrl = TextEditingController();
  String? _aisInspeccionTipo;
  // Identificación de la edificación
  String? _aisTipoVia;
  final _numeroViaCtrl = TextEditingController();
  final _nombreEdificacionCtrl = TextEditingController();
  String? _aisUsoPredominante;
  String? _aisUsoPredominantePlantaBaja;
  final _nivelesSobreTerrenoCtrl = TextEditingController();
  final _sotanosCtrl = TextEditingController();
  final _pisosTotalCtrl = TextEditingController();
  final _dimFrenteCtrl = TextEditingController();
  final _dimFondoCtrl = TextEditingController();
  // Descripción de la estructura
  String? _aisSistemaEstructural;
  final _sistemaEstructuralOtroCtrl = TextEditingController();
  String? _aisTipoEntrepiso;
  final _tipoEntrepisoOtroCtrl = TextEditingController();
  String? _aisAnioConstruccion;
  // Estado general de la edificación
  String? _aisExisteColapso;
  String? _aisDesviacionInclinacion;
  String? _aisFallaCimentacion;
  // Daños en elementos arquitectónicos
  String? _danoMurosFachada;
  String? _danoMurosDivisorios;
  String? _danoCieloRasos;
  String? _danoCubierta;
  String? _danoEscaleras;
  final Set<String> _instalacionesAfectadas = {};
  String? _danoInstalaciones;
  String? _danoTanquesElevados;
  // Problemas geotécnicos
  String? _fallaTalud;
  String? _asentamientoSubsidenciaLicuacion;
  // Daños en elementos estructurales (piso de mayor afectación)
  final _nivelEntrepisoMayorDanoCtrl = TextEditingController();
  String? _danoColumnasMurosPortantes;
  String? _danoVigas;
  String? _danoNudosConexion;
  String? _danoEntrepisos;
  // Clasificación global
  final _pctDanoGlobalCtrl = TextEditingController();
  bool? _existeClasificacionPrevia;
  final _clasificacionPreviaCualCtrl = TextEditingController();
  // Recomendaciones y medidas de seguridad
  final Set<String> _visitaEspecializada = {};
  final Set<String> _intervencionRecomendada = {};
  final Set<String> _medidasSeguridad = {};
  final Set<String> _desconectarServicios = {};
  final _lugaresMedidasSeguridadCtrl = TextEditingController();
  // Condiciones preexistentes
  String? _calidadConstruccion;
  String? _posicionEdificacionManzana;
  String? _configuracionPlanta;
  String? _configuracionAltura;
  String? _configuracionEstructural;
  bool? _indiciosDanosSismosAnteriores;
  String? _huboReparacion;
  // Efecto en los ocupantes
  String? _huboMuertosHeridos;
  final _numeroFallecidosCtrl = TextEditingController();
  final _numeroHeridosCtrl = TextEditingController();
  // Ocupación de la edificación
  bool? _edificacionHabitada;
  final _numUnidadesExistentesCtrl = TextEditingController();
  final _numUnidadesNoHabitablesCtrl = TextEditingController();
  // Comentarios e inspectores
  final _comentariosAisCtrl = TextEditingController();
  final _codigoComisionCtrl = TextEditingController();
  final _numeroEvaluadoresCtrl = TextEditingController();
  final _nombreLiderComisionCtrl = TextEditingController();

  // --- Necesidades humanitarias — no forman parte del formulario AIS (que
  // solo evalúa seguridad estructural), pero siguen siendo datos valiosos de
  // SIGERIA para la atención a la familia; se conservan aquí.
  bool? _requiereSubsidioArrendamiento;
  final _personasAfectadasCtrl = TextEditingController();

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
            title: const Text('2. Inspección técnica AIS'),
            isActive: _paso >= 1,
            state: _paso > 1 ? StepState.complete : StepState.indexed,
            content: _pasoInspeccionAis(),
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
        _seccionFotosGenerales(),
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

  /// Paso 2 — formulario oficial AIS ("Guía Técnica para la Inspección de
  /// Edificaciones Después de un Sismo", Asociación Colombiana de
  /// Ingeniería Sísmica). Mismos campos, mismas opciones y mismo orden que
  /// el formulario en papel de 2 páginas que usa la Unidad de Gestión del
  /// Riesgo — reemplaza el checklist simplificado de 8 componentes que
  /// tenía SIGERIA antes, a pedido explícito del usuario ("el oficial lo
  /// debemos adoptar e implementar nosotros porque este es válido para
  /// unidad del riesgo nacional y local").
  Widget _pasoInspeccionAis() {
    final pct = double.tryParse(_pctDanoGlobalCtrl.text.replaceAll(',', '.'));
    final clasificacion = pct != null ? clasificacionDesdeporcentaje(pct) : null;
    final colorHab = clasificacion != null ? colorHabitabilidad[clasificacion] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Formulario oficial AIS — el mismo que usa la Unidad de Gestión del '
          'Riesgo. Llénalo por secciones; las que no apliquen se pueden dejar '
          'en blanco.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        _seccionAis('Identificación del formulario', [
          _campoTexto(_localidadCtrl, 'Localidad'),
          _campoTexto(_nombreBarrioAisCtrl, 'Nombre del barrio'),
          Row(children: [
            Expanded(child: _campoTexto(_catastralBarrioCtrl, 'Barrio (catastral)')),
            const SizedBox(width: 8),
            Expanded(child: _campoTexto(_catastralManzanaCtrl, 'Manzana')),
          ]),
          Row(children: [
            Expanded(child: _campoTexto(_catastralPredioCtrl, 'Predio')),
            const SizedBox(width: 8),
            Expanded(child: _campoTexto(_catastralConstruccionCtrl, 'Construcción')),
          ]),
          _campoTexto(_formularioNumeroCtrl, 'Formulario número'),
          _campoOpcion('Inspección de la edificación', _aisInspeccionTipo, inspeccionTipos,
              (v) => setState(() => _aisInspeccionTipo = v)),
        ]),
        _seccionAis('Identificación de la edificación', [
          Row(children: [
            Expanded(
              flex: 2,
              child: _campoOpcion('Tipo de vía', _aisTipoVia, tiposVia,
                  (v) => setState(() => _aisTipoVia = v)),
            ),
            const SizedBox(width: 8),
            Expanded(child: _campoTexto(_numeroViaCtrl, 'Número')),
          ]),
          _campoTexto(_nombreEdificacionCtrl, 'Nombre de la edificación'),
          _campoOpcion('Uso predominante', _aisUsoPredominante, usosPredominantes,
              (v) => setState(() => _aisUsoPredominante = v)),
          _campoOpcion(
              'Uso predominante de la planta baja', _aisUsoPredominantePlantaBaja, usosPredominantes,
              (v) => setState(() => _aisUsoPredominantePlantaBaja = v)),
          Row(children: [
            Expanded(
                child: _campoTexto(_nivelesSobreTerrenoCtrl, 'Niveles sobre el terreno',
                    teclado: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(
                child: _campoTexto(_sotanosCtrl, 'Sótanos', teclado: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(
                child: _campoTexto(_pisosTotalCtrl, 'Total', teclado: TextInputType.number)),
          ]),
          Row(children: [
            Expanded(
                child: _campoTexto(_dimFrenteCtrl, 'Frente (m)',
                    teclado: const TextInputType.numberWithOptions(decimal: true))),
            const SizedBox(width: 8),
            Expanded(
                child: _campoTexto(_dimFondoCtrl, 'Fondo (m)',
                    teclado: const TextInputType.numberWithOptions(decimal: true))),
          ]),
        ]),
        _seccionAis('Descripción de la estructura', [
          _campoOpcion('Sistema estructural', _aisSistemaEstructural, sistemasEstructurales,
              (v) => setState(() => _aisSistemaEstructural = v)),
          _campoTexto(_sistemaEstructuralOtroCtrl, 'Sistema estructural — especificar (si es "Otros")'),
          _campoOpcion('Tipo de entrepiso', _aisTipoEntrepiso, tiposEntrepiso,
              (v) => setState(() => _aisTipoEntrepiso = v)),
          _campoTexto(_tipoEntrepisoOtroCtrl, 'Tipo de entrepiso — especificar (si es "Otros")'),
          _campoOpcion('Año de construcción', _aisAnioConstruccion, aniosConstruccion,
              (v) => setState(() => _aisAnioConstruccion = v)),
        ]),
        _seccionAis('Estado general de la edificación', [
          _campoOpcion('¿Existe colapso?', _aisExisteColapso, existeColapsoOpciones,
              (v) => setState(() => _aisExisteColapso = v)),
          _campoOpcion('Desviación o inclinación de la edificación o de algún entrepiso',
              _aisDesviacionInclinacion, siNoIndeterminado,
              (v) => setState(() => _aisDesviacionInclinacion = v)),
          _campoOpcion('Falla o asentamiento de la cimentación', _aisFallaCimentacion,
              siNoIndeterminado, (v) => setState(() => _aisFallaCimentacion = v)),
        ]),
        _seccionAis('Daños en elementos arquitectónicos', [
          _campoOpcion('Muros de fachadas o antepechos', _danoMurosFachada, gradoDanoAis,
              (v) => setState(() => _danoMurosFachada = v)),
          _campoOpcion('Muros divisorios o particiones', _danoMurosDivisorios, gradoDanoAis,
              (v) => setState(() => _danoMurosDivisorios = v)),
          _campoOpcion('Cielo rasos y luminarias', _danoCieloRasos, gradoDanoAis,
              (v) => setState(() => _danoCieloRasos = v)),
          _campoOpcion('Cubierta', _danoCubierta, gradoDanoAis,
              (v) => setState(() => _danoCubierta = v)),
          _campoOpcion('Escaleras', _danoEscaleras, gradoDanoAis,
              (v) => setState(() => _danoEscaleras = v)),
          _campoMultiple('Instalaciones afectadas', instalacionesOpciones, _instalacionesAfectadas),
          _campoOpcion('Grado de daño de las instalaciones', _danoInstalaciones, gradoDanoAis,
              (v) => setState(() => _danoInstalaciones = v)),
          _campoOpcion('Tanques elevados', _danoTanquesElevados, gradoDanoAis,
              (v) => setState(() => _danoTanquesElevados = v)),
        ]),
        _seccionAis('Problemas geotécnicos', [
          _campoOpcion('Falla en talud o movimientos en masa', _fallaTalud, nivelPuntualGeneral,
              (v) => setState(() => _fallaTalud = v)),
          _campoOpcion('Asentamiento, subsidencia o licuación', _asentamientoSubsidenciaLicuacion,
              nivelPuntualGeneral, (v) => setState(() => _asentamientoSubsidenciaLicuacion = v)),
        ]),
        _seccionAis('Daños en elementos estructurales (piso de mayor afectación)', [
          _campoTexto(_nivelEntrepisoMayorDanoCtrl, 'Nivel de entrepiso con el mayor daño'),
          _campoOpcion('Columnas o muros portantes', _danoColumnasMurosPortantes, gradoDanoAis,
              (v) => setState(() => _danoColumnasMurosPortantes = v)),
          _campoOpcion('Vigas', _danoVigas, gradoDanoAis, (v) => setState(() => _danoVigas = v)),
          _campoOpcion('Nudos o puntos de conexión', _danoNudosConexion, gradoDanoAis,
              (v) => setState(() => _danoNudosConexion = v)),
          _campoOpcion('Entrepisos', _danoEntrepisos, gradoDanoAis,
              (v) => setState(() => _danoEntrepisos = v)),
        ]),
        _seccionAis('Clasificación global del daño y habitabilidad', [
          _campoTexto(_pctDanoGlobalCtrl, 'Porcentaje de daño global de la edificación (%)',
              teclado: const TextInputType.numberWithOptions(decimal: true)),
          if (clasificacion != null && colorHab != null)
            Card(
              color: _colorHabitabilidadFlutter(colorHab).withValues(alpha: 0.15),
              child: ListTile(
                leading: Icon(Icons.rule, color: _colorHabitabilidadFlutter(colorHab)),
                title: Text('Clasificación calculada: ${gradoDanoAis.firstWhere((g) => g['valor'] == clasificacion)['etiqueta']}'),
                subtitle: Text(
                  etiquetaHabitabilidad[colorHab] ?? colorHab,
                  style: TextStyle(color: _colorHabitabilidadFlutter(colorHab), fontWeight: FontWeight.bold),
                ),
              ),
            ),
          const SizedBox(height: 4),
          const Text('¿Existe una clasificación previa?', style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<bool?>(
            dense: true, title: const Text('Sí'), value: true,
            groupValue: _existeClasificacionPrevia,
            onChanged: (v) => setState(() => _existeClasificacionPrevia = v),
          ),
          RadioListTile<bool?>(
            dense: true, title: const Text('No'), value: false,
            groupValue: _existeClasificacionPrevia,
            onChanged: (v) => setState(() => _existeClasificacionPrevia = v),
          ),
          if (_existeClasificacionPrevia == true)
            _campoTexto(_clasificacionPreviaCualCtrl, '¿Cuál?'),
        ]),
        _seccionAis('Recomendaciones y medidas de seguridad', [
          _campoMultiple('Se necesita visita especializada por aspectos',
              visitaEspecializadaOpciones, _visitaEspecializada),
          _campoMultiple('Se recomienda intervención de', intervencionOpciones, _intervencionRecomendada),
          _campoMultiple('Medidas de seguridad', medidasSeguridadOpciones, _medidasSeguridad),
          _campoMultiple('Desconectar', serviciosDesconectarOpciones, _desconectarServicios),
          _campoTexto(_lugaresMedidasSeguridadCtrl,
              'Lugares de la edificación que requieren estas medidas'),
        ]),
        _seccionAis('Condiciones preexistentes', [
          _campoOpcion('Calidad de la construcción', _calidadConstruccion, calidadBuenaRegularMala,
              (v) => setState(() => _calidadConstruccion = v)),
          _campoOpcion('Posición de la edificación en la manzana', _posicionEdificacionManzana,
              posicionManzanaOpciones, (v) => setState(() => _posicionEdificacionManzana = v)),
          _campoOpcion('Configuración en planta', _configuracionPlanta, calidadBuenaRegularMala,
              (v) => setState(() => _configuracionPlanta = v)),
          _campoOpcion('Configuración en altura', _configuracionAltura, calidadBuenaRegularMala,
              (v) => setState(() => _configuracionAltura = v)),
          _campoOpcion('Configuración estructural', _configuracionEstructural, calidadBuenaRegularMala,
              (v) => setState(() => _configuracionEstructural = v)),
          SwitchListTile(
            dense: true,
            title: const Text('Hay indicios de daños por sismos anteriores'),
            value: _indiciosDanosSismosAnteriores ?? false,
            onChanged: (v) => setState(() => _indiciosDanosSismosAnteriores = v),
          ),
          _campoOpcion('Hubo reparación', _huboReparacion, huboReparacionOpciones,
              (v) => setState(() => _huboReparacion = v)),
        ]),
        _seccionAis('Efecto en los ocupantes', [
          _campoOpcion('Hubo muertos o heridos', _huboMuertosHeridos, huboMuertosHeridosOpciones,
              (v) => setState(() => _huboMuertosHeridos = v)),
          Row(children: [
            Expanded(
                child: _campoTexto(_numeroFallecidosCtrl, 'Número de fallecidos',
                    teclado: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(
                child: _campoTexto(_numeroHeridosCtrl, 'Número de heridos',
                    teclado: TextInputType.number)),
          ]),
        ]),
        _seccionAis('Ocupación de la edificación', [
          SwitchListTile(
            dense: true,
            title: const Text('En el momento de esta evaluación, la edificación está habitada'),
            value: _edificacionHabitada ?? false,
            onChanged: (v) => setState(() => _edificacionHabitada = v),
          ),
          Row(children: [
            Expanded(
                child: _campoTexto(_numUnidadesExistentesCtrl, 'Unidades existentes',
                    teclado: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(
                child: _campoTexto(_numUnidadesNoHabitablesCtrl, 'Unidades no habitables',
                    teclado: TextInputType.number)),
          ]),
        ]),
        _seccionAis('Comentarios e inspectores', [
          TextFormField(
            controller: _comentariosAisCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Comentarios',
              hintText: 'Amplíe la evaluación con observaciones que ayuden a darle claridad.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _campoTexto(_codigoComisionCtrl, 'Código de la comisión')),
            const SizedBox(width: 8),
            Expanded(
                child: _campoTexto(_numeroEvaluadoresCtrl, 'No. de evaluadores',
                    teclado: TextInputType.number)),
          ]),
          _campoTexto(_nombreLiderComisionCtrl, 'Nombre del líder de la comisión'),
        ]),
        const Divider(height: 32),
        const Text('Necesidades humanitarias', style: TextStyle(fontWeight: FontWeight.bold)),
        const Text(
          'No forma parte del formulario AIS (que solo evalúa seguridad '
          'estructural) — se conserva para la atención a la familia.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
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
      ],
    );
  }

  Widget _seccionAis(String titulo, List<Widget> campos) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        initiallyExpanded: true,
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        children: [
          for (final c in campos) Padding(padding: const EdgeInsets.only(bottom: 8), child: c),
        ],
      ),
    );
  }

  Widget _campoOpcion(String etiqueta, String? valor, List<Map<String, String>> opciones,
      ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: valor,
      decoration: InputDecoration(labelText: etiqueta, isDense: true, border: const OutlineInputBorder()),
      items: opciones
          .map((o) => DropdownMenuItem(value: o['valor'], child: Text(o['etiqueta']!)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _campoMultiple(String etiqueta, List<Map<String, String>> opciones, Set<String> seleccionadas) {
    return Column(
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
    );
  }

  Color _colorHabitabilidadFlutter(String colorNombre) {
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

  /// Al menos 6 fotos aceptadas, con etiqueta editable (a pedido del
  /// usuario: "frente, adentro, cocina, escalera, grietas, mínimo 6 fotos
  /// que acepte que tomen"). Cada fila es una categoría; se puede agregar
  /// más filas con "Agregar otra foto" si hace falta (no hay tope).
  Widget _seccionFotosGenerales() {
    final tomadas = _fotosGenerales.where((f) => f.foto != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fotos de la vivienda ($tomadas de ${_fotosGenerales.length} tomadas — '
          'ninguna es obligatoria por sí sola, pero mientras más completas mejor).',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < _fotosGenerales.length; i++) _filaFotoGeneral(i),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Agregar otra foto'),
          onPressed: () => setState(() => _fotosGenerales.add(_FotoGeneral('Otra evidencia'))),
        ),
      ],
    );
  }

  Widget _filaFotoGeneral(int i) {
    final f = _fotosGenerales[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            if (f.foto != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(f.foto!, width: 48, height: 48, fit: BoxFit.cover),
              )
            else
              const Icon(Icons.image_outlined, size: 40, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: f.etiqueta,
                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                style: const TextStyle(fontSize: 14),
                onChanged: (v) => f.etiqueta = v,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.camera_alt),
              tooltip: 'Tomar foto con la cámara',
              onPressed: () => _tomarFotoGeneral(i),
            ),
            if (_fotosGenerales.length > 1)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                tooltip: 'Quitar esta fila',
                onPressed: () => setState(() => _fotosGenerales.removeAt(i)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _tomarFotoGeneral(int i) async {
    final resultado = await _capturarFoto();
    if (resultado == null) return;
    setState(() {
      _fotosGenerales[i].foto = resultado.$1;
      _fotosGenerales[i].archivo = resultado.$2;
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

  /// Captura GPS — blindada.
  ///
  /// Antes se pedía permiso con `checkPermission()`/`requestPermission()`
  /// ANTES de intentar leer la posición. En el navegador (Chrome/Safari de
  /// Android e iPhone) eso es poco confiable: `checkPermission()` usa la
  /// Permissions API (`navigator.permissions.query`), que en varios
  /// navegadores móviles devuelve "denied" o directamente falla ANTES de
  /// que el usuario haya visto siquiera el diálogo nativo de "Permitir
  /// ubicación" — eso es lo que producía "permiso denegado" aunque la
  /// persona nunca lo hubiera negado. La forma confiable en la web es pedir
  /// la posición DIRECTAMENTE con `getCurrentPosition()`: eso es lo que
  /// dispara el diálogo nativo del navegador de verdad, y solo si la
  /// persona toca "Bloquear" ahí sí llega la excepción de permiso.
  Future<void> _capturarUbicacion() async {
    setState(() => _obteniendoUbicacion = true);
    try {
      // Servicio de ubicación del dispositivo/navegador apagado del todo
      // (distinto de "permiso denegado" — este es un aviso más claro).
      final servicioActivo = await Geolocator.isLocationServiceEnabled().catchError((_) => true);
      if (!servicioActivo) {
        throw Exception(
            'La ubicación está desactivada en el dispositivo o navegador. Actívala en Ajustes.');
      }

      Position pos;
      try {
        // Intento directo — es lo que realmente dispara el permiso nativo.
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
      } on LocationServiceDisabledException {
        rethrow;
      } catch (_) {
        // Si el intento directo falla (algunos navegadores lo exigen),
        // recién ahí se revisa/pide permiso explícitamente como respaldo.
        var permiso = await Geolocator.checkPermission();
        if (permiso == LocationPermission.denied) {
          permiso = await Geolocator.requestPermission();
        }
        if (permiso == LocationPermission.deniedForever) {
          throw Exception(
              'Ubicación bloqueada para este sitio. En el navegador: ícono de candado → '
              'Permisos del sitio → Ubicación → Permitir, y vuelve a intentar.');
        }
        if (permiso == LocationPermission.denied) {
          throw Exception('Permiso de ubicación denegado. Vuelve a intentar y toca "Permitir".');
        }
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
        );
      }
      setState(() {
        _ubicacion = {'lat': pos.latitude, 'lon': pos.longitude, 'precision_m': pos.accuracy};
      });
      await _dibujarPuntoMiniMapa();
      _mensaje('Ubicación capturada correctamente.');
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
    // Foto y GPS son opcionales a nivel técnico (a veces no hay señal o la
    // cámara falla en campo), pero un expediente sin ninguno de los dos
    // pierde casi todo su valor para EDAN. En vez de bloquear el guardado,
    // se avisa con claridad y se deja decidir — así no se pierde el resto
    // de los datos ya digitados si de verdad no se puede completar.
    final faltaFoto = _fotosGenerales.every((f) => f.foto == null);
    final faltaGps = _ubicacion == null;
    if (faltaFoto || faltaGps) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Expediente incompleto'),
          content: Text(
            'Todavía falta:\n'
            '${faltaFoto ? '• Ninguna foto tomada (paso 1)\n' : ''}'
            '${faltaGps ? '• Ubicación GPS (paso 3)\n' : ''}'
            '\n¿Guardar de todas formas? Podrás completarlo después desde '
            '"Consultar registros".',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Guardar de todas formas')),
          ],
        ),
      );
      if (continuar != true) return;
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
      // El nivel de daño preliminar ya NO sale de una pregunta aparte ni de
      // un checklist propio: lo fija la inspección AIS (paso 5, más abajo),
      // que actualiza este mismo objeto con su clasificación oficial.
      final objeto = await api.post('/api/eventos/objetos', {
        'id_evento': idEvento,
        'tipo_objeto': _tipoObjeto,
        'estado_operativo': _estadoOperativo,
        'personas_afectadas': int.tryParse(_personasAfectadasCtrl.text.trim()),
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

      // 5) Inspección técnica AIS — MISMO id_objeto. Este POST es el que
      // calcula la clasificación de habitabilidad y actualiza
      // `objeto_afectado.nivel_dano_preliminar` en el backend (ver
      // `_sincronizar_objeto_afectado` en inspeccion_ais.py) — así el mapa
      // y las estadísticas siguen coloreando el punto igual que antes,
      // ahora con el dato oficial en vez del checklist simplificado.
      await api.post('/api/inspeccion-ais', {
        'id_objeto': idObjeto,
        'localidad': _localidadCtrl.text.trim(),
        'nombre_barrio': _nombreBarrioAisCtrl.text.trim(),
        'ident_catastral_barrio': _catastralBarrioCtrl.text.trim(),
        'ident_catastral_manzana': _catastralManzanaCtrl.text.trim(),
        'ident_catastral_predio': _catastralPredioCtrl.text.trim(),
        'ident_catastral_construccion': _catastralConstruccionCtrl.text.trim(),
        'formulario_numero': _formularioNumeroCtrl.text.trim(),
        'inspeccion_tipo': _aisInspeccionTipo,
        'tipo_via': _aisTipoVia,
        'numero_via': _numeroViaCtrl.text.trim(),
        'nombre_edificacion': _nombreEdificacionCtrl.text.trim(),
        'uso_predominante': _aisUsoPredominante,
        'uso_predominante_planta_baja': _aisUsoPredominantePlantaBaja,
        'niveles_sobre_terreno': int.tryParse(_nivelesSobreTerrenoCtrl.text.trim()),
        'sotanos': int.tryParse(_sotanosCtrl.text.trim()),
        'pisos_total': int.tryParse(_pisosTotalCtrl.text.trim()),
        'dimension_frente_m': double.tryParse(_dimFrenteCtrl.text.trim()),
        'dimension_fondo_m': double.tryParse(_dimFondoCtrl.text.trim()),
        'sistema_estructural': _aisSistemaEstructural,
        'sistema_estructural_otro': _sistemaEstructuralOtroCtrl.text.trim(),
        'tipo_entrepiso': _aisTipoEntrepiso,
        'tipo_entrepiso_otro': _tipoEntrepisoOtroCtrl.text.trim(),
        'anio_construccion': _aisAnioConstruccion,
        'existe_colapso': _aisExisteColapso,
        'desviacion_inclinacion': _aisDesviacionInclinacion,
        'falla_asentamiento_cimentacion': _aisFallaCimentacion,
        'dano_muros_fachada': _danoMurosFachada,
        'dano_muros_divisorios': _danoMurosDivisorios,
        'dano_cielo_rasos': _danoCieloRasos,
        'dano_cubierta': _danoCubierta,
        'dano_escaleras': _danoEscaleras,
        'instalaciones_afectadas': _instalacionesAfectadas.toList(),
        'dano_instalaciones': _danoInstalaciones,
        'dano_tanques_elevados': _danoTanquesElevados,
        'falla_talud': _fallaTalud,
        'asentamiento_subsidencia_licuacion': _asentamientoSubsidenciaLicuacion,
        'nivel_entrepiso_mayor_dano': _nivelEntrepisoMayorDanoCtrl.text.trim(),
        'dano_columnas_muros_portantes': _danoColumnasMurosPortantes,
        'dano_vigas': _danoVigas,
        'dano_nudos_conexion': _danoNudosConexion,
        'dano_entrepisos': _danoEntrepisos,
        'pct_dano_global': double.tryParse(_pctDanoGlobalCtrl.text.replaceAll(',', '.').trim()),
        'existe_clasificacion_previa': _existeClasificacionPrevia,
        'clasificacion_previa_cual': _clasificacionPreviaCualCtrl.text.trim(),
        'requiere_visita_especializada': _visitaEspecializada.toList(),
        'recomienda_intervencion': _intervencionRecomendada.toList(),
        'medidas_seguridad': _medidasSeguridad.toList(),
        'desconectar_servicios': _desconectarServicios.toList(),
        'lugares_medidas_seguridad_texto': _lugaresMedidasSeguridadCtrl.text.trim(),
        'calidad_construccion': _calidadConstruccion,
        'posicion_edificacion_manzana': _posicionEdificacionManzana,
        'configuracion_planta': _configuracionPlanta,
        'configuracion_altura': _configuracionAltura,
        'configuracion_estructural': _configuracionEstructural,
        'indicios_danos_sismos_anteriores': _indiciosDanosSismosAnteriores,
        'hubo_reparacion': _huboReparacion,
        'hubo_muertos_heridos': _huboMuertosHeridos,
        'numero_personas_fallecidas': int.tryParse(_numeroFallecidosCtrl.text.trim()),
        'numero_heridos': int.tryParse(_numeroHeridosCtrl.text.trim()),
        'edificacion_habitada': _edificacionHabitada,
        'num_unidades_existentes': int.tryParse(_numUnidadesExistentesCtrl.text.trim()),
        'num_unidades_no_habitables': int.tryParse(_numUnidadesNoHabitablesCtrl.text.trim()),
        'comentarios': _comentariosAisCtrl.text.trim(),
        'codigo_comision': _codigoComisionCtrl.text.trim(),
        'numero_evaluadores': int.tryParse(_numeroEvaluadoresCtrl.text.trim()),
        'nombre_lider_comision': _nombreLiderComisionCtrl.text.trim(),
        'fecha_inspeccion': DateTime.now().toIso8601String(),
        'creado_por': _recolectorNombreCtrl.text.trim(),
      });

      // 6) Mediciones — MISMO id_objeto (con su foto calibrada si se tomó)
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

      // 6) Fotos generales — MISMO id_objeto (quedan archivadas con el código
      // de la vivienda, cada una con su etiqueta de categoría en el nombre;
      // se sube el contenido real, no solo el nombre, para que el reporte
      // PDF pueda mostrarlas de verdad). Mínimo 6 categorías sugeridas desde
      // el inicio, pero solo se suben las que sí tienen foto tomada.
      var fotosGuardadas = 0;
      for (final f in _fotosGenerales) {
        if (f.archivo == null || f.foto == null) continue;
        await api.post('/api/edan/evidencias', {
          'id_objeto': idObjeto,
          'tipo': 'foto',
          'url_almacenamiento': '${f.etiqueta}_${f.archivo!.name}',
          'usuario_id': _recolectorNombreCtrl.text.trim(),
          'contenido_base64': base64Encode(f.foto!),
        });
        fotosGuardadas++;
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
            'Fotos: $fotosGuardadas\n\n'
            'Todo quedó archivado bajo el mismo código — captura única. '
            'A continuación se muestra en el mapa real.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Ver en el mapa')),
          ],
        ),
      );
      if (!mounted) return;
      // Cierra el ciclo: abre el mapa GENERAL en vivo (no solo este evento)
      // para que el punto recién creado se vea de una vez como parte de la
      // malla completa que va creciendo — a pedido explícito del usuario
      // ("debe de una vez aparecer georreferenciados los puntos" en la
      // malla, no aislado). Al volver, cae directo en el menú principal
      // listo para "Nuevo expediente" otra vez — sin arrastrar el estado
      // del formulario anterior.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => MapaScreen(backendUrl: widget.backendUrl),
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
