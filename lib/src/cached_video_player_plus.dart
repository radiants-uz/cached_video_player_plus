import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;

import 'package:cached_video_player_plus/src/real_data_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:uuid/v4.dart';
import 'package:video_player/video_player.dart';

import 'cache_key_helpers.dart';
import 'video_cache_manager.dart';
import 'video_player_storage.dart';

/// A video player that wraps [VideoPlayerController] with intelligent
/// caching capabilities using [flutter_cache_manager].
///
/// It provides the same functionality as the standard video player but with the
/// added benefit of caching network videos locally for improved performance,
/// reduced bandwidth usage, and offline playback.
///
/// ### Basic Usage
///
/// ```dart
/// final player = CachedVideoPlayerPlus.networkUrl(
///   Uri.parse('https://example.com/video.mp4'),
///   invalidateCacheIfOlderThan: const Duration(days: 42),
/// );
///
/// await player.initialize();
/// player.controller.play();
/// ```
///
/// [flutter_cache_manager]: https://pub.dev/packages/flutter_cache_manager
class CachedVideoPlayerPlus {
  static bool enableLogger = kDebugMode;

  /// Constructs a [CachedVideoPlayerPlus] playing a video from an asset.
  ///
  /// The name of the asset is given by the [dataSource] argument and must not
  /// be null. The [package] argument must be non-null when the asset comes from
  /// a package and null otherwise.
  ///
  /// The [viewType] option allows the caller to request a specific display mode
  /// for the video. Platforms that do not support the request view type will
  /// ignore this parameter.
  ///
  /// Asset videos do not support caching and will bypass cache operations.
  CachedVideoPlayerPlus.asset(
    this.dataSource, {
    this.package,
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.viewType = VideoViewType.textureView,
  })  : dataSourceType = DataSourceType.asset,
        formatHint = null,
        httpHeaders = const <String, String>{},
        _authHeaders = const <String, String>{},
        invalidateCacheIfOlderThan = Duration.zero,
        skipCache = true,
        _cacheKey = '',
        _cacheManager = _defaultCacheManager {
    _logCreate();
  }

  /// Constructs a [CachedVideoPlayerPlus] playing a video from a network URL.
  ///
  /// The URI for the video is given by the [url] argument.
  ///
  /// **Android only**: The [formatHint] option allows the caller to override
  /// the video format detection code.
  ///
  /// [httpHeaders] option allows to specify HTTP headers for the request to the
  /// [url].
  ///
  /// [downloadHeaders] option allows to specify HTTP headers specifically for
  /// downloading the video file for caching. If not provided, [httpHeaders]
  /// will be used. This is useful when [httpHeaders] contains
  /// streaming-specific headers like 'Range' that should not be used when
  /// downloading the complete video file for caching.
  ///
  /// The [invalidateCacheIfOlderThan] parameter controls cache expiration.
  /// Videos cached before this duration will be re-downloaded. Defaults to 69
  /// days.
  ///
  /// Set [skipCache] to true to bypass caching and always use the network.
  ///
  /// The [cacheKey] parameter allows specifying a custom cache key for
  /// caching operations. If not provided, a default key based on the URL will
  /// be used.
  ///
  /// The [cacheManager] parameter allows providing a custom [CacheManager]
  /// instance for caching operations. If not provided, the default
  /// [VideoCacheManager] will be used.
  CachedVideoPlayerPlus.networkUrl(
    Uri url, {
    this.formatHint,
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.httpHeaders = const <String, String>{},
    Map<String, String>? downloadHeaders,
    this.viewType = VideoViewType.textureView,
    this.invalidateCacheIfOlderThan = const Duration(days: 69),
    this.skipCache = false,
    String? cacheKey,
    CacheManager? cacheManager,
  })  : dataSource = url.toString(),
        dataSourceType = DataSourceType.network,
        package = null,
        _authHeaders = downloadHeaders ?? httpHeaders,
        _cacheKey = cacheKey != null
            ? getCustomCacheKey(cacheKey)
            : getCacheKey(url.toString()),
        _cacheManager = cacheManager ?? _defaultCacheManager {
    _logCreate();
  }

