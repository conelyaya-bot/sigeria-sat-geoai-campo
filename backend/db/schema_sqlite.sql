-- SIGERIA — esquema de desarrollo local (SQLite, cero instalación)
-- La geometría se guarda como GeoJSON en TEXT (columna geom_geojson) en vez de tipo geometry real.
-- Mismo patrón que backend_encuestas/db_local.py del proyecto Escuchar Turbo.

CREATE TABLE IF NOT EXISTS usuario (
    id_usuario      TEXT PRIMARY KEY,
    nombre          TEXT NOT NULL,
    rol             TEXT NOT NULL,
    verificado      INTEGER NOT NULL DEFAULT 0,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS evento (
    id_evento       TEXT PRIMARY KEY,
    fenomeno        TEXT NOT NULL,
    fecha_evento    TEXT NOT NULL,
    municipio_divipola TEXT NOT NULL,
    descripcion     TEXT,
    creado_por      TEXT,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS objeto_afectado (
    id_objeto       TEXT PRIMARY KEY,
    id_evento       TEXT NOT NULL REFERENCES evento(id_evento),
    tipo_objeto     TEXT NOT NULL,
    estado_operativo TEXT NOT NULL DEFAULT 'sin_evaluar',
    nivel_dano_preliminar TEXT,
    -- Ubicación detallada del objeto/vivienda (sección 6: "identificar
    -- municipio, zona, barrio/vereda"). Departamento es catálogo cerrado
    -- (33 DANE) en el cliente; aquí se guarda el nombre ya validado.
    departamento    TEXT,
    barrio_vereda   TEXT,
    direccion       TEXT,
    -- Responsable de la recolección (brigadista/encuestador que levanta el dato)
    recolector_nombre     TEXT,
    recolector_documento  TEXT,
    recolector_cargo      TEXT,
    recolector_entidad    TEXT,
    -- Quien entrega la información en la vivienda (beneficiario/informante)
    informante_nombre       TEXT,
    informante_documento    TEXT,
    informante_parentesco   TEXT,   -- relación con el hogar: jefe de hogar, cónyuge, etc.
    informante_telefono     TEXT,
    -- Necesidad específica de vivienda temporal (EDAN — atención humanitaria)
    requiere_subsidio_arrendamiento INTEGER,  -- NULL=sin evaluar, 0=no, 1=sí
    -- Resumen legible de la lista de chequeo por componente (columnas, muros,
    -- cubierta, etc. — sección 8 del documento base). El detalle fila por
    -- fila queda para las tablas Componente/Daño de fase 3 (roadmap); esto
    -- documenta ya la selección sin volver a pedir texto libre.
    resumen_componentes_dano TEXT,
    -- Espacio libre opcional: solo si quien evalúa es ingeniero/a y quiere
    -- detallar por escrito lo evidenciado. No reemplaza la lista de chequeo.
    observaciones_tecnicas TEXT,
    creado_por      TEXT,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now')),
    actualizado_en  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS geometria (
    id_geometria    TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    geom_tipo       TEXT NOT NULL,          -- Point | LineString | Polygon
    geom_geojson    TEXT NOT NULL,          -- geometry GeoJSON como texto, EPSG:4326
    precision_gnss_m REAL,
    fuente_posicion TEXT,
    capturado_en    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS necesidad (
    id_necesidad    TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL,
    estado          TEXT NOT NULL DEFAULT 'abierta',
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS evidencia (
    id_evidencia    TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL,
    url_almacenamiento TEXT NOT NULL,
    usuario_id      TEXT,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS medicion (
    id_medicion     TEXT PRIMARY KEY,
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL,
    valor           REAL NOT NULL,
    unidad          TEXT NOT NULL,
    metodo          TEXT NOT NULL,
    precision_categoria TEXT NOT NULL,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS auditoria (
    id_auditoria    INTEGER PRIMARY KEY AUTOINCREMENT,
    tabla           TEXT NOT NULL,
    id_registro     TEXT NOT NULL,
    accion          TEXT NOT NULL,
    usuario_id      TEXT,
    detalle         TEXT,
    creado_en       TEXT NOT NULL DEFAULT (datetime('now'))
);
