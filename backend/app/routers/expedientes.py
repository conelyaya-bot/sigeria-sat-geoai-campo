"""Exportación del expediente completo — JSON para integraciones (p.ej. subir
a Google Drive) y PDF profesional con fotos en recuadros, listo para
imprimir o entregar ante UNGRD/departamento/municipio.
"""
from __future__ import annotations

import io
import json

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response, StreamingResponse

from app.db.database import get_conn, new_uuid, now_iso, row_to_dict
from app.routers.edan import CARPETA_EVIDENCIAS
from app.schemas.schemas import ObjetoAfectadoActualizar

router = APIRouter(prefix="/api/expedientes", tags=["Expedientes"])


@router.get("/lista")
def listar_expedientes(
    departamento: str | None = None,
    municipio_divipola: str | None = None,
    q: str | None = None,
):
    """Lista liviana para la pantalla 'Consultar registros' — junta el
    objeto afectado con el fenómeno/municipio del evento y si tiene o no
    foto/GPS capturados, sin traer el detalle completo de cada uno
    (fotos, mediciones, etc. — eso se pide aparte con /detalle)."""
    with get_conn() as conn:
        condiciones = []
        parametros: list = []
        if departamento:
            condiciones.append("o.departamento = ?")
            parametros.append(departamento)
        if municipio_divipola:
            condiciones.append("e.municipio_divipola = ?")
            parametros.append(municipio_divipola)
        if q:
            condiciones.append(
                "(o.id_objeto LIKE ? OR o.direccion LIKE ? OR o.barrio_vereda LIKE ? "
                "OR o.informante_nombre LIKE ? OR o.recolector_nombre LIKE ?)"
            )
            comodin = f"%{q}%"
            parametros.extend([comodin] * 5)
        where = f"WHERE {' AND '.join(condiciones)}" if condiciones else ""
        filas = conn.execute(
            f"""SELECT o.id_objeto, o.id_evento, o.tipo_objeto, o.estado_operativo,
                       o.nivel_dano_preliminar, o.departamento, o.barrio_vereda, o.direccion,
                       o.informante_nombre, o.personas_afectadas, o.creado_en, o.actualizado_en,
                       e.fenomeno, e.municipio_divipola,
                       (SELECT COUNT(*) FROM evidencia ev WHERE ev.id_objeto = o.id_objeto
                        AND ev.tipo = 'foto') AS num_fotos,
                       (SELECT COUNT(*) FROM geometria g WHERE g.id_objeto = o.id_objeto) AS num_geometrias
                FROM objeto_afectado o
                JOIN evento e ON e.id_evento = o.id_evento
                {where}
                ORDER BY o.creado_en DESC
                LIMIT 500""",
            parametros,
        ).fetchall()
        return [row_to_dict(f) for f in filas]


@router.get("/{id_objeto}/detalle")
def detalle_expediente(id_objeto: str):
    """Igual a /exportar pero es el nombre que usa la pantalla de consulta
    — se deja /exportar también por compatibilidad con integraciones (Drive)."""
    with get_conn() as conn:
        return _reunir_expediente(conn, id_objeto)


