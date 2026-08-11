"""Esquemas Pydantic — contratos de la API de SIGERIA (módulos MVP 1-4)."""
from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, Field

Fenomeno = Literal[
    "sismo", "inundacion", "deslizamiento", "vendaval",
    "incendio", "erosion_socavacion", "creciente_subita", "otro",
]
EstadoOperativo = Literal["operativo", "parcial", "fuera_de_servicio", "sin_evaluar"]
NivelDano = Literal["sin_dano", "leve", "moderado", "severo", "colapso"]
TipoGeom = Literal["Point", "LineString", "Polygon"]
FuentePosicion = Literal["gnss_interno", "gnss_externo", "manual"]
TipoMedicion = Literal["distancia", "area", "pendiente", "altura", "grieta"]
MetodoMedicion = Literal["sensor_telefono", "equipo_externo"]
PrecisionCategoria = Literal["orientativa", "certificada"]
TipoNecesidad = Literal["agua", "alimento", "refugio", "salud", "otro"]


# --- Módulo 1: Evento y objetos -------------------------------------------------

class EventoCrear(BaseModel):
    fenomeno: Fenomeno
    fecha_evento: datetime
    municipio_divipola: str = Field(..., description="Código DIVIPOLA del municipio")
    descripcion: Optional[str] = None
    creado_por: Optional[str] = None


class EventoOut(EventoCrear):
    id_evento: str
    creado_en: str


class ObjetoAfectadoCrear(BaseModel):
    id_evento: str
    tipo_objeto: str
    estado_operativo: EstadoOperativo = "sin_evaluar"
    nivel_dano_preliminar: Optional[NivelDano] = None
    # Ubicación detallada (sección 6 del documento base)
    departamento: Optional[str] = None
    barrio_vereda: Optional[str] = None
    direccion: Optional[str] = None
    # Responsable de la recolección — obligatorio para trazabilidad y para
    # que el dato sea entregable ante UNGRD/departamento/municipio.
    recolector_nombre: Optional[str] = None
    recolector_documento: Optional[str] = None
    recolector_cargo: Optional[str] = None
    recolector_entidad: Optional[str] = None
    # Informante en la vivienda (beneficiario)
    informante_nombre: Optional[str] = None
    informante_documento: Optional[str] = None
    informante_parentesco: Optional[str] = None
    informante_telefono: Optional[str] = None
    requiere_subsidio_arrendamiento: Optional[bool] = None
    resumen_componentes_dano: Optional[str] = None
    creado_por: Optional[str] = None


class ObjetoAfectadoOut(BaseModel):
    id_objeto: str
    id_evento: str
    tipo_objeto: str
    estado_operativo: EstadoOperativo
    nivel_dano_preliminar: Optional[NivelDano] = None
    departamento: Optional[str] = None
    barrio_vereda: Optional[str] = None
    direccion: Optional[str] = None
    recolector_nombre: Optional[str] = None
    recolector_documento: Optional[str] = None
    recolector_cargo: Optional[str] = None
    recolector_entidad: Optional[str] = None
    informante_nombre: Optional[str] = None
    informante_documento: Optional[str] = None
    informante_parentesco: Optional[str] = None
    informante_telefono: Optional[str] = None
    requiere_subsidio_arrendamiento: Optional[bool] = None
    resumen_componentes_dano: Optional[str] = None
    creado_en: str
    actualizado_en: str


# --- Módulo 2: EDAN básico adaptativo -------------------------------------------

class NecesidadCrear(BaseModel):
    id_objeto: str
    tipo: TipoNecesidad


class NecesidadOut(NecesidadCrear):
    id_necesidad: str
    estado: str
    creado_en: str


class EvidenciaCrear(BaseModel):
    id_objeto: str
    tipo: Literal["foto", "video", "croquis", "escaneo3d"]
    url_almacenamiento: str
    usuario_id: Optional[str] = None
    # Contenido real de la imagen en base64 (opcional). Si viene, el backend
    # la guarda de verdad en disco (workspace/evidencias/) y el reporte PDF
    # puede mostrarla en un recuadro real, no solo el nombre del archivo.
    contenido_base64: Optional[str] = None


class EvidenciaOut(EvidenciaCrear):
    id_evidencia: str
    creado_en: str


# --- Módulo 3: GIS offline -------------------------------------------------------

class GeometriaCrear(BaseModel):
    id_objeto: str
    geom_tipo: TipoGeom
    geom_geojson: dict = Field(..., description="Geometry GeoJSON, EPSG:4326")
    precision_gnss_m: Optional[float] = None
    fuente_posicion: FuentePosicion = "gnss_interno"


class GeometriaOut(GeometriaCrear):
    id_geometria: str
    capturado_en: str


# --- Módulo 4: Medición móvil -----------------------------------------------------

class MedicionCrear(BaseModel):
    id_objeto: str
    tipo: TipoMedicion
    valor: float
    unidad: str
    metodo: MetodoMedicion
    precision_categoria: PrecisionCategoria


class MedicionOut(MedicionCrear):
    id_medicion: str
    creado_en: str
