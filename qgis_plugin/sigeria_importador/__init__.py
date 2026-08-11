# -*- coding: utf-8 -*-
"""
SIGERIA Importador EDAN
Punto de entrada del plugin. QGIS llama a classFactory(iface) al cargar.
"""


def classFactory(iface):
    from .sigeria_importador import SigeriaImportador
    return SigeriaImportador(iface)