  /// Constructs a [CachedVideoPlayerPlus] playing a video from a file.
  ///
  /// This will load the file from a file:// URI constructed from [file]'s path.
  /// [httpHeaders] option allows to specify HTTP headers, mainly used for hls
  /// files like (m3u8).
  ///
  /// File videos do not support caching and will bypass cache operations.
  CachedVideoPlayerPlus.file(
    File file, {
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.httpHeaders = const <String, String>{},
    this.viewType = VideoViewType.textureView,
  })  : dataSource = Uri.file(file.absolute.path).toString(),
        dataSourceType = DataSourceType.file,
        package = null,
        formatHint = null,
        _authHeaders = const <String, String>{},
        invalidateCacheIfOlderThan = Duration.zero,
        skipCache = true,
        _cacheKey = '',
        _cacheManager = _defaultCacheManager {
    _logCreate();
  }

  /// Constructs a [CachedVideoPlayerPlus] playing a video from a contentUri.
  ///
  /// This will load the video from the input content-URI.
  /// This is supported on Android only.
  ///
  /// ContentUri videos do not support caching and will bypass cache operations.
  CachedVideoPlayerPlus.contentUri(
    Uri contentUri, {
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.viewType = VideoViewType.textureView,
  })  : assert(
          defaultTargetPlatform == TargetPlatform.android,
          'CachedVideoPlayerPlus.contentUri is only supported on Android.',
        ),
        dataSource = contentUri.toString(),
        dataSourceType = DataSourceType.contentUri,
        package = null,
        formatHint = null,
        httpHeaders = const <String, String>{},
        _authHeaders = const <String, String>{},
        invalidateCacheIfOlderThan = Duration.zero,
        skipCache = true,
        _cacheKey = '',
        _cacheManager = _defaultCacheManager {
    _logCreate();
  }

  void _logCreate() {
    log('create player: $id');
  }

  final String id = UuidV4().generate();

  /// The URI to the video file. This will be in different formats depending on
  /// the [DataSourceType] of the original video.
  final String dataSource;

  /// HTTP headers used for the request to the [dataSource].
  /// Only for [CachedVideoPlayerPlus.networkUrl].
  /// Always empty for other video types.
  final Map<String, String> httpHeaders;

  /// HTTP headers used specifically for downloading the video file
  /// for caching purposes.
  ///
  /// This is useful when [httpHeaders] contains streaming-specific headers
  /// like 'Range' that should not be used when downloading the complete video
  /// file for caching.
  ///
  /// If not provided, [httpHeaders] will be used.
  final Map<String, String> _authHeaders;

  /// **Android only**. Will override the platform's generic file format
  /// detection with whatever is set here.
  final VideoFormat? formatHint;

  /// Describes the type of data source this [CachedVideoPlayerPlus]
  /// is constructed with.
  final DataSourceType dataSourceType;

  /// Provide additional configuration options (optional). Like setting the
  /// audio mode to mix.
  final VideoPlayerOptions? videoPlayerOptions;

  /// Only set for [CachedVideoPlayerPlus.asset] videos. The package that the
  /// asset was loaded from.
  final String? package;

  /// The closed caption file to be used with the video.
  ///
  /// This is only used if the video player supports closed captions.
  final Future<ClosedCaptionFile>? closedCaptionFile;

  /// The requested display mode for the video.
  ///
  /// Platforms that do not support the request view type will ignore this.
  final VideoViewType viewType;

  /// If the requested network video is cached already, checks if the cache is
  /// older than the provided [Duration] and re-fetches data.
  final Duration invalidateCacheIfOlderThan;

  /// If set to true, it will skip the cache and use the video from the network.
  final bool skipCache;

  /// The cache key used for caching operations. This is used to uniquely
  /// identify the cached video file.
  final String _cacheKey;

  bool _isInitialized = true;

  bool get isInitialized => _isInitialized;

  /// The [CacheManager] instance used for caching video files.
  ///
  /// This is used to manage cached video files, including downloading,
  /// retrieving, and removing cached files.
  ///
  /// Defaults to [VideoCacheManager] if not provided.
  final CacheManager _cacheManager;

  /// The underlying video player controller that handles actual video playback.
  late VideoPlayerController _videoPlayerController;

