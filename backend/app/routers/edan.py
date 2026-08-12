"""Módulo MVP 2: EDAN básico adaptativo (necesidades + evidencia + consolidado)."""
from __future__ import annotations

import base64
import os
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.db.database import BASE_DIR, get_conn, new_uuid, now_iso, row_to_dict
from app.schemas.schemas import EvidenciaCrear, EvidenciaOut, NecesidadCrear, NecesidadOut

router = APIRouter(prefix="/api/edan", tags=["2. EDAN básico adaptativo"])

# Carpeta donde quedan las fotos reales de cada evidencia. Por defecto vive
# dentro del proyecto (workspace/evidencias/) — pero se puede apuntar a
# CUALQUIER carpeta local con la variable de entorno SIGERIA_CARPETA_EVIDENCIAS.
# Esto es lo que permite "vincular Drive" sin credenciales de Google Cloud:
# si esa ruta es una carpeta sincronizada por "Google Drive para escritorio"
# (o Drive File Stream), todo lo que el backend guarde ahí sube solo a Drive.
# Cada departamento que adopte SIGERIA puede así usar SU PROPIO Drive, sin
# tocar código — ver README.md, sección "Vincular Google Drive por departamento".
CARPETA_EVIDENCIAS = Path(
    os.environ.get("SIGERIA_CARPETA_EVIDENCIAS", str(BASE_DIR / "workspace" / "evidencias"))
)
CARPETA_EVIDENCIAS.mkdir(parents=True, exist_ok=True)


@router.post("/necesidades", response_model=NecesidadOut)
def crear_necesidad(payload: NecesidadCrear):
    with get_conn() as conn:
        _validar_objeto(conn, payload.id_objeto)
        id_necesidad = new_uuid()
        conn.execute(
            "INSERT INTO necesidad (id_necesidad, id_objeto, tipo) VALUES (?,?,?)",
            (id_necesidad, payload.id_objeto, payload.tipo),
        )
        row = conn.execute(
            "SELECT * FROM necesidad WHERE id_necesidad=?", (id_necesidad,)
        ).fetchone()
        return row_to_dict(row)


@router.post("/evidencias", response_model=EvidenciaOut)
def crear_evidencia(payload: EvidenciaCrear):
    with get_conn() as conn:
        _validar_objeto(conn, payload.id_objeto)
        id_evidencia = new_uuid()
        url = payload.url_almacenamiento

        # Si viene el contenido real (foto tomada en la app), se guarda de
        # verdad en disco — así el reporte PDF puede mostrar la foto real en
        # su recuadro, no solo el nombre del archivo.
        if payload.contenido_base64:
            try:
                datos = base64.b64decode(payload.contenido_base64)
                ruta = CARPETA_EVIDENCIAS / f"{id_evidencia}.jpg"
                ruta.write_bytes(datos)
                url = f"evidencias/{id_evidencia}.jpg"
            except Exception as exc:  # noqa: BLE001 — no tumbar el guardado por una foto mala
                raise HTTPException(400, f"No se pudo guardar la imagen: {exc}")

        conn.execute(
            """INSERT INTO evidencia (id_evidencia, id_objeto, tipo, url_almacenamiento, usuario_id)
               VALUES (?,?,?,?,?)""",
            (id_evidencia, payload.id_objeto, payload.tipo, url, payload.usuario_id),
        )
        row = conn.execute(
            "SELECT * FROM evidencia WHERE id_evidencia=?", (id_evidencia,)
        ).fetchone()
        return row_to_dict(row)


@router.get("/evidencias/{id_evidencia}/archivo")
def descargar_evidencia(id_evidencia: str):
    ruta = CARPETA_EVIDENCIAS / f"{id_evidencia}.jpg"
    if not ruta.exists():
        raise HTTPException(404, "Esta evidencia no tiene archivo guardado en el servidor")
    return FileResponse(ruta, media_type="image/jpeg")


@router.get("/evidencias")
def listar_evidencias(id_objeto: str):
    """Evidencias de un expediente — usado por la pantalla de consulta para
    mostrar las miniaturas sin traer todo el expediente completo."""
    with get_conn() as conn:
        filas = conn.execute(
            "SELECT * FROM evidencia WHERE id_objeto=? ORDER BY creado_en", (id_objeto,)
        ).fetchall()
        return [row_to_dict(f) for f in filas]


@router.delete("/evidencias/{id_evidencia}")
def eliminar_evidencia(id_evidencia: str):
    """Quita una foto de un expediente — p. ej. si quedó borrosa o repetida
    y se quiere reemplazar por una mejor."""
    with get_conn() as conn:
        row = conn.execute(
            "SELECT * FROM evidencia WHERE id_evidencia=?", (id_evidencia,)
        ).fetchone()
        if not row:
            raise HTTPException(404, "Esa evidencia no existe")
        ruta = CARPETA_EVIDENCIAS / f"{id_evidencia}.jpg"
        if ruta.exists():
            ruta.unlink()
        conn.execute("DELETE FROM evidencia WHERE id_evidencia=?", (id_evidencia,))
        return {"eliminado": id_evidencia}


@router.get("/consolidado/{id_evento}")
def consolidado_edan(id_evento: str):
    """Resumen automático — 'captura única' aplicada: no se vuelve a digitar nada."""
    with get_conn() as conn:
        objetos = conn.execute(
            "SELECT * FROM objeto_afectado WHERE id_evento=?", (id_evento,)
        ).fetchall()
        if not objetos:
            raise HTTPException(404, "No hay objetos registrados para este evento")

        ids = [o["id_objeto"] for o in objetos]
        placeholders = ",".join("?" * len(ids))

        por_severidad: dict[str, int] = {}
        por_estado: dict[str, int] = {}
        for o in objetos:
            sev = o["nivel_dano_preliminar"] or "sin_evaluar"
            por_severidad[sev] = por_severidad.get(sev, 0) + 1
            por_estado[o["estado_operativo"]] = por_estado.get(o["estado_operativo"], 0) + 1

        necesidades = conn.execute(
            f"SELECT tipo, estado, COUNT(*) as n FROM necesidad "
            f"WHERE id_objeto IN ({placeholders}) GROUP BY tipo, estado",
            ids,
        ).fetchall()

        return {
            "id_evento": id_evento,
            "total_objetos": len(objetos),
            "por_severidad_preliminar": por_severidad,
            "por_estado_operativo": por_estado,
            "necesidades": [row_to_dict(n) for n in necesidades],
            "generado_en": now_iso(),
        }


def _validar_objeto(conn, id_objeto: str) -> None:
    row = conn.execute(
        "SELECT 1 FROM objeto_afectado WHERE id_objeto=?", (id_objeto,)
    ).fetchone()
    if not row:
        raise HTTPException(404, f"Objeto afectado {id_objeto} no existe")
