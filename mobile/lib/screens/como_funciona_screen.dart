import 'package:flutter/material.dart';

/// Paso a paso de cómo funciona SIGERIA Campo — mismo flujo general de uso
/// descrito en la sección 6 del documento base, en modo imperativo (verbo al
/// frente, frases cortas) para que se lea rápido en campo.
class ComoFuncionaScreen extends StatelessWidget {
  const ComoFuncionaScreen({super.key});

  static const _pasos = [
    (Icons.warning_amber, 'Selecciona el evento',
        'Elige el fenómeno: sismo, inundación, deslizamiento, vendaval, incendio, erosión u otro.'),
    (Icons.gps_fixed, 'Ubica el punto',
        'Toca el GPS o el mapa. Se registra la posición real con su precisión.'),
    (Icons.home_work, 'Elige el objeto afectado',
        'Vivienda, salud, educación, vía, puente u otro. La ficha se adapta sola.'),
    (Icons.assignment, 'Llena la ficha adaptativa',
        'Solo aparecen los campos que aplican al fenómeno y al objeto elegidos.'),
    (Icons.camera_alt, 'Toma fotos y mide',
        'Cámara, distancia, área, pendiente — todo queda vinculado al mismo objeto.'),
    (Icons.save, 'Guarda (funciona offline)',
        'Un dato, un solo registro. Se guarda en el dispositivo aunque no haya señal.'),
    (Icons.sync, 'Sincroniza cuando haya señal',
        'La cola de sincronización sube todo solo, sin volver a digitar nada.'),
    (Icons.map, 'Consulta el mapa',
        'Cada dato levantado queda señalado en el mapa real, con su severidad.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cómo funciona SIGERIA')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _pasos.length,
        separatorBuilder: (_, __) => const Divider(height: 24),
        itemBuilder: (context, i) {
          final (icono, titulo, detalle) = _pasos[i];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                child: Text('${i + 1}'),
              ),
              const SizedBox(width: 12),
              Icon(icono, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(detalle),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
