import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Cámara REAL en vivo — reemplaza el `ImageSource.camera` de `image_picker`,
/// que en navegadores de escritorio (Mac/Windows/Linux) NO abre una cámara:
/// el atributo HTML `capture` que dispara solo lo respetan los navegadores
/// MÓVILES (Android/iOS); en escritorio cae siempre al buscador de archivos
/// del sistema operativo — eso es lo que el usuario venía viendo, no era un
/// bug de la app sino una limitación real del navegador.
///
/// Esta pantalla usa el paquete `camera` (con `camera_web` por debajo en
/// navegador, vía `getUserMedia`) para mostrar una vista previa EN VIVO y
/// capturar un cuadro real — funciona igual en Mac (webcam), Android e
/// iPhone (cámara trasera/frontal) y en cualquier navegador de escritorio.
///
/// Nota honesta sobre "tomar medidas con la cámara": esta vista sirve para
/// tomar la FOTO calibrada que acompaña cada medición (sección 11 del
/// documento base — "Metrología y responsabilidad": las mediciones con
/// sensores del teléfono son orientativas, no certificadas). Calcular una
/// distancia real automáticamente a partir de la imagen requeriría ARCore/
/// ARKit con sensor de profundidad (solo en apps nativas móviles, no vía
/// navegador) — no se simula ese cálculo; el valor numérico se sigue
/// ingresando junto a la foto, como ya lo pedía el documento base.
class CamaraCapturaScreen extends StatefulWidget {
  final String titulo;
  const CamaraCapturaScreen({super.key, this.titulo = 'Tomar foto'});

  @override
  State<CamaraCapturaScreen> createState() => _CamaraCapturaScreenState();
}

class _CamaraCapturaScreenState extends State<CamaraCapturaScreen> {
  CameraController? _controller;
  List<CameraDescription> _camaras = [];
  int _indiceCamaraActual = 0;
  Future<void>? _inicializacion;
  String? _error;
  bool _capturando = false;

  @override
  void initState() {
    super.initState();
    _inicializacion = _iniciar();
  }

  Future<void> _iniciar() async {
    try {
      _camaras = await availableCameras();
      if (_camaras.isEmpty) {
        setState(() => _error = 'Este dispositivo no reporta ninguna cámara disponible.');
        return;
      }
      // En celular, arrancar con la cámara trasera si existe (mejor para fotos de campo).
      _indiceCamaraActual = _camaras.indexWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      if (_indiceCamaraActual < 0) _indiceCamaraActual = 0;
      await _abrirCamara(_camaras[_indiceCamaraActual]);
    } catch (e) {
      setState(() => _error = 'No se pudo iniciar la cámara: $e');
    }
  }

  Future<void> _abrirCamara(CameraDescription camara) async {
    final anterior = _controller;
    _controller = CameraController(
      camara,
      ResolutionPreset.high,
      enableAudio: false,
    );
    await anterior?.dispose();
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _cambiarCamara() async {
    if (_camaras.length < 2) return;
    setState(() => _indiceCamaraActual = (_indiceCamaraActual + 1) % _camaras.length);
    await _abrirCamara(_camaras[_indiceCamaraActual]);
  }

  Future<void> _capturar() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturando) return;
    setState(() => _capturando = true);
    try {
      final archivo = await c.takePicture();
      final bytes = await archivo.readAsBytes();
      if (mounted) Navigator.pop(context, (bytes, archivo));
    } catch (e) {
      setState(() {
        _error = 'No se pudo tomar la foto: $e';
        _capturando = false;
      });
    }
  }

  /// Respaldo: si la cámara no está disponible (permiso denegado, sin
  /// hardware), se deja elegir un archivo — mismo comportamiento que antes,
  /// pero ahora como excepción explícita, no como comportamiento por defecto.
  Future<void> _usarGaleria() async {
    final archivo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (archivo == null) return;
    final bytes = await archivo.readAsBytes();
    if (mounted) Navigator.pop(context, (bytes, archivo));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.titulo),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_camaras.length > 1)
            IconButton(
              icon: const Icon(Icons.cameraswitch),
              tooltip: 'Cambiar cámara',
              onPressed: _cambiarCamara,
            ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _inicializacion,
        builder: (context, snapshot) {
          if (_error != null) {
            return _panelError();
          }
          if (snapshot.connectionState != ConnectionState.done ||
              _controller == null ||
              !_controller!.value.isInitialized) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }
          return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(child: CameraPreview(_controller!)),
              Positioned(
                bottom: 24,
                child: _botonCaptura(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _panelError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(_error ?? 'Error de cámara',
                style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Elegir de la galería'),
              onPressed: _usarGaleria,
            ),
          ],
        ),
      ),
    );
  }

  Widget _botonCaptura() {
    return GestureDetector(
      onTap: _capturando ? null : _capturar,
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          color: _capturando ? Colors.grey : Colors.white24,
        ),
        child: _capturando
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(color: Colors.white),
              )
            : const Icon(Icons.camera_alt, color: Colors.white, size: 32),
      ),
    );
  }
}
