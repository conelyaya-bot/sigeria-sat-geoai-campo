/// Opciones del formulario oficial AIS ("Guía Técnica para la Inspección de
/// Edificaciones Después de un Sismo", Asociación Colombiana de Ingeniería
/// Sísmica) — mismos valores y orden que el formulario en papel de 2
/// páginas que usa la Unidad de Gestión del Riesgo. Cada lista es
/// `[{'valor': ..., 'etiqueta': ...}]`, mismo patrón que
/// `componentes_dano.dart`.
library;

const tiposVia = [
  {'valor': 'carrera', 'etiqueta': 'Carrera'},
  {'valor': 'calle', 'etiqueta': 'Calle'},
  {'valor': 'transv', 'etiqueta': 'Transversal'},
  {'valor': 'diag', 'etiqueta': 'Diagonal'},
  {'valor': 'avda', 'etiqueta': 'Avenida'},
  {'valor': 'otro', 'etiqueta': 'Otro'},
];

const inspeccionTipos = [
  {'valor': 'exterior_interior', 'etiqueta': 'Exterior e interior'},
  {'valor': 'no_se_pudo_entrar', 'etiqueta': 'No se pudo entrar'},
];

const usosPredominantes = [
  {'valor': 'residencial', 'etiqueta': 'Residencial'},
  {'valor': 'comercial', 'etiqueta': 'Comercial'},
  {'valor': 'educacional', 'etiqueta': 'Educacional'},
  {'valor': 'salud', 'etiqueta': 'Salud'},
  {'valor': 'hotelero', 'etiqueta': 'Hotelero'},
  {'valor': 'oficinas', 'etiqueta': 'Oficinas'},
  {'valor': 'industrial', 'etiqueta': 'Industrial'},
  {'valor': 'institucional', 'etiqueta': 'Institucional'},
  {'valor': 'bodegas', 'etiqueta': 'Bodegas'},
  {'valor': 'estacionamientos', 'etiqueta': 'Estacionamientos'},
  {'valor': 'otros', 'etiqueta': 'Otros'},
];

const sistemasEstructurales = [
  {'valor': '11_portico_concreto', 'etiqueta': 'Concreto reforzado — Pórtico'},
  {'valor': '12_muros_estructurales', 'etiqueta': 'Concreto reforzado — Muros estructurales'},
  {'valor': '13_sistemas_duales', 'etiqueta': 'Concreto reforzado — Sistemas duales'},
  {'valor': '14_prefabricados', 'etiqueta': 'Concreto reforzado — Prefabricados'},
  {'valor': '21_mamposteria_confinada', 'etiqueta': 'Mampostería confinada'},
  {'valor': '22_mamposteria_reforzada', 'etiqueta': 'Mampostería reforzada'},
  {'valor': '23_mamposteria_no_reforzada', 'etiqueta': 'Mampostería no reforzada'},
  {'valor': '31_porticos_arriostrados', 'etiqueta': 'Acero — Pórticos arriostrados'},
  {'valor': '32_porticos_no_arriostrados', 'etiqueta': 'Acero — Pórticos no arriostrados'},
  {'valor': '41_porticos_paneles_madera', 'etiqueta': 'Madera — Pórticos y paneles en madera'},
  {'valor': '42_porticos_madera_paneles_otros', 'etiqueta': 'Madera — Pórticos en madera, paneles en otro material'},
  {'valor': '51_muros_bahareque', 'etiqueta': 'Bahareque o tapia — Muros en bahareque'},
  {'valor': '52_muros_tapia', 'etiqueta': 'Bahareque o tapia — Muros en tapia'},
  {'valor': '50_mixta', 'etiqueta': 'Mixta'},
  {'valor': '60_otros', 'etiqueta': 'Otros'},
];

const tiposEntrepiso = [
  {'valor': '11_placa_maciza', 'etiqueta': 'Concreto reforzado — Placa maciza'},
  {'valor': '12_placa_aligerada', 'etiqueta': 'Concreto reforzado — Placa aligerada'},
  {'valor': '13_reticular_celulado', 'etiqueta': 'Concreto reforzado — Reticular celulado'},
  {'valor': '21_lamina_colaborante', 'etiqueta': 'Acero — Lámina colaborante (steel deck)'},
  {'valor': '22_vigas_acero', 'etiqueta': 'Acero — Vigas'},
  {'valor': '23_cerchas', 'etiqueta': 'Acero — Cerchas'},
  {'valor': '31_vigas_madera', 'etiqueta': 'Madera — Vigas'},
  {'valor': '32_mixta_madera', 'etiqueta': 'Madera — Mixta'},
  {'valor': '40_otros', 'etiqueta': 'Otros'},
];

