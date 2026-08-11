import 'package:flutter/material.dart';
import 'screens/como_funciona_screen.dart';
import 'screens/mapa_screen.dart';
import 'screens/nuevo_expediente_screen.dart';
import 'services/sync_queue.dart';

/// SIGERIA Campo | módulo de SAT-GeoAI Chocó
/// Punto de entrada — home con menú, eslogan y los 4 módulos del MVP
/// (sección 22 del documento base): Evento y objetos, EDAN básico, GIS
/// offline, Medición móvil.
void main() {
  runApp(const SigeriaCampoApp());
}

const String kEslogan = 'Captura una vez. SIGERIA hace el resto.';

class SigeriaCampoApp extends StatelessWidget {
  const SigeriaCampoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SIGERIA Campo',
      theme: ThemeData(
        // Alto contraste, botones grandes — requisito no funcional (sección 28)
        colorSchemeSeed: const Color(0xFF1F4E5F),
        useMaterial3: true,
        textTheme: const TextTheme(bodyLarge: TextStyle(fontSize: 18)),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const backendUrl = String.fromEnvironment(
    'SIGERIA_API',
    defaultValue: 'http://10.0.2.2:8010', // loopback del emulador Android hacia el host
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SIGERIA Campo')),
      drawer: _MenuSigeria(backendUrl: backendUrl),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bannerEslogan(context),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.add_home_work),
            label: const Text('Nuevo expediente (vivienda o familia afectada)'),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            onPressed: () => _abrirExpediente(context),
          ),
          const SizedBox(height: 16),
          const Text(
            'Un expediente = un solo código para la vivienda/familia. '
            'Estos 4 pasos NO son formularios separados: son las etapas de un '
            'mismo expediente — el evento, el EDAN, la ubicación GIS y las '
            'mediciones quedan bajo el mismo código, sin volver a preguntar '
            'lo mismo dos veces.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          _tarjetaModulo(context, '1. Evento y objeto', Icons.warning_amber,
              'Fenómeno, ubicación, responsable e informante'),
          _tarjetaModulo(context, '2. EDAN básico adaptativo', Icons.assignment,
              'Daños, necesidades y subsidio de arrendamiento'),
          _tarjetaModulo(context, '3. GIS — ubicación real', Icons.map,
              'GPS real vinculado al mismo expediente'),
          _tarjetaModulo(context, '4. Medición móvil', Icons.straighten,
              'Distancia, área, pendiente — del mismo expediente'),
          const Divider(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.help_outline),
            label: const Text('Ver cómo funciona'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ComoFuncionaScreen()),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.map),
            label: const Text('Abrir mapa real (todos los expedientes)'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MapaScreen(backendUrl: backendUrl)),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.sync),
            label: const Text('Sincronizar pendientes'),
            onPressed: () => _sincronizar(context),
          ),
        ],
      ),
    );
  }

  Widget _bannerEslogan(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Image.asset('assets/branding/logo.png', width: 48, height: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              kEslogan,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaModulo(
      BuildContext context, String titulo, IconData icono, String subtitulo) {
    return Card(
      child: ListTile(
        leading: Icon(icono, size: 32),
        title: Text(titulo),
        subtitle: Text(subtitulo),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _abrirExpediente(context),
      ),
    );
  }

  static void _abrirExpediente(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NuevoExpedienteScreen(backendUrl: backendUrl)),
    );
  }

  static Future<void> _sincronizar(BuildContext context) async {
    final resumen = await SyncQueue(baseUrl: backendUrl).sincronizar();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sincronización: $resumen')),
      );
    }
  }
}

/// Menú lateral — misma estructura de navegación que apps de campo tipo
/// SW Maps (Proyecto / Mapa / Capas / Datos / Ajustes), adaptada a SIGERIA.
class _MenuSigeria extends StatelessWidget {
  final String backendUrl;
  const _MenuSigeria({required this.backendUrl});

  // Los 4 pasos son el MISMO expediente (Stepper único, ver
  // nuevo_expediente_screen.dart) — el menú los muestra por claridad, pero
  // los cuatro abren la misma pantalla, no formularios sueltos.
  void _abrirExpedienteDesdeMenu(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NuevoExpedienteScreen(backendUrl: backendUrl)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            child: Row(
              children: [
                ClipOval(
                  child: Image.asset('assets/branding/logo.png', width: 56, height: 56),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('SIGERIA Campo',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 4),
                      Text(kEslogan,
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Inicio'),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Mapa general en vivo'),
            subtitle: const Text('Malla de puntos de todos los expedientes'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => MapaScreen(backendUrl: backendUrl)));
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8, bottom: 4),
            child: Text('Expediente (4 pasos)', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          ListTile(
            leading: const Icon(Icons.warning_amber),
            title: const Text('1. Evento y objeto'),
            onTap: () => _abrirExpedienteDesdeMenu(context),
          ),
          ListTile(
            leading: const Icon(Icons.assignment),
            title: const Text('2. EDAN básico adaptativo'),
            onTap: () => _abrirExpedienteDesdeMenu(context),
          ),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const Text('3. GIS — ubicación real'),
            onTap: () => _abrirExpedienteDesdeMenu(context),
          ),
          ListTile(
            leading: const Icon(Icons.straighten),
            title: const Text('4. Medición móvil'),
            onTap: () => _abrirExpedienteDesdeMenu(context),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Cómo funciona'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const ComoFuncionaScreen()));
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sincronizar pendientes'),
            onTap: () {
              Navigator.pop(context);
              HomeScreen._sincronizar(context);
            },
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'SIGERIA no sustituye dictamen profesional ni instrumentos '
              'oficiales EDAN/RUD de la UNGRD.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
