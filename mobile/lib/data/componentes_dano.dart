/// Lista de chequeo de componentes constructivos — sección 8 del documento
/// base ("Módulo de edificaciones e inspección por componentes").
///
/// Reemplaza la descripción libre del daño: la persona que levanta el dato
/// casi nunca es ingeniera y no sabe redactar un diagnóstico técnico — pero
/// SÍ puede mirar la vivienda y marcar qué componente ve afectado y qué tan
/// grave se ve. El nivel de daño preliminar del expediente se calcula solo,
/// tomando el peor componente marcado (ver `_calcularNivelDano` en
/// `nuevo_expediente_screen.dart`).
library componentes_dano;

const List<Map<String, String>> componentesDano = [
  {'id': 'cimentacion', 'nombre': 'Terreno y cimentación'},
  {'id': 'columnas', 'nombre': 'Columnas'},
  {'id': 'vigas', 'nombre': 'Vigas'},
  {'id': 'muros', 'nombre': 'Muros / mampostería'},
  {'id': 'losas', 'nombre': 'Losas y entrepisos'},
  {'id': 'escaleras', 'nombre': 'Escaleras / rutas de evacuación'},
  {'id': 'cubierta', 'nombre': 'Cubierta / techo'},
  {'id': 'no_estructural', 'nombre': 'Elementos no estructurales (fachadas, vidrios, cielorrasos)'},
];

/// Escala de severidad por componente, alineada con el campo backend
/// `nivel_dano_preliminar` (sin_dano|leve|moderado|severo|colapso) pero con
/// etiquetas que cualquier persona entiende sin ser ingeniera — referencia
/// conceptual NSR-10 (daño no estructural / estructural / colapso).
const List<Map<String, String>> severidadComponente = [
  {'valor': 'sin_dano', 'etiqueta': 'Sin daño visible'},
  {'valor': 'leve', 'etiqueta': 'Leve (grietas finas, cosmético)'},
  {'valor': 'moderado', 'etiqueta': 'Parcial — no estructural'},
  {'valor': 'severo', 'etiqueta': 'Estructural (compromete la resistencia)'},
  {'valor': 'colapso', 'etiqueta': 'Colapso / destrucción total'},
];

/// Orden de gravedad para calcular el peor caso (índice mayor = más grave).
const List<String> ordenSeveridad = ['sin_dano', 'leve', 'moderado', 'severo', 'colapso'];
