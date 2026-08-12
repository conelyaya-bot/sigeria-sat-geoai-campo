import 'package:flutter/material.dart';
import '../data/colombia_departamentos.dart';
import '../data/colombia_municipios.dart';
import '../services/api_client.dart';
import 'ficha_expediente_screen.dart';

/// "Consultar registros" — el sitio que faltaba para VER lo ya levantado,
/// no solo capturarlo. Lista filtrable por departamento/municipio/texto;
/// al tocar un registro se abre su ficha completa (con editar/eliminar).
class ConsultaRegistrosScreen extends StatefulWidget {
  final String backendUrl;
  const ConsultaRegistrosScreen({super.key, required this.backendUrl});

  @override
  State<ConsultaRegistrosScreen> createState() => _ConsultaRegistrosScreenState();
}

class _ConsultaRegistrosScreenState extends State<ConsultaRegistrosScreen> {
  String? _departamento;
  String? _municipioDivipola;
  final _busquedaCtrl = TextEditingController();
  bool _cargando = true;
  String? _error;
  List<dynamic> _registros = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  String? _codigoDepartamento(String? nombre) {
    if (nombre == null) return null;
    for (final d in departamentosColombia) {
      if (d['nombre'] == nombre) return d['codigo'];
    }
    return null;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    final api = ApiClient(baseUrl: widget.backendUrl);
    try {
      final params = <String, String>{};
      if (_departamento != null) params['departamento'] = _departamento!;
      if (_municipioDivipola != null) params['municipio_divipola'] = _municipioDivipola!;
      if (_busquedaCtrl.text.trim().isNotEmpty) params['q'] = _busquedaCtrl.text.trim();
      final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
      final ruta = '/api/expedientes/lista${query.isNotEmpty ? '?$query' : ''}';
      final lista = await api.getLista(ruta);
      if (!mounted) return;
      setState(() {
        _registros = lista;
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

  @override
  Widget build(BuildContext context) {
    final codigoDepto = _codigoDepartamento(_departamento);
    final municipios = codigoDepto != null
        ? (municipiosPorDepartamento[codigoDepto] ?? const <MunicipioColombia>[])
        : const <MunicipioColombia>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Consultar registros'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargando ? null : _cargar),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _departamento,
                        decoration: const InputDecoration(
                          labelText: 'Departamento (todos)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Todos')),
                          ...departamentosColombia.map(
                            (d) => DropdownMenuItem(value: d['nombre'], child: Text(d['nombre']!)),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() {
                            _departamento = v;
                            _municipioDivipola = null;
                          });
                          _cargar();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _municipioDivipola,
                        decoration: const InputDecoration(
                          labelText: 'Municipio (todos)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('Todos')),
                          ...municipios.map(
                            (m) => DropdownMenuItem(value: m.divipola, child: Text(m.nombre)),
                          ),
                        ],
                        onChanged: municipios.isEmpty
                            ? null
                            : (v) {
                                setState(() => _municipioDivipola = v);
                                _cargar();
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _busquedaCtrl,
                  decoration: InputDecoration(
                    labelText: 'Buscar por código, dirección, barrio o nombre',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _cargar),
                  ),
                  onSubmitted: (_) => _cargar(),
                ),
              ],
            ),
          ),
          if (_cargando) const Expanded(child: Center(child: CircularProgressIndicator())),
          if (!_cargando && _error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('No se pudo cargar: $_error', textAlign: TextAlign.center),
                ),
              ),
            ),
          if (!_cargando && _error == null && _registros.isEmpty)
            const Expanded(
              child: Center(child: Text('No hay registros con estos filtros.')),
            ),
          if (!_cargando && _error == null && _registros.isNotEmpty)
            Expanded(
              child: RefreshIndicator(
                onRefresh: _cargar,
                child: ListView.builder(
                  itemCount: _registros.length,
                  itemBuilder: (context, i) => _tarjetaRegistro(_registros[i] as Map<String, dynamic>),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tarjetaRegistro(Map<String, dynamic> r) {
    final tieneFoto = (r['num_fotos'] ?? 0) > 0;
    final tieneGps = (r['num_geometrias'] ?? 0) > 0;
    final nivel = r['nivel_dano_preliminar'] as String?;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _colorNivel(nivel).withValues(alpha: 0.2),
          child: Icon(Icons.home_work, color: _colorNivel(nivel)),
        ),
        title: Text(
          r['id_objeto'] as String,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        subtitle: Text(
          '${r['tipo_objeto']} · ${r['municipio_divipola'] ?? '?'} · '
          '${r['barrio_vereda'] ?? r['direccion'] ?? 'sin dirección'}\n'
          'Daño: ${nivel ?? 'sin evaluar'} · '
          '${r['personas_afectadas'] != null ? '${r['personas_afectadas']} personas' : ''}',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(tieneFoto ? Icons.photo_camera : Icons.no_photography,
                size: 18, color: tieneFoto ? Colors.green : Colors.grey),
            Icon(tieneGps ? Icons.gps_fixed : Icons.gps_off,
                size: 18, color: tieneGps ? Colors.green : Colors.grey),
          ],
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FichaExpedienteScreen(
                backendUrl: widget.backendUrl,
                idObjeto: r['id_objeto'] as String,
              ),
            ),
          );
          _cargar(); // por si se editó o eliminó, refresca la lista al volver
        },
      ),
    );
  }

  Color _colorNivel(String? valor) {
    switch (valor) {
      case 'leve':
        return const Color(0xFFC9B400);
      case 'moderado':
        return const Color(0xFFE08A1E);
      case 'severo':
        return const Color(0xFFD1392B);
      case 'colapso':
        return const Color(0xFF6B0F1A);
      default:
        return const Color(0xFF2E8B57);
    }
  }
}