  /// The controller for the video player.
  ///
  /// This provides access to the underlying [VideoPlayerController] for video
  /// playback operations like play, pause, seek, and accessing video state.
  ///
  /// Throws an [StateError] if the controller is not initialized. Always call
  /// [initialize] before accessing this property.
  VideoPlayerController get controller {
    try {
      return _videoPlayerController;
    } catch (e) {
      throw StateError(
        'CachedVideoPlayerPlus is not initialized. '
        'Call initialize() before accessing the controller.',
      );
    }
  }

  /// Returns true if caching is supported and [skipCache] is false.
  ///
  /// Caching is only supported for network data sources. Asset, file, and
  /// contentUri data sources always return false.
  bool get _shouldUseCache {
    return dataSourceType == DataSourceType.network && !kIsWeb && !skipCache;
  }

  /// The default cache manager for video file caching operations.
  static final _defaultCacheManager = VideoCacheManager();

  /// Default storage for cache metadata and expiration timestamps.
  static final _storage = VideoPlayerStorage();

  bool _initializeCancelled = false;

  Completer<VideoPlayerController>? _checkCacheCompleter;

  Completer<void>? _initializationCompleter;

  Future<RealDataSource> _prepareRealDataSource() async {
    late String realDataSource;
    bool isCacheAvailable = false;

    if (_shouldUseCache) {
      FileInfo? cachedFile = await _cacheManager.getFileFromCache(_cacheKey);

      if (kDebugMode) {
        debugPrint(
          'Cached video of [$dataSource] is: ${cachedFile?.file.path}',
        );
      }

      if (cachedFile != null) {
        final cachedElapsedMillis = await _storage.read(_cacheKey);

        if (cachedElapsedMillis != null) {
          final now = DateTime.timestamp();
          final cachedDate = DateTime.fromMillisecondsSinceEpoch(
            cachedElapsedMillis,
          );
          final difference = now.difference(cachedDate);

          if (kDebugMode) {
            debugPrint(
              'Cache for [$dataSource] valid till: '
              '${cachedDate.add(invalidateCacheIfOlderThan)}',
            );
          }

          if (difference > invalidateCacheIfOlderThan) {
            if (kDebugMode) {
              debugPrint('Cache of [$dataSource] expired. Removing...');
            }
            _cacheManager.removeFile(_cacheKey);
            cachedFile = null;
          }
        } else {
          if (kDebugMode) {
            debugPrint('Cache of [$dataSource] expired. Removing...');
          }
          _cacheManager.removeFile(_cacheKey);
          cachedFile = null;
        }
      }

      if (cachedFile == null) {
        _cacheManager
            .downloadFile(dataSource, authHeaders: _authHeaders, key: _cacheKey)
            .then((_) {
          _storage.write(
            _cacheKey,
            DateTime.timestamp().millisecondsSinceEpoch,
          );
          if (kDebugMode) {
            debugPrint('Cached video [$dataSource] successfully.');
          }
        });
      } else {
        isCacheAvailable = true;
      }

      realDataSource =
          isCacheAvailable ? cachedFile!.file.absolute.path : dataSource;
    } else {
      realDataSource = dataSource;
    }

    return RealDataSource(
      datasource: realDataSource,
      originalDatasource: dataSource,
      isCacheAvailable: isCacheAvailable,
    );
  }

  VideoPlayerController _prepareVideoController(
    RealDataSource realDatasource,
  ) {
    final datasource = realDatasource.datasource;
    final isCacheAvailable = realDatasource.isCacheAvailable;
    return switch (dataSourceType) {
      DataSourceType.asset => VideoPlayerController.asset(
          datasource,
          package: package,
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
          viewType: viewType,
        ),
      DataSourceType.network when !isCacheAvailable =>
        VideoPlayerController.networkUrl(
          Uri.parse(datasource),
          formatHint: formatHint,
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
          httpHeaders: httpHeaders,
          viewType: viewType,
        ),
      DataSourceType.contentUri => VideoPlayerController.contentUri(
          Uri.parse(datasource),
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
          viewType: viewType,
        ),
      _ => VideoPlayerController.file(
          File(datasource),
          closedCaptionFile: closedCaptionFile,
          videoPlayerOptions: videoPlayerOptions,
          httpHeaders: httpHeaders,
          viewType: viewType,
        ),
    };
  }

  Future<VideoPlayerController> _checkCache() async {
    final realDataSource = await _prepareRealDataSource();
    final controller = _prepareVideoController(realDataSource);
    return controller;
  }

