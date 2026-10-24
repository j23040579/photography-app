import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Takes one still photo on Android or a Windows webcam. The returned path is
/// temporary: callers must copy it into their managed memory store.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  int _generation = 0;
  bool _loading = true;
  bool _takingPhoto = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  Future<void> _initialize({bool findCameras = true}) async {
    final generation = ++_generation;
    final previous = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    CameraController? next;
    try {
      await previous?.dispose();
      if (findCameras || _cameras.isEmpty) {
        _cameras = await availableCameras();
        final back = _cameras.indexWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
        );
        _cameraIndex = back < 0 ? 0 : back;
      }
      if (!mounted || generation != _generation) return;
      if (_cameras.isEmpty) {
        setState(() {
          _loading = false;
          _error =
              'No camera was found. Connect a webcam, or go back and '
              'import a photo from your device.';
        });
        return;
      }
      next = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await next.initialize();
      if (!mounted || generation != _generation) {
        await next.dispose();
        return;
      }
      _controller = next;
      next.addListener(_cameraChanged);
      setState(() => _loading = false);
    } catch (error) {
      await next?.dispose();
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = _cameraError(error);
      });
    }
  }

  void _cameraChanged() {
    final controller = _controller;
    if (!mounted || controller == null || !controller.value.hasError) return;
    setState(() {
      _error =
          controller.value.errorDescription ??
          'The camera disconnected. Check your camera and try again.';
    });
  }

  String _cameraError(Object error) {
    if (error is CameraException) {
      if (error.code.toLowerCase().contains('access') ||
          error.code.toLowerCase().contains('permission')) {
        return 'Camera access is unavailable. Allow camera access in your '
            'device settings, then try again. You can also import a photo.';
      }
      return 'Could not open the camera (${error.code}). Close other apps '
          'using it, check your camera settings, and try again.';
    }
    return 'Could not open the camera. Check that it is connected and allowed '
        'in your device settings, then try again.';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ++_generation;
      final controller = _controller;
      _controller = null;
      if (controller != null) {
        controller.removeListener(_cameraChanged);
        unawaited(controller.dispose());
      }
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      unawaited(_initialize(findCameras: false));
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _takingPhoto) {
      return;
    }
    setState(() => _takingPhoto = true);
    try {
      final photo = await controller.takePicture();
      if (mounted) Navigator.of(context).pop<String>(photo.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cameraError(error))));
    } finally {
      if (mounted) setState(() => _takingPhoto = false);
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_cameraChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Capture a memory')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF2D0000),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator(
                          color: Color(0xFFEEEAD7),
                        )
                      : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.no_photography_outlined,
                                color: Color(0xFFEEEAD7),
                                size: 48,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFFEEEAD7),
                                ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.icon(
                                onPressed: () => _initialize(),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Try again'),
                              ),
                            ],
                          ),
                        )
                      : controller == null
                      ? const SizedBox.shrink()
                      : CameraPreview(controller),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Switch camera',
                    onPressed: _cameras.length > 1 && !_loading && !_takingPhoto
                        ? () {
                            _cameraIndex = (_cameraIndex + 1) % _cameras.length;
                            unawaited(_initialize(findCameras: false));
                          }
                        : null,
                    icon: const Icon(Icons.cameraswitch_outlined),
                  ),
                  FilledButton.icon(
                    onPressed: !_loading && _error == null && !_takingPhoto
                        ? _capture
                        : null,
                    icon: _takingPhoto
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_outlined),
                    label: Text(_takingPhoto ? 'Saving…' : 'Take photo'),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
