import 'dart:convert';
import 'package:computing_blog/core/logger.util.dart';
import 'package:flutter/foundation.dart';
import 'package:global_configuration/global_configuration.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../domain/models/blog.dart';

@lazySingleton
class BlogApi {
  BlogApi() {
    logger.i('BlogApi initializing');

    final cfg = GlobalConfiguration();

    String? apiUrl;
    try {
      apiUrl = cfg.getValue<String>('blogApiUrl');
      logger.d('blogApiUrl loaded from config: $apiUrl');
    } catch (_) {
      logger.w('blogApiUrl not found in config, using fallback');
      apiUrl = null;
    }

    _entriesBaseUri = Uri.parse(
      (apiUrl?.isNotEmpty ?? false)
          ? apiUrl!
          : 'https://d-cap-blog-backend---v2.whitepond-b96fee4b.westeurope.azurecontainerapps.io/entries',
    );

    logger.i('Entries base URI set to $_entriesBaseUri');

    try {
      _tokenUri = Uri.parse(cfg.getValue<String>('keycloakTokenUrl'));
      _clientId = cfg.getValue<String>('keycloakClientId');
      _username = cfg.getValue<String>('devUsername');
      _password = cfg.getValue<String>('devPassword');
      logger.d('Keycloak config loaded from GlobalConfiguration');
    } catch (_) {
      logger.w('Keycloak config missing, using fallback dev credentials');
      _tokenUri = Uri.parse(
        "https://d-cap-keyclaok.kindbay-711f60b2.westeurope.azurecontainerapps.io/realms/blog/protocol/openid-connect/token",
      );
      _clientId = "flutter-blog";
      _username = "alice";
      _password = "alice";
    }

    _headers = const {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    logger.i('BlogApi initialized');
  }

  final logger = getLogger();

  String? _accessToken;
  DateTime? _tokenExpiresAt;
  late final Uri _tokenUri;
  late final String _clientId;
  late final String _username;
  late final String _password;

  late final Uri _entriesBaseUri;
  late final Map<String, String> _headers;

  Uri _entryUri(String id) {
    final basePath = _entriesBaseUri.path;
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;

    return _entriesBaseUri.replace(path: '$normalizedBase/$id');
  }

  Uri _entryLikeUri(String id) {
    final entry = _entryUri(id);
    final normalized = entry.path.endsWith('/')
        ? entry.path.substring(0, entry.path.length - 1)
        : entry.path;
    return entry.replace(path: '$normalized/like-info');
  }

  /// GET /entries (paginated, default = 10)
  Future<List<Blog>> getBlogs({int pageIndex = 0, int pageSize = 10}) async {
    logger.i('GET /entries pageIndex=$pageIndex pageSize=$pageSize');

    final uri = _entriesBaseUri.replace(
      queryParameters: {
        'pageIndex': pageIndex.toString(),
        'pageSize': pageSize.toString(),
      },
    );

    final response = await http.get(uri, headers: await _authHeaders());

    logger.d('GET /entries response status=${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      logger.e('GET /entries failed: ${response.body}');
      throw Exception(
        'Failed to load blogs: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final List<dynamic> items = (decoded is Map<String, dynamic>)
        ? (decoded['data'] as List<dynamic>? ?? [])
        : (decoded as List<dynamic>);

    logger.d(
      'GET /entries parsed ${items.length} items '
      '(pageIndex=$pageIndex pageSize=$pageSize)',
    );

    return items.whereType<Map<String, dynamic>>().map(Blog.fromJson).toList();
  }

  /// GET /entries/{id}
  Future<Blog> getBlog({required String blogId}) async {
    logger.i('GET /entries/$blogId');

    final response = await http.get(
      _entryUri(blogId),
      headers: await _authHeaders(),
    );

    logger.d('GET /entries/$blogId status=${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      logger.e('GET blog failed: ${response.body}');
      throw Exception(
        'Failed to load blog. Status code: ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final data = decoded['data'] as List<dynamic>;

    if (data.isEmpty) {
      logger.w('Blog $blogId not found');
      throw Exception('Blog not found');
    }

    logger.d('Blog $blogId loaded successfully');
    return Blog.fromJson(data.first as Map<String, dynamic>);
  }

  /// POST /entries
  Future<Blog> addBlog({
    required String title,
    required String content,
    String? headerImageUrl,
  }) async {
    logger.i('POST /entries (create blog)');

    final response = await http.post(
      _entriesBaseUri,
      headers: await _authHeaders(),
      body: jsonEncode({'title': title, 'content': content}),
    );

    logger.d('POST /entries status=${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      logger.e('Create blog failed: ${response.body}');
      throw Exception(
        'Failed to create blog. Status code: ${response.statusCode}',
      );
    }

    if (response.body.trim().isEmpty) {
      logger.w('Blog created but response body empty');
      return Blog(
        author: 'unknown',
        title: title,
        content: content,
        publishedAt: DateTime.now(),
      );
    }

    logger.d('Blog created successfully');
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return Blog.fromJson(decoded);

    return Blog(
      author: 'unknown',
      title: title,
      content: content,
      publishedAt: DateTime.now(),
    );
  }

  Future<Blog?> patchBlog({
    required String blogId,
    String? title,
    String? content,
  }) async {
    logger.i('PATCH /entries/$blogId');

    final response = await http.patch(
      _entryUri(blogId),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (title != null) 'title': title,
        if (content != null) 'content': content,
      }),
    );

    logger.d('PATCH /entries/$blogId status=${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      logger.e('Update blog failed: ${response.body}');
      throw Exception(
        'Failed to update blog. Status code: ${response.statusCode}',
      );
    }

    if (response.body.trim().isEmpty) {
      logger.w('PATCH succeeded but response empty');
      return null;
    }

    logger.d('Blog $blogId updated');
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return Blog.fromJson(decoded);
    return null;
  }

  Future<void> deleteBlog({required String blogId}) async {
    logger.i('DELETE /entries/$blogId');

    final response = await http.delete(
      _entryUri(blogId),
      headers: await _authHeaders(),
    );

    logger.d('DELETE /entries/$blogId status=${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      logger.e('Delete blog failed: ${response.body}');
      throw Exception(
        'Failed to delete blog. Status code: ${response.statusCode}',
      );
    }

    logger.i('Blog $blogId deleted');
  }

  Future<void> setLike({
    required String blogId,
    required bool likedByMe,
  }) async {
    logger.i('PUT /entries/$blogId/like-info likedByMe=$likedByMe');

    final response = await http.put(
      _entryLikeUri(blogId),
      headers: await _authHeaders(),
      body: jsonEncode({'likedByMe': likedByMe}),
    );

    logger.d('Like response status=${response.statusCode}');

    if (response.statusCode != 204 &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      logger.e('Set like failed: ${response.body}');
      throw Exception(
        'Failed to set like. Status code: ${response.statusCode} ${response.body}',
      );
    }

    logger.i('Like updated for blogId=$blogId');
  }

  Future<String> _getAccessToken() async {
    if (_accessToken != null &&
        _tokenExpiresAt != null &&
        DateTime.now().isBefore(_tokenExpiresAt!)) {
      logger.d('Using cached access token');
      return _accessToken!;
    }

    logger.i('Requesting new access token');

    final res = await http.post(
      _tokenUri,
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'password',
        'client_id': _clientId,
        'username': _username,
        'password': _password,
      },
    );

    logger.d('Token endpoint status=${res.statusCode}');

    if (res.statusCode < 200 || res.statusCode >= 300) {
      logger.e('Token request failed: ${res.body}');
      throw Exception(
        'Failed to get token. Status: ${res.statusCode}, body: ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    final expiresIn = data['expires_in'] as int?;

    if (token == null) {
      logger.e('Token response missing access_token');
      throw Exception('Token response missing access_token: ${res.body}');
    }

    _accessToken = token;
    _tokenExpiresAt = DateTime.now().add(
      Duration(seconds: (expiresIn ?? 60) - 10),
    );

    logger.i('Access token stored, expires at $_tokenExpiresAt');
    return token;
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _getAccessToken();
    return {..._headers, 'Authorization': 'Bearer $token'};
  }
}
