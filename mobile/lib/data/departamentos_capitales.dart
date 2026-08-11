/// Coordenadas aproximadas de la capital de cada departamento — se usan
/// SOLO como referencia inicial para centrar el mapa apenas el usuario elige
/// el departamento (antes de tener el punto GPS real). En cuanto se captura
/// el GPS real (paso 3), ese punto reemplaza esta referencia.
library departamentos_capitales;

/// {lat, lon} por nombre de departamento (mismo texto que colombia_departamentos.dart).
const Map<String, List<double>> capitalesPorDepartamento = {
  'Antioquia': [6.2442, -75.5812], // Medellín
  'Atlántico': [10.9639, -74.7964], // Barranquilla
  'Bogotá D.C.': [4.7110, -74.0721],
  'Bolívar': [10.3910, -75.4794], // Cartagena
  'Boyacá': [5.5353, -73.3678], // Tunja
  'Caldas': [5.0689, -75.5174], // Manizales
  'Caquetá': [1.6144, -75.6062], // Florencia
  'Cauca': [2.4448, -76.6147], // Popayán
  'Cesar': [10.4631, -73.2532], // Valledupar
  'Córdoba': [8.7479, -75.8814], // Montería
  'Cundinamarca': [4.7110, -74.0721], // Bogotá (sede admin)
  'Chocó': [5.6947, -76.6413], // Quibdó
  'Huila': [2.9273, -75.2819], // Neiva
  'La Guajira': [11.5444, -72.9072], // Riohacha
  'Magdalena': [11.2408, -74.1990], // Santa Marta
  'Meta': [4.1420, -73.6266], // Villavicencio
  'Nariño': [1.2136, -77.2811], // Pasto
  'Norte de Santander': [7.8939, -72.5078], // Cúcuta
  'Quindío': [4.5339, -75.6811], // Armenia
  'Risaralda': [4.8087, -75.6906], // Pereira
  'Santander': [7.1193, -73.1227], // Bucaramanga
  'Sucre': [9.3047, -75.3978], // Sincelejo
  'Tolima': [4.4389, -75.2322], // Ibagué
  'Valle del Cauca': [3.4516, -76.5320], // Cali
  'Arauca': [7.0847, -70.7591], // Arauca
  'Casanare': [5.3378, -72.3959], // Yopal
  'Putumayo': [1.1497, -76.6478], // Mocoa
  'Archipiélago de San Andrés, Providencia y Santa Catalina': [12.5847, -81.7006],
  'Amazonas': [-4.2000, -69.9407], // Leticia
  'Guainía': [3.8653, -67.9239], // Inírida
  'Guaviare': [2.0653, -72.6396], // San José del Guaviare
  'Vaupés': [1.2536, -70.2336], // Mitú
  'Vichada': [4.4234, -69.5836], // Puerto Carreño
};
