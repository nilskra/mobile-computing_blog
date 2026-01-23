import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class BlogImageCacheManager extends CacheManager {
  static const key = 'blogImages';

  static final BlogImageCacheManager _instance = BlogImageCacheManager._();

  factory BlogImageCacheManager() => _instance;

  BlogImageCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 14),
            maxNrOfCacheObjects: 200,
          ),
        );
}
