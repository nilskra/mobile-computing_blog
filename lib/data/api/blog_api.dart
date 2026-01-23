import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:global_configuration/global_configuration.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../domain/models/blog.dart';

@lazySingleton
class BlogApi {
  BlogApi() {
    final cfg = GlobalConfiguration();

    String? apiUrl;
    try {
      apiUrl = cfg.getValue<String>('blogApiUrl');
    } catch (_) {
      apiUrl = null;
    }

    // 1) Base URI EINMAL setzen
    _entriesBaseUri = Uri.parse(
      (apiUrl?.isNotEmpty ?? false)
          ? apiUrl!
          : 'https://d-cap-blog-backend---v2.whitepond-b96fee4b.westeurope.azurecontainerapps.io/entries',
    );

    // 2) Jetzt erst loggen (nachdem es existiert)
    debugPrint('Blog API URL: $_entriesBaseUri');

    // 3) Token Config separat lesen (eigener try/catch!)
    try {
      _tokenUri = Uri.parse(cfg.getValue<String>('keycloakTokenUrl'));
      _clientId = cfg.getValue<String>('keycloakClientId');
      _username = cfg.getValue<String>('devUsername');
      _password = cfg.getValue<String>('devPassword');
    } catch (_) {
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
  }

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

  /// GET /entries
  Future<List<Blog>> getBlogs() async {
    final response = await http.get(
      _entriesBaseUri,
      headers: await _authHeaders(),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to load blogs: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final List<dynamic> items = (decoded is Map<String, dynamic>)
        ? (decoded['data'] as List<dynamic>? ?? [])
        : (decoded as List<dynamic>);

    return items.whereType<Map<String, dynamic>>().map(Blog.fromJson).toList();
  }

  /// GET /entries/{id}
  Future<Blog> getBlog({required String blogId}) async {
  final response = await http.get(
    _entryUri(blogId),
    headers: await _authHeaders(),
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw Exception(
      'Failed to load blog. Status code: ${response.statusCode}',
    );
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  final data = decoded['data'] as List<dynamic>;

  if (data.isEmpty) {
    throw Exception('Blog not found');
  }

  return Blog.fromJson(data.first as Map<String, dynamic>);
}


  /// POST /entries
  Future<Blog> addBlog({required String title, required String content, String? headerImageUrl}) async {
    final response = await http.post(
      _entriesBaseUri,
      headers: await _authHeaders(),
      body: jsonEncode({'title': title, 'content': content}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to create blog. Status code: ${response.statusCode}',
      );
    }

    // Some backends return 201 with created resource, others return empty.
    if (response.body.trim().isEmpty) {
      debugPrint('Blog created (empty body).');
      // If the backend doesn't return the created resource, the caller can re-fetch.
      return Blog(
        author: 'unknown',
        title: title,
        content: content,
        publishedAt: DateTime.now(),
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return Blog.fromJson(decoded);

    return Blog(
      author: 'unknown',
      title: title,
      content: content,
      publishedAt: DateTime.now(),
    );
  }

  /// PATCH /entries/{id}
  Future<Blog?> patchBlog({
    required String blogId,
    String? title,
    String? content,
  }) async {
    final body = <String, dynamic>{
      if (title != null) 'title': title,
      if (content != null) 'content': content,
    };

    final response = await http.patch(
      _entryUri(blogId),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to update blog. Status code: ${response.statusCode}',
      );
    }

    if (response.body.trim().isEmpty) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) return Blog.fromJson(decoded);
    return null;
  }

  /// DELETE /entries/{id}
  Future<void> deleteBlog({required String blogId}) async {
    final response = await http.delete(
      _entryUri(blogId),
      headers: await _authHeaders(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Failed to delete blog. Status code: ${response.statusCode}',
      );
    }
  }

  /// PUT /entries/{id}/like-info
  /// Body: { "likedByMe": true/false }
  /// Response: 204 No Content
  Future<void> setLike({
    required String blogId,
    required bool likedByMe,
  }) async {
    final response = await http.put(
      _entryLikeUri(blogId),
      headers: await _authHeaders(),
      body: jsonEncode({'likedByMe': likedByMe}),
    );

    // Swagger: 204 expected. Viele Backends liefern auch 200.
    if (response.statusCode != 204 &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      throw Exception(
        'Failed to set like. Status code: ${response.statusCode} ${response.body}',
      );
    }

    // KEIN jsonDecode/Blog.fromJson hier! (204 -> leer)
  }

  Future<String> _getAccessToken() async {
    // Cache: wenn Token noch gültig ist -> verwenden
    if (_accessToken != null &&
        _tokenExpiresAt != null &&
        DateTime.now().isBefore(_tokenExpiresAt!)) {
      return _accessToken!;
    }

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

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'Failed to get token. Status: ${res.statusCode}, body: ${res.body}',
      );
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    final expiresIn = data['expires_in'] as int?; // seconds

    if (token == null) {
      throw Exception('Token response missing access_token: ${res.body}');
    }

    _accessToken = token;
    // kleines Sicherheits-Delta
    _tokenExpiresAt = DateTime.now().add(
      Duration(seconds: (expiresIn ?? 60) - 10),
    );

    return token;
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _getAccessToken();
    return {..._headers, 'Authorization': 'Bearer $token'};
  }
}