const aniosConstruccion = [
  {'valor': 'antes_1930', 'etiqueta': 'Antes de 1930'},
  {'valor': '1930_1984', 'etiqueta': '1930 a 1984'},
  {'valor': '1985_1997', 'etiqueta': '1985 a 1997'},
  {'valor': 'desde_1998', 'etiqueta': 'A partir de 1998'},
];

const siNoIndeterminado = [
  {'valor': 'si', 'etiqueta': 'Sí'},
  {'valor': 'no', 'etiqueta': 'No'},
  {'valor': 'no_determinado', 'etiqueta': 'No se pudo determinar'},
];

const existeColapsoOpciones = [
  {'valor': 'no', 'etiqueta': 'No'},
  {'valor': 'parcial', 'etiqueta': 'Parcial'},
  {'valor': 'total', 'etiqueta': 'Total'},
];

/// Grado de daño oficial AIS — distinto del checklist simplificado anterior
/// (ese tenía "no_aplica"/"sin_dano"/...; este sigue exacto al formulario:
/// Ninguno/Leve/Moderado/Fuerte/Severo).
const gradoDanoAis = [
  {'valor': 'ninguno', 'etiqueta': 'Ninguno'},
  {'valor': 'leve', 'etiqueta': 'Leve'},
  {'valor': 'moderado', 'etiqueta': 'Moderado'},
  {'valor': 'fuerte', 'etiqueta': 'Fuerte'},
  {'valor': 'severo', 'etiqueta': 'Severo'},
];
const ordenGradoDanoAis = ['ninguno', 'leve', 'moderado', 'fuerte', 'severo'];

const instalacionesOpciones = [
  {'valor': 'acueducto', 'etiqueta': 'Acueducto'},
  {'valor': 'alcantarillado', 'etiqueta': 'Alcantarillado'},
  {'valor': 'energia', 'etiqueta': 'Energía'},
  {'valor': 'gas', 'etiqueta': 'Gas'},
];

const nivelPuntualGeneral = [
  {'valor': 'no', 'etiqueta': 'No'},
  {'valor': 'puntual', 'etiqueta': 'Puntual'},
  {'valor': 'general', 'etiqueta': 'General'},
];

const visitaEspecializadaOpciones = [
  {'valor': 'estructural', 'etiqueta': 'Estructural'},
  {'valor': 'geotecnico', 'etiqueta': 'Geotécnico'},
  {'valor': 'servicios_publicos', 'etiqueta': 'Servicios públicos'},
];

const intervencionOpciones = [
  {'valor': 'planeacion_control_fisico', 'etiqueta': 'Planeación — Control físico'},
  {'valor': 'policia_ejercito', 'etiqueta': 'Policía — Ejército'},
  {'valor': 'transito', 'etiqueta': 'Tránsito'},
  {'valor': 'bomberos_rescate', 'etiqueta': 'Bomberos — Entidades de rescate'},
];

const medidasSeguridadOpciones = [
  {'valor': 'restringir_paso_peatones', 'etiqueta': 'Restringir paso de peatones'},
  {'valor': 'restringir_trafico_vehicular', 'etiqueta': 'Restringir tráfico vehicular'},
  {'valor': 'evacuar_parcial', 'etiqueta': 'Evacuar parcialmente la edificación'},
  {'valor': 'evacuar_total', 'etiqueta': 'Evacuar totalmente la edificación'},
  {'valor': 'manejo_sustancias_peligrosas', 'etiqueta': 'Manejo de sustancias peligrosas'},
  {'valor': 'apuntalar', 'etiqueta': 'Apuntalar'},
  {'valor': 'demoler_elementos_peligro', 'etiqueta': 'Demoler elementos en peligro de caer'},
  {'valor': 'evacuar_edificaciones_vecinas', 'etiqueta': 'Evacuar edificaciones vecinas'},
];

const serviciosDesconectarOpciones = [
  {'valor': 'energia', 'etiqueta': 'Energía'},
  {'valor': 'gas', 'etiqueta': 'Gas'},
  {'valor': 'agua', 'etiqueta': 'Agua'},
];

const calidadBuenaRegularMala = [
  {'valor': 'buena', 'etiqueta': 'Buena'},
  {'valor': 'regular', 'etiqueta': 'Regular'},
  {'valor': 'mala', 'etiqueta': 'Mala'},
];

const posicionManzanaOpciones = [
  {'valor': 'esquina', 'etiqueta': 'Esquina'},
  {'valor': 'intermedia', 'etiqueta': 'Intermedia'},
  {'valor': 'libre_un_costado', 'etiqueta': 'Libre por un costado'},
  {'valor': 'libre_dos_costados', 'etiqueta': 'Libre por dos costados'},
];

