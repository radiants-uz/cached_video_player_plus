import 'package:video_player/video_player.dart';

class CustomVideoPlayerController extends VideoPlayerController {
  CustomVideoPlayerController.contentUri(
    super.contentUri, {
    super.closedCaptionFile,
    super.videoPlayerOptions,
    super.viewType,
  }) : super.contentUri();
  CustomVideoPlayerController.networkUrl(
    super.url, {
    super.closedCaptionFile,
    super.formatHint,
    super.httpHeaders,
    super.videoPlayerOptions,
    super.viewType,
  }) : super.networkUrl();
  CustomVideoPlayerController.file(
    super.file, {
    super.closedCaptionFile,
    super.httpHeaders,
    super.videoPlayerOptions,
    super.viewType,
  }) : super.file();
  CustomVideoPlayerController.asset(
    super.dataSource, {
    super.closedCaptionFile,
    super.package,
    super.videoPlayerOptions,
    super.viewType,
  }) : super.asset();

  bool _disposed = false;

  bool get disposed => _disposed;

  @override
  set value(VideoPlayerValue newValue) {
    if (_disposed) return;
    super.value = newValue;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    return super.dispose();
  }
}
