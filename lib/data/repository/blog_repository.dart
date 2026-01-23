import 'dart:async';
import 'dart:io';

import 'package:computing_blog/core/exceptions.dart';
import 'package:computing_blog/core/result.dart';
import 'package:computing_blog/data/api/blog_api.dart';
import 'package:computing_blog/domain/models/blog.dart';
import 'package:computing_blog/local/blog_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class BlogRepository {
  BlogRepository(this._api, this._cache) {
    debugPrint('BlogRepository instance hash=$hashCode');
  }

  final BlogApi _api;
  final BlogCache _cache;

  final _blogController = StreamController<List<Blog>>.broadcast();
  Stream<List<Blog>> get blogStream => _blogController.stream;

  List<Blog> _currentBlogs = [];

  /// Beispiel: maximal alle 60 Sekunden wirklich zur API gehen,
  /// sonst cached Daten nehmen (minimiert Datenzugriffe).
  static const _minFetchInterval = Duration(seconds: 60);

  Future<Result<List<Blog>>> getBlogPosts({bool forceRefresh = false}) async {
    try {
      // 1) Wenn nicht force: TTL prüfen und ggf. Cache returnen
      if (!forceRefresh) {
        final lastSync = await _cache.getLastSync();
        if (lastSync != null &&
            DateTime.now().difference(lastSync) < _minFetchInterval) {
          final cached = await _cache.getAll();
          if (cached.isNotEmpty) {
            _currentBlogs = cached;
            _blogController.add(_currentBlogs);
            return Success(cached);
          }
        }
      }

      // 2) Online-Fetch
      final blogs = await _api.getBlogs();
      blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      // 3) Cache aktualisieren
      await _cache.saveAll(blogs);

      // 4) Stream pushen
      _currentBlogs = blogs;
      _blogController.add(_currentBlogs);

      return Success(blogs);
    } on SocketException {
      // Offline → Cache
      final cached = await _cache.getAll();
      if (cached.isNotEmpty) {
        _currentBlogs = cached;
        _blogController.add(_currentBlogs);
        return Success(cached);
      }
      return Failure(NetworkException());
    } catch (e) {
      // Auch bei Serverfehlern: Cache als Fallback
      final cached = await _cache.getAll();
      if (cached.isNotEmpty) {
        _currentBlogs = cached;
        _blogController.add(_currentBlogs);
        return Success(cached);
      }
      return Failure(ServerException(e.toString()));
    }
  }

  Future<void> addBlogPost(Blog blog) async {
    await _api.addBlog(
      title: blog.title,
      content: blog.content ?? "",
      headerImageUrl: blog.headerImageUrl,
    );

    // danach frisch holen (forceRefresh) und Cache aktualisieren
    await getBlogPosts(forceRefresh: true);
  }

  Future<void> updateBlogPost(
    String id, {
    required String blogId,
    required String title,
    required String content,
  }) async {
    await _api.patchBlog(blogId: id, title: title, content: content);
    await getBlogPosts(forceRefresh: true);
  }

  void dispose() {
    _blogController.close();
  }

  Future<void> deleteBlogPost(String blogId) async {
    await _api.deleteBlog(blogId: blogId);
    await getBlogPosts(); // Stream aktualisieren
  }

  Future<void> toggleLike(Blog blog) async {
    await _api.setLike(blogId: blog.id, likedByMe: !blog.isLikedByMe);

    await getBlogPosts(); // Stream refresh
  }
}
