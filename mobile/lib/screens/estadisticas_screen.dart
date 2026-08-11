import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../data/colombia_departamentos.dart';
import '../data/colombia_municipios.dart';
import '../data/componentes_dano.dart';
import '../widgets/mapa_vivo_embed.dart';

/// Pantalla de Estadísticas — a pedido del usuario: "una ventana donde se
/// vaya viendo el registro" + "en el visor del mapa donde escojamos
/// departamento y municipio se vea la malla de puntos" + "datos estadísticos
/// de afectados y los daños que más ocurrieron". Todo el análisis (sumas,
/// promedios, agrupaciones) lo hace el backend en Python — esta pantalla
/// solo pide los números ya calculados y los muestra.
///
/// Se refresca sola cada 20 s (Timer.periodic) para sentirse "en vivo" sin
/// que la persona tenga que salir y volver a entrar — como pidió el usuario.
class EstadisticasScreen extends StatefulWidget {
  final String backendUrl;
  const EstadisticasScreen({super.key, required this.backendUrl});

  @override
  State<EstadisticasScreen> createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen> {
  String? _departamento;
  MunicipioColombia? _municipio;

  Map<String, dynamic>? _general;
  Map<String, dynamic>? _componentes;
  List<dynamic> _registroReciente = [];
  String? _error;
  bool _cargando = true;
  Timer? _timer;

  static final _nombresComponentes = {
    for (final c in componentesDano) c['id']!: c['nombre']!,
  };

  @override
  void initState() {
    super.initState();
    _cargarTodo();
    // "En vivo": se refresca sola mientras la pantalla esté abierta.
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _cargarTodo(silencioso: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Map<String, String> get _paramsFiltro => {
        if (_departamento != null) 'departamento': _departamento!,
        if (_municipio != null) 'municipio_divipola': _municipio!.divipola,
      };

  Future<void> _cargarTodo({bool silencioso = false}) async {
    if (!silencioso) setState(() => _cargando = true);
    try {
      final base = widget.backendUrl;
      final qs = _paramsFiltro;
      final urlGeneral = Uri.parse('$base/api/estadisticas/general').replace(queryParameters: qs.isEmpty ? null : qs);
      final urlComponentes = Uri.parse('$base/api/estadisticas/componentes').replace(queryParameters: qs.isEmpty ? null : qs);
      final urlReciente = Uri.parse('$base/api/estadisticas/registro_reciente')
          .replace(queryParameters: {...qs, 'limite': '15'});

      final resultados = await Future.wait([
        http.get(urlGeneral).timeout(const Duration(seconds: 10)),
        http.get(urlComponentes).timeout(const Duration(seconds: 10)),
        http.get(urlReciente).timeout(const Duration(seconds: 10)),
      ]);
      for (final r in resultados) {
        if (r.statusCode != 200) throw Exception('Backend respondió ${r.statusCode}');
      }
      if (!mounted) return;
      setState(() {
        _general = jsonDecode(resultados[0].body) as Map<String, dynamic>;
        _componentes = jsonDecode(resultados[1].body) as Map<String, dynamic>;
        _registroReciente = (jsonDecode(resultados[2].body) as Map<String, dynamic>)['registros'] as List<dynamic>;
        _error = null;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo conectar con el backend: $e';
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar ahora',
            onPressed: () => _cargarTodo(),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _cargarTodo(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _filtroZona(),
            const SizedBox(height: 16),
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                ),
              )
            else if (_cargando)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              Text('Malla de puntos — ${_tituloZona()}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              MapaVivoEmbed(
                backendUrl: widget.backendUrl,
                departamento: _departamento,
                municipioDivipola: _municipio?.divipola,
              ),
              const SizedBox(height: 20),
              _tarjetasResumen(),
              const SizedBox(height: 20),
              const Text('Daños que más ocurrieron',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text(
                'Componentes constructivos marcados como afectados (leve, parcial, '
                'estructural o colapso) en todos los expedientes de la zona elegida.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              _listaComponentesMasAfectados(),
              const SizedBox(height: 20),
              const Text('Registro reciente — se va llenando en vivo',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              _listaRegistroReciente(),
            ],
          ],
        ),
      ),
    );
  }

  String _tituloZona() {
    if (_municipio != null) return _municipio!.nombre;
    if (_departamento != null) return _departamento!;
    return 'todo el país';
  }

  Widget _filtroZona() {
    final codigoDepto = _departamento == null ? null : _codigoDepartamento(_departamento!);
    final municipios = codigoDepto == null
        ? const <MunicipioColombia>[]
        : municipiosPorDepartamento[codigoDepto] ?? const <MunicipioColombia>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Filtrar por zona', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              isExpanded: true,
              initialValue: _departamento,
              decoration: const InputDecoration(labelText: 'Departamento', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos los departamentos')),
                ...departamentosColombia
                    .map((d) => DropdownMenuItem(value: d['nombre'], child: Text(d['nombre']!))),
              ],
              onChanged: (v) {
                setState(() {
                  _departamento = v;
                  _municipio = null;
                });
                _cargarTodo();
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<MunicipioColombia?>(
              isExpanded: true,
              initialValue: _municipio,
              decoration: const InputDecoration(labelText: 'Municipio', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('Todos los municipios')),
                ...municipios.map((m) => DropdownMenuItem(value: m, child: Text(m.nombre))),
              ],
              onChanged: _departamento == null
                  ? null
                  : (v) {
                      setState(() => _municipio = v);
                      _cargarTodo();
                    },
            ),
          ],
        ),
      ),
    );
  }

  String? _codigoDepartamento(String nombreDepartamento) {
    for (final d in departamentosColombia) {
      if (d['nombre'] == nombreDepartamento) return d['codigo'];
    }
    return null;
  }

  Widget _tarjetasResumen() {
    final g = _general!;
    return Row(
      children: [
        Expanded(child: _tarjetaKpi('Expedientes', '${g['total_objetos_afectados']}', Icons.home_work)),
        const SizedBox(width: 8),
        Expanded(child: _tarjetaKpi('Eventos', '${g['total_eventos']}', Icons.warning_amber)),
        const SizedBox(width: 8),
        Expanded(
            child: _tarjetaKpi(
                'Personas afectadas', '${g['total_personas_afectadas']}', Icons.groups)),
      ],
    );
  }

  Widget _tarjetaKpi(String etiqueta, String valor, IconData icono) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icono, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 4),
            Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(etiqueta, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _listaComponentesMasAfectados() {
    final lista = (_componentes?['componentes_mas_afectados'] as List<dynamic>? ?? []);
    if (lista.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Todavía no hay componentes marcados como afectados en esta zona.',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    final maxTotal = (lista.first['total'] as num).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: lista.map((c) {
            final total = (c['total'] as num).toDouble();
            final nombre = _nombresComponentes[c['componente']] ?? c['componente'] as String;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(nombre)),
                      Text('${total.toInt()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: maxTotal == 0 ? 0 : total / maxTotal,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _listaRegistroReciente() {
    if (_registroReciente.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('Todavía no hay expedientes guardados en esta zona.',
              style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return Card(
      child: Column(
        children: _registroReciente.map((r) {
          final m = r as Map<String, dynamic>;
          return ListTile(
            dense: true,
            leading: Icon(Icons.home, color: _colorSeveridad(m['nivel_dano_preliminar'] as String?)),
            title: Text(m['id_objeto'] as String, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              '${m['tipo_objeto']} · ${m['departamento'] ?? m['municipio_divipola']} · '
              '${m['fenomeno']} · ${_fechaCorta(m['creado_en'] as String?)}',
              style: const TextStyle(fontSize: 11),
            ),
            trailing: Text(
              (m['nivel_dano_preliminar'] as String?) ?? 'sin_evaluar',
              style: TextStyle(
                fontSize: 11,
                color: _colorSeveridad(m['nivel_dano_preliminar'] as String?),
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _fechaCorta(String? isoUtc) {
    if (isoUtc == null) return '—';
    final dt = DateTime.tryParse(isoUtc)?.toLocal();
    if (dt == null) return '—';
    final ahora = DateTime.now();
    final diferencia = ahora.difference(dt);
    if (diferencia.inMinutes < 1) return 'ahora mismo';
    if (diferencia.inMinutes < 60) return 'hace ${diferencia.inMinutes} min';
    if (diferencia.inHours < 24) return 'hace ${diferencia.inHours} h';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Color _colorSeveridad(String? valor) {
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
}
