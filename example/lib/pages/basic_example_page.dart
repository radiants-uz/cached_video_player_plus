import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class BasicExamplePage extends StatefulWidget {
  const BasicExamplePage({super.key});

  @override
  State<BasicExamplePage> createState() => _BasicExamplePageState();
}

class _BasicExamplePageState extends State<BasicExamplePage> {
  // https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4
  VideoPlayerController? _controller;
  late final CachedVideoPlayerPlus _player;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _player = CachedVideoPlayerPlus.networkUrl(
      Uri.parse(
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
      ),
    );
    final controller = await _player.initialize(
      onControllerCreate: (controller) {
        setState(() {
          _controller = controller;
        });
      },
    );
    if (controller != null) {
      controller.play();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final placeholder = CircularProgressIndicator();
    return Scaffold(
      body: Center(
        child: controller == null
            ? placeholder
            : ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, child) {
                  final isInitialized = value.isInitialized;
                  final error = value.errorDescription;
                  if (error != null) {
                    return Text(
                      'Error: $error',
                      textAlign: TextAlign.center,
                    );
                  } else if (!isInitialized) {
                    return placeholder;
                  }
                  return VideoPlayer(controller);
                },
              ),
      ),
    );
  }
}
