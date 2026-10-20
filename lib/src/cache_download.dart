import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/v4.dart';

/// Copies a network video into a [CacheManager] in the background, and can
/// stop doing so.
///
/// [CacheManager.downloadFile] cannot be cancelled, so a player disposed
/// mid-download kept downloading its whole video. This downloads into a
/// temporary file of its own instead, deleted when the download is
/// cancelled or fails, and hands only a finished file to
/// [CacheManager.putFileStream]. Players of the same cache key share one
/// download, which stops when the last of them lets go.
class CacheDownload {
  CacheDownload._({
    required this.url,
    required this.cacheKey,
    required this.headers,
    required this.cacheManager,
    required this.maxAge,
  });

  /// Starts the download of [url] into [cacheManager] under [cacheKey], or
  /// joins the one already running for that key.
  ///
  /// Every call must be matched by one [release].
  factory CacheDownload.start({
    required String url,
    required String cacheKey,
    required Map<String, String> headers,
    required CacheManager cacheManager,
    required Duration maxAge,
  }) {
    final running = _running[cacheKey];
    if (running != null) {
      running._holders++;
      return running;
    }
    final download = CacheDownload._(
      url: url,
      cacheKey: cacheKey,
      headers: headers,
      cacheManager: cacheManager,
      maxAge: maxAge,
    );
    _running[cacheKey] = download;
    download._done = download._run();
    return download;
  }

  static final Map<String, CacheDownload> _running = {};

  static HttpClient? _client;

  static Future<Directory>? _partialDir;

  final String url;
  final String cacheKey;
  final Map<String, String> headers;
  final CacheManager cacheManager;
  final Duration maxAge;

  int _holders = 1;
  bool _cancelled = false;
  HttpClientRequest? _request;
  void Function()? _cancelBody;
  late final Future<bool> _done;

  /// Completes with true once the video is in the cache, and with false
  /// when the download failed or was cancelled.
  Future<bool> get done => _done;

  /// Lets go of the download. When the last holder lets go before it has
  /// finished, it is cancelled and its partial file deleted.
  void release() {
    if (_holders == 0) {
      return;
    }
    _holders--;
    if (_holders > 0) {
      return;
    }
    _cancelled = true;
    _request?.abort();
    _cancelBody?.call();
    if (identical(_running[cacheKey], this)) {
      _running.remove(cacheKey);
    }
  }

  Future<bool> _run() async {
    File? partial;
    try {
      final directory = await _partialDirectory();
      if (_cancelled) {
        return false;
      }
      partial = File('${directory.path}/${const UuidV4().generate()}.part');

      final client = _client ??= HttpClient();
      final request = await client.getUrl(Uri.parse(url));
      _request = request;
      if (_cancelled) {
        request.abort();
        return false;
      }
      headers.forEach(request.headers.set);
      final response = await request.close();

      // flutter_cache_manager caches only these as a new file.
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.accepted) {
        await response.listen(null).cancel();
        throw HttpException(
          'Invalid statusCode: ${response.statusCode}',
          uri: Uri.parse(url),
        );
      }

      // Cancelling the body's subscription drops the connection, which is
      // how release() stops a download midway.
      final sink = partial.openWrite();
      final received = Completer<void>();
      final subscription = response.listen(
        sink.add,
        onError: (Object e, StackTrace s) {
          if (!received.isCompleted) {
            received.completeError(e, s);
          }
        },
        onDone: () {
          if (!received.isCompleted) {
            received.complete();
          }
        },
        cancelOnError: true,
      );
      _cancelBody = () {
        subscription.cancel();
        if (!received.isCompleted) {
          received.completeError(
            const HttpException('Caching cancelled'),
          );
        }
      };
      Object? error;
      try {
        await received.future;
      } catch (e) {
        error = e;
      }
      _cancelBody = null;
      try {
        await sink.close();
      } catch (e) {
        error ??= e;
      }
      if (error != null) {
        throw error;
      }
      if (_cancelled) {
        return false;
      }

      await cacheManager.putFileStream(
        url,
        partial.openRead(),
        key: cacheKey,
        eTag: response.headers.value(HttpHeaders.etagHeader),
        maxAge: maxAge,
        fileExtension: _fileExtension(response.headers.contentType, url),
      );
      return true;
    } catch (e) {
      if (kDebugMode && !_cancelled) {
        debugPrint('Caching [$url] failed: $e');
      }
      return false;
    } finally {
      _request = null;
      _cancelBody = null;
      if (identical(_running[cacheKey], this)) {
        _running.remove(cacheKey);
      }
      if (partial != null) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }

  /// A folder for partial downloads, emptied once per launch of the app:
  /// a download cut short by the app being killed leaves its file there.
  static Future<Directory> _partialDirectory() {
    return _partialDir ??= () async {
      final temporary = await getTemporaryDirectory();
      final directory = Directory(
        '${temporary.path}/cached_video_player_plus_partial',
      );
      try {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      } catch (_) {}
      await directory.create(recursive: true);
      return directory;
    }()
        .catchError((Object error) {
      _partialDir = null;
      throw error;
    });
  }

  /// The extension flutter_cache_manager would give the file (players pick
  /// the container by it on iOS), with the URL's for a generic type.
  static String _fileExtension(ContentType? contentType, String url) {
    if (contentType != null) {
      final known = _mimeExtensions[contentType.mimeType];
      if (known != null) {
        return known;
      }
      if (contentType.primaryType == 'video' ||
          contentType.primaryType == 'audio') {
        return contentType.subType;
      }
    }
    final path = Uri.tryParse(url)?.path ?? '';
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) {
      return name.substring(dot + 1);
    }
    final subType = contentType?.subType ?? '';
    return subType.isEmpty ? 'file' : subType;
  }

  /// flutter_cache_manager's extensions for audio and video types.
  static const _mimeExtensions = {
    'audio/3gpp': '3gp',
    'audio/3gpp2': '3g2',
    'audio/aac': 'aac',
    'audio/x-aac': 'aac',
    'audio/midi': 'midi',
    'audio/x-midi': 'midi',
    'audio/x-m4a': 'm4a',
    'audio/m4a': 'm4a',
    'audio/mpeg': 'mp3',
    'audio/ogg': 'oga',
    'audio/opus': 'opus',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/webm': 'weba',
    'video/3gpp': '3gp',
    'video/3gpp2': '3g2',
    'video/mp2t': 'ts',
    'video/mpeg': 'mpeg',
    'video/ogg': 'ogv',
    'video/webm': 'webm',
    'video/x-msvideo': 'avi',
    'video/quicktime': 'mov',
  };
}
