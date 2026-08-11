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
    expect(find.text('1. Evento y objeto'), findsOneWidget);
    expect(find.text('2. EDAN básico adaptativo'), findsOneWidget);
    expect(find.text('3. GIS — ubicación real'), findsOneWidget);
    expect(find.text('4. Medición móvil'), findsOneWidget);
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

    // Avanza al paso 2 (EDAN) — mismo expediente, sin volver a preguntar nada del paso 1.
    // El Stepper de Material arma los controles de los 4 pasos en el árbol de widgets
    // (no solo el activo); el primero corresponde al paso visible/activo actual.
    final botonSiguiente = find.text('Siguiente').first;
    await tester.ensureVisible(botonSiguiente);
    await tester.pumpAndSettle();
    await tester.tap(botonSiguiente);
    await tester.pumpAndSettle();

    // Paso 2 (EDAN): checklist por componente, NO descripción libre.
    expect(find.text('¿Requiere subsidio de arrendamiento?'), findsOneWidget);
    expect(find.text('Terreno y cimentación'), findsOneWidget);
    expect(find.text('Columnas'), findsOneWidget);
    expect(find.text('Muros / mampostería'), findsOneWidget);
    expect(find.text('Cubierta / techo'), findsOneWidget);
    expect(find.text('Nivel de daño preliminar (calculado)'), findsOneWidget);
    expect(find.text('Descripción del daño'), findsNothing); // ya no existe texto libre

    // Avanza al paso 3 (GIS) — el mini-mapa debe construirse sin reventar.
    final siguiente2 = find.text('Siguiente').first;
    await tester.ensureVisible(siguiente2);
    await tester.pumpAndSettle();
    await tester.tap(siguiente2);
    await tester.pumpAndSettle();
    expect(find.text('Capturar GPS'), findsOneWidget);

    // Avanza al paso 4 (Medición) y agrega una medición con su botón de foto.
    final siguiente3 = find.text('Siguiente').first;
    await tester.ensureVisible(siguiente3);
    await tester.pumpAndSettle();
    await tester.tap(siguiente3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar medición'));
    await tester.pumpAndSettle();
    expect(find.text('Foto'), findsOneWidget);
    expect(find.text('Guardar expediente completo'), findsWidgets);
  });
}
