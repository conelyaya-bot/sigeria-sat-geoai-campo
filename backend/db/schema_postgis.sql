-- SIGERIA — esquema de producción (PostgreSQL + PostGIS)
-- Requiere: CREATE EXTENSION IF NOT EXISTS postgis;

CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE usuario (
    id_usuario      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nombre          TEXT NOT NULL,
    rol             TEXT NOT NULL CHECK (rol IN (
                        'ciudadania','brigadista','organismo_respuesta','profesional',
                        'especialista','sector','coordinador','administrador')),
    verificado      BOOLEAN NOT NULL DEFAULT FALSE,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE evento (
    id_evento       TEXT PRIMARY KEY,               -- SIGERIA-EVT-<AAAA>-<NNNN>
    fenomeno        TEXT NOT NULL CHECK (fenomeno IN (
                        'sismo','inundacion','deslizamiento','vendaval','incendio',
                        'erosion_socavacion','creciente_subita','otro')),
    fecha_evento    TIMESTAMPTZ NOT NULL,
    municipio_divipola TEXT NOT NULL,
    descripcion     TEXT,
    creado_por      UUID REFERENCES usuario(id_usuario),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE objeto_afectado (
    id_objeto       TEXT PRIMARY KEY,                -- SIGERIA-CHO-DIVIPOLA-FEN-AAAA-NNNNNN
    id_evento       TEXT NOT NULL REFERENCES evento(id_evento),
    tipo_objeto     TEXT NOT NULL,                    -- vivienda, salud, educacion, via, puente...
    estado_operativo TEXT NOT NULL DEFAULT 'sin_evaluar'
                        CHECK (estado_operativo IN ('operativo','parcial','fuera_de_servicio','sin_evaluar')),
    nivel_dano_preliminar TEXT CHECK (nivel_dano_preliminar IN
                        ('sin_dano','leve','moderado','severo','colapso')),
    -- Ubicación detallada del objeto/vivienda (sección 6 del documento base)
    departamento    TEXT,
    barrio_vereda   TEXT,
    direccion       TEXT,
    -- Responsable de la recolección (brigadista/encuestador)
    recolector_nombre     TEXT,
    recolector_documento  TEXT,
    recolector_cargo      TEXT,
    recolector_entidad    TEXT,
    -- Informante en la vivienda (beneficiario que entrega la información)
    informante_nombre       TEXT,
    informante_documento    TEXT,
    informante_parentesco   TEXT,
    informante_telefono     TEXT,
    -- Necesidad de vivienda temporal (atención humanitaria)
    requiere_subsidio_arrendamiento BOOLEAN,
    -- Resumen legible de la lista de chequeo por componente (sección 8)
    resumen_componentes_dano TEXT,
    -- Espacio libre opcional: solo si quien evalúa es ingeniero/a y quiere
    -- detallar por escrito lo evidenciado. No reemplaza la lista de chequeo.
    observaciones_tecnicas TEXT,
    -- Personas del hogar afectadas por el evento (sección 26: indicadores de
    -- afectados) — se capturaba en el formulario pero no se guardaba.
    personas_afectadas INTEGER,
    creado_por      UUID REFERENCES usuario(id_usuario),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now(),
    actualizado_en  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Detalle fila por fila de la lista de chequeo de componentes — permite
-- calcular de verdad "qué componentes se dañan más" en estadísticas.
CREATE TABLE componente_dano_detalle (
    id_detalle      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    componente      TEXT NOT NULL,
    severidad       TEXT NOT NULL CHECK (severidad IN
                        ('no_aplica','sin_dano','leve','moderado','severo','colapso')),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_componente_dano_objeto ON componente_dano_detalle (id_objeto);

CREATE TABLE geometria (
    id_geometria    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    geom            geometry(Geometry, 4326) NOT NULL,   -- point | linestring | polygon
    precision_gnss_m REAL,
    fuente_posicion TEXT CHECK (fuente_posicion IN ('gnss_interno','gnss_externo','manual')),
    capturado_en    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_geometria_geom ON geometria USING GIST (geom);

CREATE TABLE necesidad (
    id_necesidad    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL,        -- agua, alimento, refugio, salud, otro
    estado          TEXT NOT NULL DEFAULT 'abierta' CHECK (estado IN ('abierta','atendida','cerrada')),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE evidencia (
    id_evidencia    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL CHECK (tipo IN ('foto','video','croquis','escaneo3d')),
    url_almacenamiento TEXT NOT NULL,
    usuario_id      UUID REFERENCES usuario(id_usuario),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE medicion (
    id_medicion     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    id_objeto       TEXT NOT NULL REFERENCES objeto_afectado(id_objeto),
    tipo            TEXT NOT NULL CHECK (tipo IN ('distancia','area','pendiente','altura','grieta')),
    valor           REAL NOT NULL,
    unidad          TEXT NOT NULL,
    metodo          TEXT NOT NULL CHECK (metodo IN ('sensor_telefono','equipo_externo')),
    precision_categoria TEXT NOT NULL CHECK (precision_categoria IN ('orientativa','certificada')),
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE auditoria (
    id_auditoria    BIGSERIAL PRIMARY KEY,
    tabla           TEXT NOT NULL,
    id_registro     TEXT NOT NULL,
    accion          TEXT NOT NULL CHECK (accion IN ('crear','modificar','validar','sincronizar','cerrar')),
    usuario_id      UUID REFERENCES usuario(id_usuario),
    detalle         JSONB,
    creado_en       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Vista de conveniencia para el dashboard web (mapa de eventos)
CREATE VIEW v_mapa_objetos AS
SELECT o.id_objeto, o.tipo_objeto, o.estado_operativo, o.nivel_dano_preliminar,
       e.fenomeno, e.municipio_divipola, e.fecha_evento, g.geom, g.precision_gnss_m
FROM objeto_afectado o
JOIN evento e ON e.id_evento = o.id_evento
LEFT JOIN geometria g ON g.id_objeto = o.id_objeto;
