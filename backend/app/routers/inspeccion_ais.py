"""Inspección técnica AIS — "Guía Técnica para la Inspección de Edificaciones
Después de un Sismo" (Asociación Colombiana de Ingeniería Sísmica). Formulario
oficial que usa la Unidad de Gestión del Riesgo (nacional y local); reemplaza
el checklist simplificado de 8 componentes que tenía SIGERIA antes.

Los campos de selección múltiple (instalaciones afectadas, medidas de
seguridad, etc.) se guardan como texto separado por comas en SQLite (no hay
tipo array nativo) y se reconstruyen como lista al leer.
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException

from app.db.database import get_conn, new_uuid, now_iso, row_to_dict
from app.schemas.schemas import InspeccionAisCrear, InspeccionAisOut

router = APIRouter(prefix="/api/inspeccion-ais", tags=["Inspección técnica AIS"])

# Campos que se guardan como CSV en la tabla (listas de selección múltiple).
_CAMPOS_LISTA = [
    "instalaciones_afectadas", "requiere_visita_especializada",
    "recomienda_intervencion", "medidas_seguridad", "desconectar_servicios",
]

# Rangos oficiales de la guía: % de daño global → clasificación (sección
# "Porcentaje de Daños Global de la Edificación"). El 100% ("colapso total")
# se pliega dentro de "severo" para la clasificación de habitabilidad, que
# en el formulario solo tiene 5 categorías (Ninguno/Leve/Moderado/Fuerte/
# Severo), no 6.
def _clasificacion_desde_porcentaje(pct: float) -> str:
    if pct <= 0:
        return "ninguno"
    if pct <= 10:
        return "leve"
    if pct <= 30:
        return "moderado"
    if pct <= 60:
        return "fuerte"
    return "severo"


# Clasificación global del daño -> color de habitabilidad (misma tabla del
# formulario oficial, sección "Clasificación global del daño y habitabilidad
# de la edificación").
_COLOR_HABITABILIDAD = {
    "ninguno": "verde",
    "leve": "verde",
    "moderado": "amarillo",
    "fuerte": "naranja",
    "severo": "rojo",
}

# Puente hacia el campo `nivel_dano_preliminar` de objeto_afectado (usado ya
# por el mapa/estadísticas para colorear puntos) — no tiene "fuerte" como
# categoría propia, así que se aproxima al escalón más cercano.
_NIVEL_DANO_OBJETO = {
    "ninguno": "sin_dano",
    "leve": "leve",
    "moderado": "moderado",
    "fuerte": "severo",
    "severo": "colapso",
}


def _a_fila(payload: InspeccionAisCrear) -> dict:
    datos = payload.model_dump(exclude={"id_objeto"})
    for campo in _CAMPOS_LISTA:
        valor = datos.get(campo)
        datos[campo] = ",".join(valor) if valor else None
    if datos.get("fecha_inspeccion") is not None:
        datos["fecha_inspeccion"] = payload.fecha_inspeccion.isoformat()  # type: ignore[union-attr]

    # Autocompletar clasificación si no vino explícita, siguiendo la misma
    # tabla oficial (% -> clasificación -> color) — igual que
    # `nivel_dano_preliminar` ya se calcula solo del checklist en el cliente,
    # aquí se recalcula en el backend por si el valor no llegó o vino vacío.
    if not datos.get("clasificacion_global_dano") and datos.get("pct_dano_global") is not None:
        datos["clasificacion_global_dano"] = _clasificacion_desde_porcentaje(datos["pct_dano_global"])
    if not datos.get("clasificacion_habitabilidad") and datos.get("clasificacion_global_dano"):
        datos["clasificacion_habitabilidad"] = _COLOR_HABITABILIDAD.get(datos["clasificacion_global_dano"])
    return datos


def _fila_a_salida(row) -> dict:
    fila = row_to_dict(row)
    for campo in _CAMPOS_LISTA:
        fila[campo] = fila[campo].split(",") if fila.get(campo) else []
    return fila


def _sincronizar_objeto_afectado(conn, id_objeto: str, datos: dict) -> None:
    """El mapa y las estadísticas ya leen `nivel_dano_preliminar` y
    `resumen_componentes_dano` de `objeto_afectado` — en vez de duplicar esa
    lógica, la inspección AIS actualiza esos mismos campos con su propia
    clasificación, así todo lo ya construido (colores del mapa, ranking de
    daños) sigue funcionando sin cambios, ahora alimentado por el dato
    oficial en vez del checklist simplificado."""
    clasificacion = datos.get("clasificacion_global_dano")
    if not clasificacion:
        return
    nivel = _NIVEL_DANO_OBJETO.get(clasificacion)
    resumen = (
        f"Inspección AIS — clasificación global: {clasificacion} "
        f"({datos.get('pct_dano_global', '?')}% de daño), "
        f"habitabilidad: {datos.get('clasificacion_habitabilidad', '?')}"
    )
    conn.execute(
        "UPDATE objeto_afectado SET nivel_dano_preliminar=?, resumen_componentes_dano=?, "
        "actualizado_en=? WHERE id_objeto=?",
        (nivel, resumen, now_iso(), id_objeto),
    )


@router.post("", response_model=InspeccionAisOut)
def crear_inspeccion(payload: InspeccionAisCrear):
    with get_conn() as conn:
        existe = conn.execute(
            "SELECT 1 FROM objeto_afectado WHERE id_objeto=?", (payload.id_objeto,)
        ).fetchone()
        if not existe:
            raise HTTPException(404, f"Objeto afectado {payload.id_objeto} no existe")

        datos = _a_fila(payload)
        id_inspeccion = new_uuid()
        columnas = ["id_inspeccion", "id_objeto", *datos.keys()]
        marcadores = ",".join("?" * len(columnas))
        conn.execute(
            f"INSERT INTO inspeccion_ais ({','.join(columnas)}) VALUES ({marcadores})",
            (id_inspeccion, payload.id_objeto, *datos.values()),
        )
        _sincronizar_objeto_afectado(conn, payload.id_objeto, datos)
        conn.execute(
            "INSERT INTO auditoria (tabla, id_registro, accion, usuario_id) VALUES (?,?,?,?)",
            ("inspeccion_ais", id_inspeccion, "crear", payload.creado_por),
        )
        row = conn.execute(
            "SELECT * FROM inspeccion_ais WHERE id_inspeccion=?", (id_inspeccion,)
        ).fetchone()
        return _fila_a_salida(row)


@router.get("/{id_objeto}")
def obtener_inspeccion(id_objeto: str):
    """Devuelve la inspección más reciente de ese objeto (normalmente hay
    una sola). `null` si todavía no se ha hecho ninguna."""
    with get_conn() as conn:
        row = conn.execute(
            "SELECT * FROM inspeccion_ais WHERE id_objeto=? ORDER BY creado_en DESC LIMIT 1",
            (id_objeto,),
        ).fetchone()
        return _fila_a_salida(row) if row else None


@router.put("/{id_inspeccion}", response_model=InspeccionAisOut)
def editar_inspeccion(id_inspeccion: str, payload: InspeccionAisCrear):
    with get_conn() as conn:
        actual = conn.execute(
            "SELECT * FROM inspeccion_ais WHERE id_inspeccion=?", (id_inspeccion,)
        ).fetchone()
        if not actual:
            raise HTTPException(404, "Esa inspección no existe")

        datos = _a_fila(payload)
        asignaciones = ", ".join(f"{c} = ?" for c in datos)
        conn.execute(
            f"UPDATE inspeccion_ais SET {asignaciones}, actualizado_en = ? WHERE id_inspeccion = ?",
            (*datos.values(), now_iso(), id_inspeccion),
        )
        _sincronizar_objeto_afectado(conn, payload.id_objeto, datos)
        row = conn.execute(
            "SELECT * FROM inspeccion_ais WHERE id_inspeccion=?", (id_inspeccion,)
        ).fetchone()
        return _fila_a_salida(row)
