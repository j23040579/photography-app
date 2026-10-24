import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../domain/models.dart';

/// Displays the app-owned original. Images support zoom; videos play locally.
class MemoryViewer extends StatefulWidget {
  const MemoryViewer({required this.memory, super.key});

  final Memory memory;

  @override
  State<MemoryViewer> createState() => _MemoryViewerState();
}

class _MemoryViewerState extends State<MemoryViewer>
    with WidgetsBindingObserver {
  VideoPlayerController? _video;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.memory.isVideo) unawaited(_loadVideo());
  }

  Future<void> _loadVideo() async {
    final controller = VideoPlayerController.file(File(widget.memory.path));
    _video = controller;
    controller.addListener(_videoChanged);
    try {
      await controller.initialize();
      if (!mounted || _video != controller) return;
      setState(() {});
    } catch (_) {
      if (!mounted || _video != controller) return;
      setState(
        () => _error =
            'This video could not be played. Check that the '
            'file is still available. MP4 videos with H.264 video and AAC audio '
            'work on most devices; Windows may need a codec for other formats.',
      );
    }
  }

  void _videoChanged() {
    if (!mounted) return;
    if (_video?.value.hasError ?? false) {
      _error =
          'This video cannot be played on this device. The file may be '
          'damaged or use an unsupported video format.';
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _video != null) {
      unawaited(_video!.pause());
    }
  }

  Future<void> _togglePlayback() async {
    final controller = _video;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= controller.value.duration) {
          await controller.seekTo(Duration.zero);
        }
        await controller.play();
      }
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Playback failed. The video may use a format '
            'that is not supported by this device.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final video = _video;
    if (video != null) {
      video.removeListener(_videoChanged);
      unawaited(video.dispose());
    }
    super.dispose();
  }

  /// Opens the system share sheet (WhatsApp, Messages, email, etc.) with a
  /// copy of the file. Only the media is shared; the private caption is not.
  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    final file = File(widget.memory.path);
    try {
      if (!await file.exists()) {
        messenger.showSnackBar(
          const SnackBar(content: Text('This file is no longer available.')),
        );
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: _mimeType())]),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sharing is not available on this device right now.'),
        ),
      );
    }
  }

  String? _mimeType() {
    final path = widget.memory.path.toLowerCase();
    final dot = path.lastIndexOf('.');
    switch (dot < 0 ? '' : path.substring(dot + 1)) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return null;
    }
  }

  String _duration(Duration value) {
    final minutes = value.inMinutes;
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _message(String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.broken_image_outlined,
            color: Color(0xFFEEEAD7),
            size: 48,
          ),
          const SizedBox(height: 20),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFEEEAD7)),
          ),
        ],
      ),
    ),
  );

  Widget _videoBody() {
    final controller = _video;
    if (_error != null) return _message(_error!);
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFEEEAD7)),
      );
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: VideoProgressIndicator(
            controller,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: Color(0xFFEEEAD7),
              bufferedColor: Color(0xFF757D6F),
              backgroundColor: Color(0xFF6D0808),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 24, 12),
          child: Row(
            children: [
              IconButton(
                tooltip: controller.value.isPlaying ? 'Pause' : 'Play',
                onPressed: _togglePlayback,
                color: const Color(0xFFEEEAD7),
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              Text(
                '${_duration(controller.value.position)} / '
                '${_duration(controller.value.duration)}',
                style: const TextStyle(color: Color(0xFFEEEAD7)),
              ),
              const Spacer(),
              IconButton(
                tooltip: controller.value.volume == 0 ? 'Unmute' : 'Mute',
                color: const Color(0xFFEEEAD7),
                onPressed: () =>
                    controller.setVolume(controller.value.volume == 0 ? 1 : 0),
                icon: Icon(
                  controller.value.volume == 0
                      ? Icons.volume_off_outlined
                      : Icons.volume_up_outlined,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    final created = memory.createdAt.toLocal();
    final date =
        '${created.day.toString().padLeft(2, '0')}/'
        '${created.month.toString().padLeft(2, '0')}/${created.year}';
    return Scaffold(
      appBar: AppBar(
        title: Text(memory.isVideo ? 'Video memory' : 'Photo memory'),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: _share,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF2D0000),
                child: memory.isVideo
                    ? _videoBody()
                    : InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 6,
                        child: Center(
                          child: Image.file(
                            File(memory.path),
                            fit: BoxFit.contain,
                            errorBuilder: (_, error, stackTrace) => _message(
                              'This photo is unavailable or its format cannot '
                              'be displayed on this device.',
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (memory.caption.isNotEmpty) ...[
                      Text(
                        memory.caption,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      'Added $date · Stored on this device',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