  /// Initializes the video player and sets up caching if applicable.
  ///
  /// This method must be called before accessing the [controller] or playing
  /// the video. It handles cache checking, file downloading, and creates the
  /// appropriate [VideoPlayerController] based on the data source type.
  ///
  /// For network videos, it checks if a cached version exists and whether it
  /// has expired based on [invalidateCacheIfOlderThan]. If no cache exists or
  /// the cache is expired, it downloads the video in the background.
  ///
  /// Returns a [Future] that completes when initialization is finished.
  Future<void> initialize({
    void Function(VideoPlayerController controller)? onControllerCreate,
    void Function(Object object, StackTrace stackTrace)? onCacheError,
    void Function(VideoPlayerController controller)? onControllerInitialized,
    void Function(Object error, StackTrace stackTrace)? onInitializationError,
  }) async {
    _initializeCancelled = false;
    final checkCompleter = Completer<VideoPlayerController>();
    _checkCacheCompleter = checkCompleter;
    final initializeCompleter = Completer<void>();
    try {
      log('checking cache: $id');
      final controller = await _checkCache();
      _videoPlayerController = controller;
      if (_initializeCancelled) {
        log('cache and initialization skipped: $id');
        checkCompleter.complete(controller);
        return;
      }

      _initializationCompleter = initializeCompleter;
      final initializeFuture = controller.initialize();
      checkCompleter.complete(controller);
      onControllerCreate?.call(controller);
      await initializeFuture;
      initializeCompleter.complete();
      if (_initializeCancelled) {
        log('initialize skipped: $id');
      } else {
        onControllerInitialized?.call(controller);
      }
      _isInitialized = true;
    } catch (e, stk) {
      if (!checkCompleter.isCompleted) {
        log('cache check error $id: $e');
        onCacheError?.call(e, stk);
        checkCompleter.completeError(e, stk);
      } else if (!initializeCompleter.isCompleted) {
        log('initialization error $id: $e');
        onInitializationError?.call(e, stk);
        initializeCompleter.completeError(e, stk);
      }
    }
  }

  void log([Object? message]) {
    if (enableLogger) {
      dev.log(message.toString(), name: 'CachedVideoPlayerPlus');
    }
  }

  /// Disposes of the video player and releases resources.
  ///
  /// Call this method when the video player is no longer needed to free up
  /// resources and prevent memory leaks.
  Future<void> dispose() async {
    try {
      final initializationCompleter = _initializationCompleter;
      if (initializationCompleter != null &&
          !initializationCompleter.isCompleted) {
        _initializeCancelled = true;
      }
      final completer = _checkCacheCompleter;
      if (completer != null) {
        if (!completer.isCompleted) {
          _initializeCancelled = true;
        }
        final controller = await completer.future;

        log('disposing${_initializeCancelled ? ' cancelled' : ''} controller $id');
        await controller.dispose().then(
          (value) {
            log('dispose controller complete $id');
          },
        );
      }
    } catch (e) {
      log('dispose error $id: $e');
    }
  }

  /// Removes the cached file for this video player's data source.
  ///
  /// This only applies to network videos. Calling this method on asset, file,
  /// or contentUri videos has no effect since they don't use caching.
  ///
  /// The cached video file and its metadata will be permanently deleted.
  Future<void> removeFromCache() async {
    await Future.wait([
      _cacheManager.removeFile(_cacheKey),
      _storage.remove(_cacheKey),
    ]);
  }

  /// Removes the cached file for the specified [url] from the cache.
  ///
  /// Use this static method to remove specific cached videos by their URL.
  ///
  /// The [url] parameter should be the original network URL of the video.
  /// This method has no effect if the URL is not found in the cache.
  ///
  /// The [cacheManager] parameter allows specifying a custom [CacheManager]
  /// instance. If not provided, the default [VideoCacheManager] will be used.
  ///
  /// Both the cached video file and its expiration metadata are deleted.
  static Future<void> removeFileFromCache(
    Uri url, {
    CacheManager? cacheManager,
  }) async {
    final urlString = url.toString();
    final cacheKey = getCacheKey(urlString);

    cacheManager ??= _defaultCacheManager;

    await Future.wait([
      cacheManager.removeFile(cacheKey),
      _storage.remove(cacheKey),
    ]);
  }

