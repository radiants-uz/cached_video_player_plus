import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'cached_video_player_plus.dart';

/// A specialized cache manager for video files.
///
/// Extends [CacheManager] with singleton pattern to ensure consistent video
/// file caching across the application. This class is primarily used internally
/// by [CachedVideoPlayerPlus] and typically doesn't need direct usage.
class VideoCacheManager extends CacheManager {
  /// The unique identifier used for this cache manager's storage.
  ///
  /// This key ensures that cached video files are stored separately from
  /// other cached content in the application. All video files cached by
  /// [CachedVideoPlayerPlus] will use this storage key.
  static const key = 'libCachedVideoPlayerPlusData';

  /// The singleton instance of [VideoCacheManager].
  ///
  /// This ensures that all video caching operations use the same cache
  /// manager instance, providing consistency and preventing conflicts.
  ///
  /// Access this instance through the factory constructor [VideoCacheManager()].
  static final VideoCacheManager _instance = VideoCacheManager._();

  /// Returns the singleton instance of [VideoCacheManager].
  ///
  /// This factory constructor ensures that only one instance of the cache
  /// manager exists throughout the application lifecycle.
  factory VideoCacheManager() => _instance;

  /// How many videos the cache keeps by default, least recently used
  /// dropped first. flutter_cache_manager's own default is 200; a reel is
  /// several MB.
  static const defaultMaxNrOfCacheObjects = 40;

  /// How long a video stays cached without being played, by default.
  /// flutter_cache_manager's own default is 30 days.
  static const defaultStalePeriod = Duration(days: 7);

  static int _maxNrOfCacheObjects = defaultMaxNrOfCacheObjects;
  static Duration _stalePeriod = defaultStalePeriod;
  static bool _created = false;

  /// Overrides [defaultMaxNrOfCacheObjects] and [defaultStalePeriod].
  ///
  /// The cache is set up when the first player is created, so this only
  /// takes effect before that; it returns false, changing nothing, after.
  static bool configure({
    int? maxNrOfCacheObjects,
    Duration? stalePeriod,
  }) {
    if (_created) {
      return false;
    }
    _maxNrOfCacheObjects = maxNrOfCacheObjects ?? _maxNrOfCacheObjects;
    _stalePeriod = stalePeriod ?? _stalePeriod;
    return true;
  }

  /// Creates a new [VideoCacheManager] instance.
  ///
  /// This private constructor initializes the cache manager with the
  /// predefined configuration [key]. It's called only once to create the
  /// singleton instance.
  VideoCacheManager._()
      : super(
          Config(
            key,
            maxNrOfCacheObjects: _maxNrOfCacheObjects,
            stalePeriod: _stalePeriod,
          ),
        ) {
    _created = true;
  }
}
