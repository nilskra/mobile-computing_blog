import 'dart:async';
import 'dart:io';

import 'package:computing_blog/core/exceptions.dart';
import 'package:computing_blog/core/result.dart';
import 'package:computing_blog/data/api/blog_api.dart';
import 'package:computing_blog/domain/models/blog.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class BlogRepository {
  BlogRepository(this._api) {
    debugPrint('BlogRepository instance hash=$hashCode');
  }
  final BlogApi _api;

  final _blogController = StreamController<List<Blog>>.broadcast();
  Stream<List<Blog>> get blogStream => _blogController.stream;
  List<Blog> _currentBlogs = [];

  Future<Result<List<Blog>>> getBlogPosts() async {
    try {
      final blogs = await _api.getBlogs();
      blogs.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

      // Cache aktualisieren
      _currentBlogs = blogs;

      // Jetzt wirklich die neuen Daten in den Stream pushen
      _blogController.sink.add(_currentBlogs);

      return Success(blogs);
    } on SocketException {
      return Failure(NetworkException());
    } catch (e) {
      return Failure(ServerException(e.toString()));
    }
  }

  Future<void> addBlogPost(Blog blog) async {
    await _api.addBlog(
      title: blog.title,
      content: blog.content,
      headerImageUrl: blog.headerImageUrl, // nur wenn dein Blog-Modell das hat
    );

    await getBlogPosts();
  }

  Future<void> updateBlogPost(
    String id, {
    required String blogId,
    required String title,
    required String content,
  }) async {
    await _api.patchBlog(blogId: id, title: title, content: content);

    await getBlogPosts();
  }

  void dispose() {
    _blogController.close();
  }

  Future<void> deleteBlogPost(String blogId) async {
    await _api.deleteBlog(blogId: blogId);
    await getBlogPosts(); // Stream aktualisieren
  }
}
