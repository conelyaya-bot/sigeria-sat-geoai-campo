// Prueba mínima de humo para SIGERIA Campo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sigeria_campo/data/colombia_municipios.dart';
import 'package:sigeria_campo/main.dart';

void main() {
  testWidgets('Home muestra los 4 módulos del MVP', (WidgetTester tester) async {
    await tester.pumpWidget(const SigeriaCampoApp());

    expect(find.text('SIGERIA Campo'), findsOneWidget);
    expect(find.text('Nuevo expediente (vivienda o familia afectada)'), findsOneWidget);
    // El mapa en vivo ocupa el espacio principal de Inicio.
    expect(find.text('Mapa en vivo — malla de puntos'), findsOneWidget);

    // Los 4 pasos viven en el menú lateral — hay que abrirlo para que se construya.
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    // "skipOffstage: false" porque, con la entrada "Estadísticas" agregada
    // al menú, estos ítems quedan más abajo del scroll del Drawer en el
    // viewport del test — siguen en el árbol, solo no visibles sin
    // desplazar (comportamiento normal de un menú con varias entradas).
    expect(find.text('1. Evento y objeto', skipOffstage: false), findsOneWidget);
    expect(find.text('2. Inspección técnica AIS', skipOffstage: false), findsOneWidget);
    expect(find.text('3. GIS — ubicación real', skipOffstage: false), findsOneWidget);
    expect(find.text('4. Medición móvil', skipOffstage: false), findsOneWidget);
    expect(find.text('Estadísticas', skipOffstage: false), findsOneWidget);
    // Consultar registros — ver/editar/eliminar lo ya guardado, no solo capturar.
    expect(find.text('Consultar registros', skipOffstage: false), findsOneWidget);
  });

  testWidgets('Nuevo expediente abre el Stepper unico con los 4 pasos',
      (WidgetTester tester) async {
    await tester.pumpWidget(const SigeriaCampoApp());

    await tester.tap(find.text('Nuevo expediente (vivienda o familia afectada)'));
    await tester.pumpAndSettle();

    // Navegó a la pantalla del expediente único (no a 4 formularios sueltos).
    expect(find.text('Nuevo expediente'), findsOneWidget); // AppBar
    expect(find.text('1. Evento y objeto'), findsOneWidget); // Step título
    expect(find.text('Fenómeno'), findsOneWidget);
    expect(find.text('Departamento'), findsOneWidget);
    expect(find.text('Responsable de la recolección'), findsOneWidget);
    expect(find.text('Informante en la vivienda (beneficiario)'), findsOneWidget);

    // El municipio es un desplegable REAL (catálogo DANE, 1.122 municipios),
    // no texto libre — el código DIVIPOLA se genera solo al elegirlo.
    expect(find.byType(DropdownButtonFormField<MunicipioColombia>), findsOneWidget);
    expect(municipiosPorDepartamento['05']!.any((m) => m.nombre == 'Medellín' && m.divipola == '05001'),
        isTrue); // Antioquia (departamento por defecto) trae a Medellín con su DIVIPOLA real

    // El Stepper de Material solo construye el contenido del paso ACTIVO, y
    // con el formulario AIS del paso 2 (mucho más largo que el checklist
    // simplificado que reemplazó) el botón "Siguiente" puede quedar a miles
    // de píxeles del tope — perseguirlo con scroll/tap en un viewport de
    // prueba fijo es frágil y no aporta nada (no es lógica nuestra, es el
    // scroll interno de un widget de Flutter ya probado por su propio
    // equipo). En su lugar se invoca directo el mismo callback que dispara
    // el botón (`Stepper.onStepContinue`) — prueba la lógica real de
    // avance sin depender de coordenadas de pantalla.
    Future<void> avanzarPaso() async {
      final stepper = tester.widget<Stepper>(find.byType(Stepper));
      stepper.onStepContinue!();
      await tester.pumpAndSettle();
    }

    await avanzarPaso(); // 1 -> 2

    // Paso 2: formulario oficial AIS (reemplaza el checklist simplificado
    // de 8 componentes) — mismas secciones que el formulario en papel de la
    // Unidad de Gestión del Riesgo.
    expect(find.text('Identificación del formulario'), findsOneWidget);
    expect(find.text('Descripción de la estructura'), findsOneWidget);
    expect(find.text('Daños en elementos arquitectónicos'), findsOneWidget);
    expect(find.text('Problemas geotécnicos'), findsOneWidget);
    expect(find.text('Clasificación global del daño y habitabilidad'), findsOneWidget);
    expect(find.text('Recomendaciones y medidas de seguridad'), findsOneWidget);
    expect(find.text('Comentarios e inspectores'), findsOneWidget);
    expect(find.text('Terreno y cimentación'), findsNothing); // checklist viejo, ya no existe
    // Necesidades humanitarias se conservan aparte del formulario AIS.
    expect(find.text('¿Requiere subsidio de arrendamiento?'), findsOneWidget);

    await avanzarPaso(); // 2 -> 3 (GIS) — el mini-mapa debe construirse sin reventar.
    expect(find.text('Capturar GPS'), findsOneWidget);

    await avanzarPaso(); // 3 -> 4 (Medición)
    final botonAgregarMedicion = find.text('Agregar medición');
    await tester.ensureVisible(botonAgregarMedicion);
    await tester.pumpAndSettle();
    await tester.tap(botonAgregarMedicion);
    await tester.pumpAndSettle();
    expect(find.text('Foto'), findsOneWidget);
    expect(find.text('Guardar expediente completo'), findsWidgets);
  });

  testWidgets('Consultar registros abre sin reventar', (WidgetTester tester) async {
    await tester.pumpWidget(const SigeriaCampoApp());

    await tester.tap(find.text('Consultar registros (ver, editar, eliminar)'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text('Consultar registros'), findsOneWidget); // AppBar
    expect(find.text('Departamento (todos)'), findsOneWidget);
  });
}