@router.put("/{id_objeto}")
def editar_expediente(id_objeto: str, payload: ObjetoAfectadoActualizar):
    """Corrige datos de un expediente ya guardado — por ejemplo si algo
    quedó mal digitado, o para completar foto/GPS que faltaron al momento
    de la captura en campo."""
    with get_conn() as conn:
        actual = conn.execute(
            "SELECT * FROM objeto_afectado WHERE id_objeto=?", (id_objeto,)
        ).fetchone()
        if not actual:
            raise HTTPException(404, f"Expediente {id_objeto} no existe")

        campos_planos = payload.model_dump(
            exclude={"componentes", "lat", "lon", "precision_gnss_m"}, exclude_unset=True
        )
        if campos_planos:
            if "requiere_subsidio_arrendamiento" in campos_planos:
                v = campos_planos["requiere_subsidio_arrendamiento"]
                campos_planos["requiere_subsidio_arrendamiento"] = None if v is None else int(v)
            asignaciones = ", ".join(f"{c} = ?" for c in campos_planos)
            conn.execute(
                f"UPDATE objeto_afectado SET {asignaciones}, actualizado_en = ? WHERE id_objeto = ?",
                (*campos_planos.values(), now_iso(), id_objeto),
            )

        # Componentes de daño: si vienen, se reemplaza el detalle completo
        # (más simple y confiable que intentar hacer un diff fila por fila).
        if payload.componentes is not None:
            conn.execute("DELETE FROM componente_dano_detalle WHERE id_objeto=?", (id_objeto,))
            if payload.componentes:
                conn.executemany(
                    """INSERT INTO componente_dano_detalle (id_detalle, id_objeto, componente, severidad)
                       VALUES (?,?,?,?)""",
                    [(new_uuid(), id_objeto, c.componente, c.severidad) for c in payload.componentes],
                )

        # Ubicación: si viene lat/lon, se reemplaza la geometría del objeto
        # (un expediente = un solo punto, así que no acumula duplicados).
        if payload.lat is not None and payload.lon is not None:
            conn.execute("DELETE FROM geometria WHERE id_objeto=?", (id_objeto,))
            conn.execute(
                """INSERT INTO geometria (id_geometria, id_objeto, geom_tipo, geom_geojson,
                                           precision_gnss_m, fuente_posicion)
                   VALUES (?,?,?,?,?,?)""",
                (
                    new_uuid(), id_objeto, "Point",
                    json.dumps({"type": "Point", "coordinates": [payload.lon, payload.lat]}),
                    payload.precision_gnss_m, "gnss_interno",
                ),
            )

        conn.execute(
            "INSERT INTO auditoria (tabla, id_registro, accion, usuario_id) VALUES (?,?,?,?)",
            ("objeto_afectado", id_objeto, "editar", None),
        )
        return _reunir_expediente(conn, id_objeto)


@router.delete("/{id_objeto}")
def eliminar_expediente(id_objeto: str):
    """Borra el expediente completo: objeto afectado, geometría, necesidades,
    mediciones, componentes de daño y evidencias (incluyendo los archivos de
    foto guardados en disco). El evento (encabezado) NO se borra — puede
    tener otros objetos asociados."""
    with get_conn() as conn:
        actual = conn.execute(
            "SELECT 1 FROM objeto_afectado WHERE id_objeto=?", (id_objeto,)
        ).fetchone()
        if not actual:
            raise HTTPException(404, f"Expediente {id_objeto} no existe")

        evidencias = conn.execute(
            "SELECT id_evidencia FROM evidencia WHERE id_objeto=?", (id_objeto,)
        ).fetchall()
        for ev in evidencias:
            ruta = CARPETA_EVIDENCIAS / f"{ev['id_evidencia']}.jpg"
            if ruta.exists():
                ruta.unlink()

        for tabla in ("evidencia", "medicion", "necesidad", "geometria", "componente_dano_detalle"):
            conn.execute(f"DELETE FROM {tabla} WHERE id_objeto=?", (id_objeto,))
        conn.execute("DELETE FROM objeto_afectado WHERE id_objeto=?", (id_objeto,))
        conn.execute(
            "INSERT INTO auditoria (tabla, id_registro, accion, usuario_id) VALUES (?,?,?,?)",
            ("objeto_afectado", id_objeto, "eliminar", None),
        )
        return {"eliminado": id_objeto}


def _reunir_expediente(conn, id_objeto: str) -> dict:
    objeto = conn.execute(
        "SELECT * FROM objeto_afectado WHERE id_objeto=?", (id_objeto,)
    ).fetchone()
    if not objeto:
        raise HTTPException(404, f"Expediente {id_objeto} no existe")
    objeto = row_to_dict(objeto)

    evento = conn.execute(
        "SELECT * FROM evento WHERE id_evento=?", (objeto["id_evento"],)
    ).fetchone()
    evento = row_to_dict(evento) if evento else None

    # `geom_geojson` se guarda en la tabla como TEXTO (json.dumps, ver
    # app/routers/gis.py:crear_geometria) — hay que decodificarlo aquí antes
    # de devolverlo, igual que ya hace ese router, o el cliente (Flutter)
    # recibe un string plano donde espera un objeto {type, coordinates} y
    # revienta con un TypeError al intentar leerlo como mapa.
    geometrias = []
    for r in conn.execute("SELECT * FROM geometria WHERE id_objeto=?", (id_objeto,)).fetchall():
        g = row_to_dict(r)
        if isinstance(g.get("geom_geojson"), str):
            g["geom_geojson"] = json.loads(g["geom_geojson"])
        geometrias.append(g)
    necesidades = [
        row_to_dict(r)
        for r in conn.execute(
            "SELECT * FROM necesidad WHERE id_objeto=?", (id_objeto,)
        ).fetchall()
    ]
    mediciones = [
        row_to_dict(r)
        for r in conn.execute(
            "SELECT * FROM medicion WHERE id_objeto=?", (id_objeto,)
        ).fetchall()
    ]
    evidencias = [
        row_to_dict(r)
        for r in conn.execute(
            "SELECT * FROM evidencia WHERE id_objeto=?", (id_objeto,)
        ).fetchall()
    ]
    componentes = [
        row_to_dict(r)
        for r in conn.execute(
            "SELECT componente, severidad FROM componente_dano_detalle WHERE id_objeto=?",
            (id_objeto,),
        ).fetchall()
    ]

    return {
        "evento": evento,
        "objeto_afectado": objeto,
        "geometrias": geometrias,
        "necesidades": necesidades,
        "mediciones": mediciones,
        "evidencias": evidencias,
        "componentes": componentes,
    }


