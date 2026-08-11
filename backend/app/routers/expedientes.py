"""Exportación del expediente completo — JSON para integraciones (p.ej. subir
a Google Drive) y PDF profesional con fotos en recuadros, listo para
imprimir o entregar ante UNGRD/departamento/municipio.
"""
from __future__ import annotations

import io

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response, StreamingResponse

from app.db.database import get_conn, row_to_dict
from app.routers.edan import CARPETA_EVIDENCIAS

router = APIRouter(prefix="/api/expedientes", tags=["Expedientes"])


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

    geometrias = [
        row_to_dict(r)
        for r in conn.execute(
            "SELECT * FROM geometria WHERE id_objeto=?", (id_objeto,)
        ).fetchall()
    ]
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

    return {
        "evento": evento,
        "objeto_afectado": objeto,
        "geometrias": geometrias,
        "necesidades": necesidades,
        "mediciones": mediciones,
        "evidencias": evidencias,
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
