import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// In-app audio/video player for a media URL. Uses [VideoPlayerController] for
/// both (audio just hides the video surface), mirroring the RN player.
class MediaPlayerScreen extends StatefulWidget {
  const MediaPlayerScreen({
    super.key,
    required this.url,
    this.isAudio = false,
    this.title,
    @visibleForTesting this.controllerFactory,
  });

  final String url;
  final bool isAudio;
  final String? title;

  /// Overridable for tests so a real platform player is not created.
  @visibleForTesting
  final VideoPlayerController Function(Uri uri)? controllerFactory;

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uri = Uri.parse(widget.url);
      final controller =
          widget.controllerFactory?.call(uri) ??
          VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      setState(() => _controller = controller);
      await controller.play();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  void _onTick() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    controller.value.isPlaying ? controller.pause() : controller.play();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? 'Media')),
      body: Center(child: _buildBody(context)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 44),
            const SizedBox(height: 12),
            Text(
              'Could not play this media.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '$_error',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.isAudio)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Icon(
              Icons.audiotrack,
              size: 96,
              color: Theme.of(context).colorScheme.primary,
            ),
          )
        else
          AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0
                ? 16 / 9
                : controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        VideoProgressIndicator(controller, allowScrubbing: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              IconButton(
                iconSize: 40,
                onPressed: _togglePlay,
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_circle
                      : Icons.play_circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_format(controller.value.position)} / '
                '${_format(controller.value.duration)}',
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _format(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = d.inHours;
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
