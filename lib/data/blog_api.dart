import 'dart:convert';
import 'package:global_configuration/global_configuration.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../models/blog.dart';

@lazySingleton
class BlogApi {
  BlogApi() {
    final cfg = GlobalConfiguration();

    _baseUrl = cfg.getValue<String>('appwriteBaseUrl');
    _projectId = cfg.getValue<String>('appwriteProjectId');
    _apiKey = cfg.getValue<String>('appwriteApiKey');

    final dbPath = cfg.getValue<String>('appwriteDbPath');
    final collectionPath = cfg.getValue<String>('blogCollectionPath');
    _blogCollectionId = '$dbPath/$collectionPath';

    _headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'X-Appwrite-Project': _projectId,
      'X-Appwrite-key': _apiKey,
    };

    if (_baseUrl.isEmpty || _projectId.isEmpty || _apiKey.isEmpty) {
      throw StateError('Missing Appwrite config (baseUrl/projectId/apiKey).');
    }
  }

  late final String _baseUrl;
  late final String _projectId;
  late final String _apiKey;
  late final String _blogCollectionId;
  late final Map<String, String> _headers;

  Future<List<Blog>> getBlogs() async {
    const Map<String, String> query = {
      "queries[0]": "{\"method\":\"limit\",\"values\":[1000]}",
    };
    try {
      final response = await http.get(
        Uri.https(_baseUrl, _blogCollectionId, query),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final List<dynamic> blogsJson = jsonDecode(response.body)["documents"];
        var blogs = blogsJson.map((json) => Blog.fromJson(json)).toList();
        return blogs;
      } else {
        throw Exception(
          'Failed to load blogs. Status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Failed to load blogs: $e');
    }
  }

  Future<Blog> getBlog({required String blogId}) async {
    try {
      final response = await http.get(
        Uri.https(_baseUrl, "$_blogCollectionId/$blogId"),
        headers: _headers,
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> blogJson = jsonDecode(response.body);
        return Blog.fromJson(blogJson);
      } else {
        throw Exception(
          'Failed to load blog. Status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Failed to load blog');
    }
  }

  Future<void> addBlog({
    required String title,
    required String content,
    String? headerImageUrl,
  }) async {
    try {
      final response = await http.post(
        Uri.https(_baseUrl, _blogCollectionId),
        headers: _headers,
        body: jsonEncode({
          "documentId": "unique()",
          "data": {
            "title": title,
            "content": content,
            "headerImageUrl": headerImageUrl,
          },
        }),
      );
      if (response.statusCode != 201) {
        throw Exception(
          'Failed to create blog. Status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Failed to create blog');
    }
  }

  Future<void> patchBlog({
    required String blogId,
    String? title,
    String? content,
    String? headerImageUrl,
    List<String>? userIdsWithLikes,
  }) async {
    var patchBody = {
      "document": blogId,
      "data": {
        if (title != null) "title": title,
        if (content != null) "content": content,
        if (headerImageUrl != null) "headerImageUrl": headerImageUrl,
        if (userIdsWithLikes != null) "userIdsWithLikes": userIdsWithLikes,
      },
    };
    try {
      final response = await http.patch(
        Uri.https(_baseUrl, "$_blogCollectionId/$blogId"),
        headers: _headers,
        body: jsonEncode(patchBody),
      );
      if (response.statusCode != 200) {
        throw Exception(
          'Failed to update blog. Status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Failed to update blog');
    }
  }

  Future<void> deleteBlog({required String blogId}) async {
    try {
      final response = await http.delete(
        Uri.https(_baseUrl, "$_blogCollectionId/$blogId"),
        headers: _headers,
      );
      if (response.statusCode != 204) {
        throw Exception(
          'Failed to delete blog. Status code: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Failed to delete blog');
    }
  }
}