const huboReparacionOpciones = [
  {'valor': 'total', 'etiqueta': 'Total'},
  {'valor': 'parcial', 'etiqueta': 'Parcial'},
  {'valor': 'ninguna', 'etiqueta': 'Ninguna'},
  {'valor': 'no_determinado', 'etiqueta': 'No se pudo determinar'},
];

// --- Campos agregados al revisar la guía IDIGER 2018 (4ta edición, la más
// reciente confirmada) — más completa que la primera versión implementada.

const siNoOpciones = [
  {'valor': 'si', 'etiqueta': 'Sí'},
  {'valor': 'no', 'etiqueta': 'No'},
];

const edificioVecinoCriticoOpciones = [
  {'valor': 'no', 'etiqueta': 'No'},
  {'valor': 'si', 'etiqueta': 'Sí'},
  {'valor': 'no_determinado', 'etiqueta': 'No se pudo determinar'},
];

const grietasTerrenoOpciones = [
  {'valor': 'no', 'etiqueta': 'No'},
  {'valor': 'incipientes', 'etiqueta': 'Incipientes'},
  {'valor': 'generalizadas', 'etiqueta': 'Generalizadas'},
];

const tipoSueloOpciones = [
  {'valor': 'duro', 'etiqueta': 'Duro'},
  {'valor': 'medio', 'etiqueta': 'Medio'},
  {'valor': 'blando', 'etiqueta': 'Blando'},
];

const tipoCimentacionOpciones = [
  {'valor': 'superficial', 'etiqueta': 'Superficial'},
  {'valor': 'profunda', 'etiqueta': 'Profunda'},
  {'valor': 'no_determinado', 'etiqueta': 'No se pudo determinar'},
];

const calidadCimentacionOpciones = [
  {'valor': 'buena', 'etiqueta': 'Buena'},
  {'valor': 'regular', 'etiqueta': 'Regular'},
  {'valor': 'mala', 'etiqueta': 'Mala'},
  {'valor': 'no_determinado', 'etiqueta': 'No se pudo determinar'},
];

const condicionesTopograficasOpciones = [
  {'valor': 'plano', 'etiqueta': 'Plano'},
  {'valor': 'cresta', 'etiqueta': 'Cresta'},
  {'valor': 'ladera', 'etiqueta': 'Ladera'},
  {'valor': 'pie_de_ladera', 'etiqueta': 'Pie de ladera'},
  {'valor': 'valle', 'etiqueta': 'Valle'},
  {'valor': 'borde_canal_rio_lago', 'etiqueta': 'Borde de canal, río o lago'},
];

const tipoCubiertaOpciones = [
  {'valor': 'maciza', 'etiqueta': 'Maciza'},
  {'valor': 'liviana', 'etiqueta': 'Liviana'},
];

const evidenciaAnclajeOpciones = [
  {'valor': 'si', 'etiqueta': 'Sí'},
  {'valor': 'no', 'etiqueta': 'No'},
  {'valor': 'no_sabe', 'etiqueta': 'No se sabe'},
];

const huboMuertosHeridosOpciones = [
  {'valor': 'no', 'etiqueta': 'No'},
  {'valor': 'si', 'etiqueta': 'Sí'},
  {'valor': 'no_se_sabe', 'etiqueta': 'No se sabe'},
];

/// Clasificación global del daño (%) → color de habitabilidad, EXACTA al
/// formulario oficial (sección "Clasificación global del daño y
/// habitabilidad de la edificación"). Se usa para calcular en el cliente lo
/// mismo que el backend recalcula por si acaso — mostrarlo de una vez ayuda
/// a que quien inspecciona vea el resultado sin esperar la respuesta del
/// servidor.
String clasificacionDesdeporcentaje(double pct) {
  if (pct <= 0) return 'ninguno';
  if (pct <= 10) return 'leve';
  if (pct <= 30) return 'moderado';
  if (pct <= 60) return 'fuerte';
  return 'severo';
}

const Map<String, String> colorHabitabilidad = {
  'ninguno': 'verde',
  'leve': 'verde',
  'moderado': 'amarillo',
  'fuerte': 'naranja',
  'severo': 'rojo',
};

const Map<String, String> etiquetaHabitabilidad = {
  'verde': 'Habitable (verde)',
  'amarillo': 'Uso restringido (amarillo)',
  'naranja': 'No habitable (naranja)',
  'rojo': 'Peligro de colapso (rojo)',
};

/// Etiqueta corta para cada una de las 5 sub-clasificaciones A-E que
/// calcula el backend (sección 2.9 de la guía IDIGER 2018 — la
/// habitabilidad final es la más conservadora de las 5).
const Map<String, String> etiquetaClasificacionAbcde = {
  'habitable': 'Habitable',
  'uso_restringido': 'Uso restringido',
  'no_habitable': 'No habitable',
  'peligro_colapso': 'Peligro de colapso',
};
