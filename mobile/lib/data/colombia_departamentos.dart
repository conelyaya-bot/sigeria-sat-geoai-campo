/// Catálogo real de departamentos de Colombia (DANE/DIVIPOLA, 33 unidades:
/// 32 departamentos + Bogotá D.C.). Se usa en el formulario adaptativo para
/// el campo "Departamento" (sección 6 del documento base: "identificar
/// municipio, zona, barrio/vereda y código territorial").
///
/// El municipio, barrio/corregimiento/vereda y dirección se llenan
/// manualmente (pedido explícito del usuario) — cargar los 1.122 municipios
/// de Colombia como catálogo cerrado queda para una fase posterior.
library colombia_departamentos;

const List<Map<String, String>> departamentosColombia = [
  {"codigo": "05", "nombre": "Antioquia"},
  {"codigo": "08", "nombre": "Atlántico"},
  {"codigo": "11", "nombre": "Bogotá D.C."},
  {"codigo": "13", "nombre": "Bolívar"},
  {"codigo": "15", "nombre": "Boyacá"},
  {"codigo": "17", "nombre": "Caldas"},
  {"codigo": "18", "nombre": "Caquetá"},
  {"codigo": "19", "nombre": "Cauca"},
  {"codigo": "20", "nombre": "Cesar"},
  {"codigo": "23", "nombre": "Córdoba"},
  {"codigo": "25", "nombre": "Cundinamarca"},
  {"codigo": "27", "nombre": "Chocó"},
  {"codigo": "41", "nombre": "Huila"},
  {"codigo": "44", "nombre": "La Guajira"},
  {"codigo": "47", "nombre": "Magdalena"},
  {"codigo": "50", "nombre": "Meta"},
  {"codigo": "52", "nombre": "Nariño"},
  {"codigo": "54", "nombre": "Norte de Santander"},
  {"codigo": "63", "nombre": "Quindío"},
  {"codigo": "66", "nombre": "Risaralda"},
  {"codigo": "68", "nombre": "Santander"},
  {"codigo": "70", "nombre": "Sucre"},
  {"codigo": "73", "nombre": "Tolima"},
  {"codigo": "76", "nombre": "Valle del Cauca"},
  {"codigo": "81", "nombre": "Arauca"},
  {"codigo": "85", "nombre": "Casanare"},
  {"codigo": "86", "nombre": "Putumayo"},
  {"codigo": "88", "nombre": "Archipiélago de San Andrés, Providencia y Santa Catalina"},
  {"codigo": "91", "nombre": "Amazonas"},
  {"codigo": "94", "nombre": "Guainía"},
  {"codigo": "95", "nombre": "Guaviare"},
  {"codigo": "97", "nombre": "Vaupés"},
  {"codigo": "99", "nombre": "Vichada"},
];
