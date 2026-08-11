"""Módulo MVP 1: Evento y objetos afectados."""
from __future__ import annotations

import json

from fastapi import APIRouter, HTTPException

from app.db.database import (
    generar_id_evento, generar_id_objeto, get_conn, new_uuid, now_iso, row_to_dict,
)
from app.schemas.schemas import EventoCrear, EventoOut, ObjetoAfectadoCrear, ObjetoAfectadoOut

router = APIRouter(prefix="/api/eventos", tags=["1. Evento y objetos"])


@router.post("", response_model=EventoOut)
def crear_evento(payload: EventoCrear):
    with get_conn() as conn:
        id_evento = generar_id_evento(conn)
        conn.execute(
            """INSERT INTO evento (id_evento, fenomeno, fecha_evento, municipio_divipola,
                                    descripcion, creado_por)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (id_evento, payload.fenomeno, payload.fecha_evento.isoformat(),
             payload.municipio_divipola, payload.descripcion, payload.creado_por),
        )
        conn.execute(
            "INSERT INTO auditoria (tabla, id_registro, accion, usuario_id) VALUES (?,?,?,?)",
            ("evento", id_evento, "crear", payload.creado_por),
        )
        row = conn.execute("SELECT * FROM evento WHERE id_evento=?", (id_evento,)).fetchone()
        return row_to_dict(row)


@router.get("", response_model=list[EventoOut])
def listar_eventos():
    with get_conn() as conn:
        rows = conn.execute("SELECT * FROM evento ORDER BY creado_en DESC").fetchall()
        return [row_to_dict(r) for r in rows]


@router.get("/{id_evento}", response_model=EventoOut)
def obtener_evento(id_evento: str):
    with get_conn() as conn:
        row = conn.execute("SELECT * FROM evento WHERE id_evento=?", (id_evento,)).fetchone()
        if not row:
            raise HTTPException(404, "Evento no encontrado")
        return row_to_dict(row)


@router.post("/objetos", response_model=ObjetoAfectadoOut)
def crear_objeto_afectado(payload: ObjetoAfectadoCrear):
    with get_conn() as conn:
        evento = conn.execute(
            "SELECT * FROM evento WHERE id_evento=?", (payload.id_evento,)
        ).fetchone()
        if not evento:
            raise HTTPException(404, "El evento indicado no existe")

        id_objeto = generar_id_objeto(evento["municipio_divipola"], evento["fenomeno"], conn)
        ts = now_iso()
        conn.execute(
            """INSERT INTO objeto_afectado
               (id_objeto, id_evento, tipo_objeto, estado_operativo, nivel_dano_preliminar,
                departamento, barrio_vereda, direccion,
                recolector_nombre, recolector_documento, recolector_cargo, recolector_entidad,
                informante_nombre, informante_documento, informante_parentesco, informante_telefono,
                requiere_subsidio_arrendamiento, resumen_componentes_dano,
                observaciones_tecnicas, personas_afectadas,
                creado_por, creado_en, actualizado_en)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (id_objeto, payload.id_evento, payload.tipo_objeto, payload.estado_operativo,
             payload.nivel_dano_preliminar, payload.departamento, payload.barrio_vereda,
             payload.direccion, payload.recolector_nombre, payload.recolector_documento,
             payload.recolector_cargo, payload.recolector_entidad, payload.informante_nombre,
             payload.informante_documento, payload.informante_parentesco,
             payload.informante_telefono,
             None if payload.requiere_subsidio_arrendamiento is None
             else int(payload.requiere_subsidio_arrendamiento),
             payload.resumen_componentes_dano,
             payload.observaciones_tecnicas,
             payload.personas_afectadas,
             payload.creado_por, ts, ts),
        )
        conn.execute(
            "INSERT INTO auditoria (tabla, id_registro, accion, usuario_id) VALUES (?,?,?,?)",
            ("objeto_afectado", id_objeto, "crear", payload.creado_por),
        )
        # Detalle fila por fila de la lista de chequeo — habilita estadísticas
        # reales de "qué componentes se dañan más" (no solo el resumen en texto).
        if payload.componentes:
            conn.executemany(
                """INSERT INTO componente_dano_detalle (id_detalle, id_objeto, componente, severidad)
                   VALUES (?,?,?,?)""",
                [(new_uuid(), id_objeto, c.componente, c.severidad) for c in payload.componentes],
            )
        row = conn.execute(
            "SELECT * FROM objeto_afectado WHERE id_objeto=?", (id_objeto,)
        ).fetchone()
        return row_to_dict(row)


@router.get("/objetos/lista", response_model=list[ObjetoAfectadoOut])
def listar_objetos(id_evento: str | None = None):
    with get_conn() as conn:
        if id_evento:
            rows = conn.execute(
                "SELECT * FROM objeto_afectado WHERE id_evento=? ORDER BY creado_en DESC",
                (id_evento,),
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT * FROM objeto_afectado ORDER BY creado_en DESC"
            ).fetchall()
        return [row_to_dict(r) for r in rows]
