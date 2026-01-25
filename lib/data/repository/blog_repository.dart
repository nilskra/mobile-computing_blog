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
    debugPrint('BlogRepository created (hash=$hashCode)');
  }

  final BlogApi _api;
  final BlogCache _cache;

  final _blogController = StreamController<List<Blog>>.broadcast();
  Stream<List<Blog>> get blogStream => _blogController.stream;

  List<Blog> _currentBlogs = [];

  static const _minFetchInterval = Duration(seconds: 60);

  Future<Result<List<Blog>>> getBlogPosts({bool forceRefresh = false}) async {
    debugPrint('getBlogPosts called (forceRefresh=$forceRefresh)');

    try {
      if (!forceRefresh) {
        final lastSync = await _cache.getLastSync();
        debugPrint('Last cache sync: $lastSync');

        if (lastSync != null &&
            DateTime.now().difference(lastSync) < _minFetchInterval) {
          debugPrint('Cache still valid, loading blogs from cache');

          final cached = await _cache.getAll();
          debugPrint('Loaded ${cached.length} blogs from cache');

          if (cached.isNotEmpty) {
            _currentBlogs = cached;
            _blogController.add(_currentBlogs);
            return Success(cached);
          }
        }
      }

      debugPrint('Fetching blogs from API');
      final blogs = await _api.getBlogs();
      blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      debugPrint('Fetched ${blogs.length} blogs from API');

      await _cache.saveAll(blogs);
      debugPrint('Blogs saved to cache');

      _currentBlogs = blogs;
      _blogController.add(_currentBlogs);

      return Success(blogs);
    } on SocketException {
      debugPrint('SocketException → offline, trying cache');

      final cached = await _cache.getAll();
      debugPrint('Loaded ${cached.length} blogs from cache (offline fallback)');

      if (cached.isNotEmpty) {
        _currentBlogs = cached;
        _blogController.add(_currentBlogs);
        return Success(cached);
      }

      debugPrint('No cached blogs available');
      return Failure(NetworkException());
    } catch (e) {
      debugPrint('Error while fetching blogs: $e');
      debugPrint('Trying cache as fallback');

      final cached = await _cache.getAll();
      debugPrint('Loaded ${cached.length} blogs from cache (error fallback)');

      if (cached.isNotEmpty) {
        _currentBlogs = cached;
        _blogController.add(_currentBlogs);
        return Success(cached);
      }

      return Failure(ServerException(e.toString()));
    }
  }

  Future<void> addBlogPost(Blog blog) async {
    debugPrint('addBlogPost started (title="${blog.title}")');

    await _api.addBlog(
      title: blog.title,
      content: blog.content ?? "",
      headerImageUrl: blog.headerImageUrl,
    );

    debugPrint('Blog created, refreshing blog list');
    await getBlogPosts(forceRefresh: true);
  }

  Future<void> updateBlogPost(
    String id, {
    required String blogId,
    required String title,
    required String content,
  }) async {
    debugPrint('updateBlogPost started (blogId=$id)');

    await _api.patchBlog(blogId: id, title: title, content: content);

    debugPrint('Blog updated, refreshing blog list');
    await getBlogPosts(forceRefresh: true);
  }

  Future<void> deleteBlogPost(String blogId) async {
    debugPrint('deleteBlogPost started (blogId=$blogId)');

    await _api.deleteBlog(blogId: blogId);

    debugPrint('Blog deleted, refreshing blog list');
    await getBlogPosts();
  }

  Future<void> toggleLike(Blog blog) async {
    debugPrint(
      'toggleLike started (blogId=${blog.id}, currentLike=${blog.isLikedByMe})',
    );

    await _api.setLike(blogId: blog.id, likedByMe: !blog.isLikedByMe);

    debugPrint('Like toggled, refreshing blog list');
    await getBlogPosts();
  }

  void dispose() {
    debugPrint('BlogRepository disposed');
    _blogController.close();
  }
}