  /// Removes the cached file for the specified [cacheKey].
  ///
  /// Use this static method to remove cached videos using a custom cache key
  /// instead of the original URL.
  ///
  /// The [cacheKey] parameter should match the key used when caching the video.
  ///
  /// The [cacheManager] parameter allows specifying a custom [CacheManager]
  /// instance. If not provided, the default [VideoCacheManager] will be used.
  ///
  /// Both the cached video file and its expiration metadata are deleted.
  static Future<void> removeFileFromCacheByKey(
    String cacheKey, {
    CacheManager? cacheManager,
  }) async {
    cacheKey = getCustomCacheKey(cacheKey);

    cacheManager ??= _defaultCacheManager;

    await Future.wait([
      cacheManager.removeFile(cacheKey),
      _storage.remove(cacheKey),
    ]);
  }

  /// Clears all cached videos and their metadata.
  ///
  /// This is a static method that removes all cached video files and
  /// associated expiration data from storage. Use this to free up storage
  /// space or reset the cache state.
  ///
  /// The [cacheManager] parameter allows specifying a custom [CacheManager]
  /// instance. If not provided, the default [VideoCacheManager] will be used.
  ///
  /// This operation cannot be undone. All cached videos will need to be
  /// re-downloaded from their original sources.
  static Future<void> clearAllCache({CacheManager? cacheManager}) async {
    cacheManager ??= _defaultCacheManager;

    await Future.wait([cacheManager.emptyCache(), _storage.erase()]);
  }

  /// Pre-caches a video file from the specified [url].
  ///
  /// This method can be used to pre-cache videos before they are played,
  /// ensuring smooth playback even in low network conditions without
  /// requiring to [initialize] a [CachedVideoPlayerPlus] instance, saving
  /// memory and resources.
  ///
  /// The [invalidateCacheIfOlderThan] parameter controls cache expiration.
  /// Videos cached before this duration will be re-downloaded. Defaults to 69
  /// days.
  ///
  /// The [downloadHeaders] parameter allows specifying HTTP headers for the
  /// request to the [url]. This is useful for authenticated requests or
  /// custom headers required by the video server.
  ///
  /// The [cacheKey] parameter allows specifying a custom cache key for
  /// caching operations. If not provided, a default key based on the URL will
  /// be used.
  ///
  /// The [cacheManager] parameter allows providing a custom [CacheManager]
  /// instance for caching operations. If not provided, the default
  /// [VideoCacheManager] will be used.
  static Future<void> preCacheVideo(
    Uri url, {
    Duration invalidateCacheIfOlderThan = const Duration(days: 69),
    Map<String, String> downloadHeaders = const <String, String>{},
    String? cacheKey,
    CacheManager? cacheManager,
  }) async {
    cacheManager ??= _defaultCacheManager;

    final effectiveCacheKey = cacheKey != null
        ? getCustomCacheKey(cacheKey)
        : getCacheKey(url.toString());

    // First check if the video is already cached
    FileInfo? cachedFile = await cacheManager.getFileFromCache(
      effectiveCacheKey,
    );

    if (cachedFile != null) {
      final cachedElapsedMillis = await _storage.read(effectiveCacheKey);

      if (cachedElapsedMillis != null) {
        final now = DateTime.timestamp();
        final cachedDate = DateTime.fromMillisecondsSinceEpoch(
          cachedElapsedMillis,
        );
        final difference = now.difference(cachedDate);

        if (difference > invalidateCacheIfOlderThan) {
          if (kDebugMode) {
            debugPrint('Cache of [$url] expired. Removing...');
          }
          await cacheManager.removeFile(effectiveCacheKey);
          cachedFile = null;
        }
      } else {
        if (kDebugMode) {
          debugPrint('Cache of [$url] expired. Removing...');
        }
        await cacheManager.removeFile(effectiveCacheKey);
        cachedFile = null;
      }
    }

    if (cachedFile == null) {
      // If not cached, download and cache the video
      await cacheManager.downloadFile(
        url.toString(),
        key: effectiveCacheKey,
        authHeaders: downloadHeaders,
      );

      await _storage.write(
        effectiveCacheKey,
        DateTime.timestamp().millisecondsSinceEpoch,
      );

      if (kDebugMode) {
        debugPrint('Pre-Cached video [$url] successfully.');
      }
    }
  }
}