@router.get("/{id_objeto}/exportar")
def exportar_expediente(id_objeto: str):
    """JSON completo del expediente — el mismo payload que se sube a la
    carpeta de Google Drive `SIGERIA - Expedientes/<id_objeto>/ficha.json`
    (ver README de esa carpeta)."""
    with get_conn() as conn:
        return _reunir_expediente(conn, id_objeto)


@router.get("/{id_objeto}/reporte.pdf")
def reporte_pdf(id_objeto: str):
    """Ficha imprimible: datos del expediente + checklist de daños +
    mediciones + fotos en recuadros. Usa reportlab (no requiere binarios
    externos como wkhtmltopdf)."""
    from reportlab.lib import colors
    from reportlab.lib.pagesizes import letter
    from reportlab.lib.units import cm
    from reportlab.platypus import (
        SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, Image,
    )
    from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

    with get_conn() as conn:
        datos = _reunir_expediente(conn, id_objeto)

    objeto = datos["objeto_afectado"]
    evento = datos["evento"] or {}

    buffer = io.BytesIO()
    doc = SimpleDocTemplate(
        buffer, pagesize=letter,
        topMargin=1.5 * cm, bottomMargin=1.5 * cm, leftMargin=1.5 * cm, rightMargin=1.5 * cm,
    )
    estilos = getSampleStyleSheet()
    titulo = ParagraphStyle("TituloSigeria", parent=estilos["Heading1"], textColor=colors.HexColor("#1F4E5F"))
    subtitulo = ParagraphStyle("Subtitulo", parent=estilos["Heading2"], textColor=colors.HexColor("#1F4E5F"), spaceBefore=10)

    elementos = [
        Paragraph("SIGERIA — Ficha de expediente", titulo),
        Paragraph(
            "Sistema Inteligente Geoespacial para Evaluación, Respuesta e Inspección de "
            "Afectaciones — módulo de SAT-GeoAI Chocó",
            estilos["Normal"],
        ),
        Spacer(1, 12),
    ]

    def _tabla(filas, anchos=None):
        t = Table(filas, colWidths=anchos)
        t.setStyle(TableStyle([
            ("GRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#c8d2d5")),
            ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#eef2f3")),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ]))
        return t

    # --- Identificación del expediente ---
    elementos.append(Paragraph("Identificación", subtitulo))
    elementos.append(_tabla([
        ["Código del expediente", objeto["id_objeto"]],
        ["Evento", f"{evento.get('fenomeno', '?')} — {evento.get('fecha_evento', '?')}"],
        ["Municipio (DIVIPOLA)", evento.get("municipio_divipola", "?")],
        ["Departamento", objeto.get("departamento") or "—"],
        ["Barrio / corregimiento / vereda", objeto.get("barrio_vereda") or "—"],
        ["Dirección", objeto.get("direccion") or "—"],
        ["Tipo de objeto", objeto["tipo_objeto"]],
        ["Estado operativo", objeto["estado_operativo"]],
    ], anchos=[6 * cm, 10.5 * cm]))

    # --- Responsable / Informante ---
    elementos.append(Paragraph("Responsable de la recolección e informante", subtitulo))
    elementos.append(_tabla([
        ["Recolector", objeto.get("recolector_nombre") or "—"],
        ["Documento / cargo / entidad",
         f"{objeto.get('recolector_documento') or '—'} · "
         f"{objeto.get('recolector_cargo') or '—'} · {objeto.get('recolector_entidad') or '—'}"],
        ["Informante (beneficiario)", objeto.get("informante_nombre") or "—"],
        ["Documento / parentesco / teléfono",
         f"{objeto.get('informante_documento') or '—'} · "
         f"{objeto.get('informante_parentesco') or '—'} · {objeto.get('informante_telefono') or '—'}"],
    ], anchos=[6 * cm, 10.5 * cm]))

    # --- Daño ---
    elementos.append(Paragraph("Evaluación de daños (lista de chequeo por componente)", subtitulo))
    elementos.append(_tabla([
        ["Nivel de daño preliminar (calculado)", (objeto.get("nivel_dano_preliminar") or "sin_evaluar").upper()],
        ["Componentes afectados", objeto.get("resumen_componentes_dano") or "Sin componentes con daño marcado."],
        ["¿Requiere subsidio de arrendamiento?",
         {1: "Sí", 0: "No", None: "Sin evaluar"}.get(objeto.get("requiere_subsidio_arrendamiento"), "Sin evaluar")],
    ], anchos=[6 * cm, 10.5 * cm]))

    if objeto.get("observaciones_tecnicas"):
        elementos.append(Paragraph("Observaciones técnicas (ingeniero/a)", subtitulo))
        elementos.append(_tabla(
            [["Detalle", objeto["observaciones_tecnicas"]]], anchos=[6 * cm, 10.5 * cm]
        ))

    # --- Necesidades ---
    if datos["necesidades"]:
        elementos.append(Paragraph("Necesidades registradas", subtitulo))
        filas = [["Tipo", "Estado"]] + [[n["tipo"], n["estado"]] for n in datos["necesidades"]]
        elementos.append(_tabla(filas, anchos=[8 * cm, 8.5 * cm]))

    # --- Mediciones ---
    if datos["mediciones"]:
        elementos.append(Paragraph("Mediciones", subtitulo))
        filas = [["Tipo", "Valor", "Unidad", "Método", "Precisión"]] + [
            [m["tipo"], str(m["valor"]), m["unidad"], m["metodo"], m["precision_categoria"]]
            for m in datos["mediciones"]
        ]
        elementos.append(_tabla(filas, anchos=[3.3 * cm] * 5))

    # --- Geometría ---
    if datos["geometrias"]:
        g = datos["geometrias"][0]
        elementos.append(Paragraph("Georreferenciación", subtitulo))
        elementos.append(_tabla([
            ["Tipo de geometría", g["geom_tipo"]],
            ["Precisión GNSS", f"{g.get('precision_gnss_m') or '?'} m"],
            ["Fuente de posición", g.get("fuente_posicion") or "—"],
        ], anchos=[6 * cm, 10.5 * cm]))

    # --- Fotos en recuadros (grilla 2 columnas) ---
    fotos_guardadas = [
        e for e in datos["evidencias"]
        if e["tipo"] == "foto" and (CARPETA_EVIDENCIAS / f"{e['id_evidencia']}.jpg").exists()
    ]
    elementos.append(Paragraph("Evidencia fotográfica", subtitulo))
    if not fotos_guardadas:
        elementos.append(Paragraph(
            f"No hay fotos con archivo guardado en el servidor "
            f"({len(datos['evidencias'])} evidencia(s) registrada(s) solo con referencia local).",
            estilos["Normal"],
        ))
    else:
        celdas = []
        fila = []
        for i, e in enumerate(fotos_guardadas):
            ruta = CARPETA_EVIDENCIAS / f"{e['id_evidencia']}.jpg"
            img = Image(str(ruta), width=7.5 * cm, height=7.5 * cm, kind="proportional")
            recuadro = Table([[img], [Paragraph(f"Foto — {e['creado_en']}", estilos["Normal"])]])
            recuadro.setStyle(TableStyle([
                ("BOX", (0, 0), (-1, -1), 1, colors.HexColor("#1F4E5F")),
                ("ALIGN", (0, 0), (-1, -1), "CENTER"),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]))
            fila.append(recuadro)
            if len(fila) == 2 or i == len(fotos_guardadas) - 1:
                celdas.append(fila)
                fila = []
        grilla = Table(celdas, colWidths=[8 * cm, 8 * cm])
        grilla.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]))
        elementos.append(grilla)

    elementos.append(Spacer(1, 16))
    elementos.append(Paragraph(
        "SIGERIA no sustituye dictamen profesional ni instrumentos oficiales EDAN/RUD de la UNGRD.",
        ParagraphStyle("Pie", parent=estilos["Normal"], fontSize=7, textColor=colors.grey),
    ))

    doc.build(elementos)
    buffer.seek(0)
    return StreamingResponse(
        buffer,
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{id_objeto}.pdf"'},
    )
