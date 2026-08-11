# -*- coding: utf-8 -*-
"""
Diálogo del plugin SIGERIA Importador EDAN.

Dos formas de traer datos al QGIS de escritorio (módulo "GIS de campo",
sección 16 del documento base):
  1) Archivo GeoJSON exportado manualmente (p.ej. desde la app móvil offline).
  2) URL en vivo del backend: GET /api/gis/geojson/{id_evento}.

Tras cargar, aplica simbología categorizada por 'nivel_dano_preliminar' —
misma paleta de color que el dashboard web (web/js/app.js), para que el
mapa de campo, el mapa de escritorio y la sala de crisis se vean igual.
"""
import json
import urllib.request

from qgis.core import (
    QgsProject, QgsVectorLayer, QgsMarkerSymbol,
    QgsRendererCategory, QgsCategorizedSymbolRenderer,
)

try:
    from qgis.PyQt.QtWidgets import (
        QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit, QPushButton,
        QFileDialog, QMessageBox, QRadioButton, QButtonGroup,
    )
except ImportError:  # pragma: no cover - compatibilidad Qt6
    from qgis.PyQt.QtWidgets import (
        QDialog, QVBoxLayout, QHBoxLayout, QLabel, QLineEdit, QPushButton,
        QFileDialog, QMessageBox, QRadioButton, QButtonGroup,
    )

COLOR_SEVERIDAD = {
    "sin_evaluar": "#8a8f98",
    "sin_dano": "#2e8b57",
    "leve": "#c9b400",
    "moderado": "#e08a1e",
    "severo": "#d1392b",
    "colapso": "#6b0f1a",
}


class SigeriaDialog(QDialog):
    def __init__(self, iface, parent=None):
        super().__init__(parent)
        self.iface = iface
        self.setWindowTitle("SIGERIA — Importar objetos afectados")
        self.setMinimumWidth(480)
        self._construir_ui()

    def _construir_ui(self):
        layout = QVBoxLayout(self)

        layout.addWidget(QLabel(
            "<b>SIGERIA</b> — Sistema Inteligente Geoespacial para Evaluación, "
            "Respuesta e Inspección de Afectaciones"
        ))

        self.rb_archivo = QRadioButton("Archivo GeoJSON local")
        self.rb_url = QRadioButton("URL del backend (API en vivo)")
        self.rb_archivo.setChecked(True)
        grupo = QButtonGroup(self)
        grupo.addButton(self.rb_archivo)
        grupo.addButton(self.rb_url)
        layout.addWidget(self.rb_archivo)
        layout.addWidget(self.rb_url)

        fila_archivo = QHBoxLayout()
        self.txt_ruta = QLineEdit()
        self.txt_ruta.setPlaceholderText("Ruta al .geojson exportado (módulo GIS offline)")
        btn_explorar = QPushButton("Explorar…")
        btn_explorar.clicked.connect(self._elegir_archivo)
        fila_archivo.addWidget(self.txt_ruta)
        fila_archivo.addWidget(btn_explorar)
        layout.addLayout(fila_archivo)

        self.txt_url = QLineEdit()
        self.txt_url.setPlaceholderText(
            "http://127.0.0.1:8010/api/gis/geojson/SIGERIA-EVT-2026-XXXXXXXX"
        )
        layout.addWidget(self.txt_url)

        self.lbl_estado = QLabel("")
        layout.addWidget(self.lbl_estado)

        botones = QHBoxLayout()
        btn_cargar = QPushButton("Cargar y simbolizar")
        btn_cargar.clicked.connect(self._cargar)
        btn_cerrar = QPushButton("Cerrar")
        btn_cerrar.clicked.connect(self.close)
        botones.addWidget(btn_cargar)
        botones.addWidget(btn_cerrar)
        layout.addLayout(botones)

    def _elegir_archivo(self):
        ruta, _ = QFileDialog.getOpenFileName(
            self, "Elegir GeoJSON de objetos afectados", "", "GeoJSON (*.geojson *.json)"
        )
        if ruta:
            self.txt_ruta.setText(ruta)

    def _cargar(self):
        try:
            if self.rb_url.isChecked():
                url = self.txt_url.text().strip()
                if not url:
                    raise ValueError("Ingresa la URL del backend")
                with urllib.request.urlopen(url, timeout=10) as resp:
                    datos = json.loads(resp.read().decode("utf-8"))
                capa = QgsVectorLayer(json.dumps(datos), "SIGERIA_objetos_afectados", "ogr")
            else:
                ruta = self.txt_ruta.text().strip()
                if not ruta:
                    raise ValueError("Elige un archivo GeoJSON")
                capa = QgsVectorLayer(ruta, "SIGERIA_objetos_afectados", "ogr")

            if not capa.isValid():
                raise RuntimeError("La capa no es válida — revisa el origen de datos")

            QgsProject.instance().addMapLayer(capa)
            self._simbolizar_por_severidad(capa)
            self.iface.mapCanvas().setExtent(capa.extent())
            self.iface.mapCanvas().refresh()

            self.lbl_estado.setText(f"Cargados {capa.featureCount()} objetos afectados.")
        except Exception as exc:  # noqa: BLE001 — mostrar cualquier error al usuario
            QMessageBox.critical(self, "Error al importar", str(exc))

    def _simbolizar_por_severidad(self, capa):
        if "nivel_dano_preliminar" not in [f.name() for f in capa.fields()]:
            return  # capa sin ese campo (p.ej. otra exportación); dejar simbología por defecto
        categorias = []
        for valor, color in COLOR_SEVERIDAD.items():
            simbolo = QgsMarkerSymbol.createSimple(
                {"color": color, "size": "4", "outline_color": "white"}
            )
            categorias.append(QgsRendererCategory(valor, simbolo, valor))
        renderer = QgsCategorizedSymbolRenderer("nivel_dano_preliminar", categorias)
        capa.setRenderer(renderer)
        capa.triggerRepaint()
