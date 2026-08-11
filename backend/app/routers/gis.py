"""Módulo MVP 3: GIS offline — captura de geometría + exportación GeoJSON para el mapa web/QGIS."""
from __future__ import annotations

import json

from fastapi import APIRouter, HTTPException

from app.db.database import get_conn, new_uuid, row_to_dict
from app.schemas.schemas import GeometriaCrear, GeometriaOut

router = APIRouter(prefix="/api/gis", tags=["3. GIS offline"])


@router.post("/geometrias", response_model=GeometriaOut)
def crear_geometria(payload: GeometriaCrear):
    with get_conn() as conn:
        existe = conn.execute(
            "SELECT 1 FROM objeto_afectado WHERE id_objeto=?", (payload.id_objeto,)
        ).fetchone()
        if not existe:
            raise HTTPException(404, f"Objeto afectado {payload.id_objeto} no existe")

        if payload.precision_gnss_m is not None and payload.precision_gnss_m > 15:
            # Regla de calidad sección 21 del documento: advertir, no bloquear.
            pass

        id_geometria = new_uuid()
        conn.execute(
            """INSERT INTO geometria
               (id_geometria, id_objeto, geom_tipo, geom_geojson, precision_gnss_m, fuente_posicion)
               VALUES (?,?,?,?,?,?)""",
            (id_geometria, payload.id_objeto, payload.geom_tipo,
             json.dumps(payload.geom_geojson), payload.precision_gnss_m, payload.fuente_posicion),
        )
        row = conn.execute(
            "SELECT * FROM geometria WHERE id_geometria=?", (id_geometria,)
        ).fetchone()
        out = row_to_dict(row)
        out["geom_geojson"] = json.loads(out["geom_geojson"])
        return out


@router.get("/geojson_general")
def exportar_geojson_general(departamento: str | None = None, municipio_divipola: str | None = None):
    """FeatureCollection de TODOS los objetos afectados de TODOS los eventos —
    la 'malla de puntos' que se va llenando en tiempo real a medida que las
    brigadas guardan expedientes, sin importar a qué evento pertenezcan.
    Si se elige departamento/municipio en el visor del mapa, filtra a esa
    zona en vez de mostrar el país entero mezclado."""
    condiciones, params = [], []
    if departamento:
        condiciones.append("o.departamento = ?")
        params.append(departamento)
    if municipio_divipola:
        condiciones.append("e.municipio_divipola = ?")
        params.append(municipio_divipola)
    where = (" WHERE " + " AND ".join(condiciones)) if condiciones else ""

    with get_conn() as conn:
        rows = conn.execute(
            f"""SELECT o.id_objeto, o.tipo_objeto, o.estado_operativo, o.nivel_dano_preliminar,
                      o.departamento, o.barrio_vereda, o.direccion, o.recolector_nombre,
                      e.fenomeno, e.municipio_divipola, g.geom_geojson, g.precision_gnss_m
               FROM objeto_afectado o
               JOIN evento e ON e.id_evento = o.id_evento
               LEFT JOIN geometria g ON g.id_objeto = o.id_objeto
               {where}""",
            tuple(params),
        ).fetchall()

        features = []
        for r in rows:
            if not r["geom_geojson"]:
                continue
            features.append({
                "type": "Feature",
                "geometry": json.loads(r["geom_geojson"]),
                "properties": {
                    "id_objeto": r["id_objeto"],
                    "tipo_objeto": r["tipo_objeto"],
                    "estado_operativo": r["estado_operativo"],
                    "nivel_dano_preliminar": r["nivel_dano_preliminar"],
                    "fenomeno": r["fenomeno"],
                    "municipio_divipola": r["municipio_divipola"],
                    "departamento": r["departamento"],
                    "barrio_vereda": r["barrio_vereda"],
                    "direccion": r["direccion"],
                    "recolector_nombre": r["recolector_nombre"],
                    "precision_gnss_m": r["precision_gnss_m"],
                },
            })
        return {"type": "FeatureCollection", "features": features}


@router.get("/geojson/{id_evento}")
def exportar_geojson(id_evento: str):
    """FeatureCollection de todos los objetos afectados de un evento — listo para
    MapLibre (dashboard web), QField/Mergin Maps o QGIS (Añadir capa vectorial)."""
    with get_conn() as conn:
        rows = conn.execute(
            """SELECT o.id_objeto, o.tipo_objeto, o.estado_operativo, o.nivel_dano_preliminar,
                      e.fenomeno, e.municipio_divipola, g.geom_geojson, g.precision_gnss_m
               FROM objeto_afectado o
               JOIN evento e ON e.id_evento = o.id_evento
               LEFT JOIN geometria g ON g.id_objeto = o.id_objeto
               WHERE o.id_evento = ?""",
            (id_evento,),
        ).fetchall()

        features = []
        for r in rows:
            if not r["geom_geojson"]:
                continue
            features.append({
                "type": "Feature",
                "geometry": json.loads(r["geom_geojson"]),
                "properties": {
                    "id_objeto": r["id_objeto"],
                    "tipo_objeto": r["tipo_objeto"],
                    "estado_operativo": r["estado_operativo"],
                    "nivel_dano_preliminar": r["nivel_dano_preliminar"],
                    "fenomeno": r["fenomeno"],
                    "municipio_divipola": r["municipio_divipola"],
                    "precision_gnss_m": r["precision_gnss_m"],
                },
            })
        return {"type": "FeatureCollection", "features": features}
