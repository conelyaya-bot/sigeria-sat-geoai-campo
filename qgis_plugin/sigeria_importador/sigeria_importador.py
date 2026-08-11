# -*- coding: utf-8 -*-
"""
SIGERIA Importador EDAN - clase principal del plugin.

Responsabilidad de este archivo (integración con QGIS):
- Agregar el botón a la barra de herramientas y al menú Vectorial.
- Abrir el diálogo cuando el usuario hace clic.
La lógica de carga/simbología vive en el diálogo (sigeria_dialog.py).
"""

import os

from qgis.PyQt.QtCore import QCoreApplication
from qgis.PyQt.QtGui import QIcon
try:
    from qgis.PyQt.QtGui import QAction
except ImportError:
    from qgis.PyQt.QtWidgets import QAction

from .sigeria_dialog import SigeriaDialog


class SigeriaImportador:
    """Plugin que agrega la herramienta 'Importar objetos afectados SIGERIA'."""

    def __init__(self, iface):
        self.iface = iface
        self.plugin_dir = os.path.dirname(__file__)
        self.actions = []
        self.menu = "&SIGERIA"
        self.toolbar = None
        self.dialog = None

    def tr(self, message):
        return QCoreApplication.translate("SigeriaImportador", message)

    def initGui(self):
        icon_path = os.path.join(self.plugin_dir, "icon.svg")
        icon = QIcon(icon_path)

        self.action = QAction(
            icon,
            self.tr("Importar objetos afectados SIGERIA..."),
            self.iface.mainWindow(),
        )
        self.action.triggered.connect(self.run)
        self.action.setStatusTip(
            self.tr("Cargar GeoJSON de EDAN/objetos afectados y simbolizar por severidad")
        )

        self.toolbar = self.iface.addToolBar(self.tr("SIGERIA"))
        self.toolbar.setObjectName("SigeriaImportadorToolbar")
        self.toolbar.addAction(self.action)

        self.iface.addPluginToVectorMenu(self.menu, self.action)
        self.actions.append(self.action)

    def unload(self):
        for action in self.actions:
            self.iface.removePluginVectorMenu(self.menu, action)
            self.iface.removeToolBarIcon(action)
        if self.toolbar:
            del self.toolbar

    def run(self):
        if self.dialog is None:
            self.dialog = SigeriaDialog(self.iface, self.iface.mainWindow())
        self.dialog.show()
        self.dialog.exec_()
