import 'dart:convert';

import 'package:computing_blog/core/logger.util.dart';
import 'package:global_configuration/global_configuration.dart';
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import '../../domain/models/blog.dart';

@lazySingleton
class BlogApi {
  BlogApi() {
    logger.i('BlogApi initializing');

    final cfg = GlobalConfiguration();

    final apiUrl = _tryGetConfig<String>(cfg, 'blogApiUrl');
    _entriesBaseUri = Uri.parse(
      (apiUrl != null && apiUrl.trim().isNotEmpty)
          ? apiUrl
          : _fallbackEntriesUrl,
    );
    logger.i('Entries base URI set to $_entriesBaseUri');

    _tokenUri = Uri.parse(
      _tryGetConfig<String>(cfg, 'keycloakTokenUrl') ?? _fallbackTokenUrl,
    );
    _clientId = _tryGetConfig<String>(cfg, 'keycloakClientId') ?? 'flutter-blog';
    _username = _tryGetConfig<String>(cfg, 'devUsername') ?? 'alice';
    _password = _tryGetConfig<String>(cfg, 'devPassword') ?? 'alice';

    logger.d('Keycloak config loaded clientId=$_clientId user=$_username');

    _baseHeaders = const {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    logger.i('BlogApi initialized');
  }

  static const _fallbackEntriesUrl =
      'https://d-cap-blog-backend---v2.whitepond-b96fee4b.westeurope.azurecontainerapps.io/entries';

  static const _fallbackTokenUrl =
      'https://d-cap-keyclaok.kindbay-711f60b2.westeurope.azurecontainerapps.io/realms/blog/protocol/openid-connect/token';

  final logger = getLogger();

  late final Uri _entriesBaseUri;
  late final Uri _tokenUri;
  late final String _clientId;
  late final String _username;
  late final String _password;
  late final Map<String, String> _baseHeaders;

  static const _writeFastFailTimeout = Duration(seconds: 3);

  String? _accessToken;
  DateTime? _tokenExpiresAt;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// GET /entries (paginated, default = 10)
  Future<List<Blog>> getBlogs({int pageIndex = 0, int pageSize = 10}) async {
    logger.i('GET /entries pageIndex=$pageIndex pageSize=$pageSize');

    final uri = _entriesBaseUri.replace(
      queryParameters: {
        'pageIndex': pageIndex.toString(),
        'pageSize': pageSize.toString(),
      },
    );

    final decoded = await _requestJson(
      method: 'GET',
      uri: uri,
    );

    final items = _extractItems(decoded);

    logger.d(
      'GET /entries parsed ${items.length} items '
      '(pageIndex=$pageIndex pageSize=$pageSize)',
    );

    return items.whereType<Map<String, dynamic>>().map(Blog.fromJson).toList();
  }

  /// GET /entries/{id}
  Future<Blog> getBlog({required String blogId}) async {
    logger.i('GET /entries/$blogId');

    final decoded = await _requestJson(
      method: 'GET',
      uri: _entryUri(blogId),
    );

    // Dein Backend liefert hier offenbar { data: [...] }
    final data = (decoded is Map<String, dynamic>)
        ? (decoded['data'] as List<dynamic>? ?? const [])
        : const <dynamic>[];

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

    final decoded = await _requestJson(
      method: 'POST',
      uri: _entriesBaseUri,
      body: {
        'title': title,
        'content': content,
        if (headerImageUrl != null) 'headerImageUrl': headerImageUrl,
      },
      allowEmptyBody: true,
    );

    // Manche Backends geben nix zurück -> Fallback-Objekt
    if (decoded == null) {
      logger.w('Blog created but response body empty');
      return Blog(
        author: 'unknown',
        title: title,
        content: content,
        publishedAt: DateTime.now(),
      );
    }

    logger.d('Blog created successfully');
    if (decoded is Map<String, dynamic>) return Blog.fromJson(decoded);

    // Notfall-Fallback (falls response kein Objekt ist)
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
    logger.i('PATCH /entries/$blogId');

    final decoded = await _requestJson(
      method: 'PATCH',
      uri: _entryUri(blogId),
      body: {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
      },
      allowEmptyBody: true,
    );

    if (decoded == null) {
      logger.w('PATCH succeeded but response empty');
      return null;
    }

    logger.d('Blog $blogId updated');
    return decoded is Map<String, dynamic> ? Blog.fromJson(decoded) : null;
  }

  /// DELETE /entries/{id}
  Future<void> deleteBlog({required String blogId}) async {
    logger.i('DELETE /entries/$blogId');

    await _requestNoJson(
      method: 'DELETE',
      uri: _entryUri(blogId),
    );

    logger.i('Blog $blogId deleted');
  }

  /// PUT /entries/{id}/like-info
  ///
  /// Backend erlaubt offenbar 204 (No Content).
  Future<void> setLike({
    required String blogId,
    required bool likedByMe,
  }) async {
    logger.i('PUT /entries/$blogId/like-info likedByMe=$likedByMe');

    await _requestNoJson(
      method: 'PUT',
      uri: _entryLikeUri(blogId),
      body: {'likedByMe': likedByMe},
      allowedStatusCodes: const {200, 201, 202, 204},
    );

    logger.i('Like updated for blogId=$blogId');
  }

  // ---------------------------------------------------------------------------
  // HTTP helpers
  // ---------------------------------------------------------------------------

  Future<dynamic> _requestJson({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
    bool allowEmptyBody = false,
    Set<int>? allowedStatusCodes,
  }) async {
    final res = await _send(
      method: method,
      uri: uri,
      body: body,
    );

    _ensureSuccess(
      res,
      method: method,
      uri: uri,
      allowedStatusCodes: allowedStatusCodes,
    );

    final decoded = _decodeBody(res.body);
    if (decoded == null && !allowEmptyBody) {
      throw Exception('Empty response body for $method $uri');
    }
    return decoded;
  }

  Future<void> _requestNoJson({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
    Set<int>? allowedStatusCodes,
  }) async {
    final res = await _send(
      method: method,
      uri: uri,
      body: body,
    );

    _ensureSuccess(
      res,
      method: method,
      uri: uri,
      allowedStatusCodes: allowedStatusCodes,
    );
  }

  Future<http.Response> _send({
    required String method,
    required Uri uri,
    Map<String, dynamic>? body,
  }) async {
    final headers = await _authHeaders();

    logger.d('$method $uri');

    switch (method.toUpperCase()) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      case 'PATCH':
        return http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
      case 'PUT':
        return http.put(uri, headers: headers, body: jsonEncode(body ?? {}));
      case 'DELETE':
        return http.delete(uri, headers: headers);
      default:
        throw UnsupportedError('Unsupported HTTP method: $method');
    }
  }

  void _ensureSuccess(
    http.Response res, {
    required String method,
    required Uri uri,
    Set<int>? allowedStatusCodes,
  }) {
    final ok = allowedStatusCodes?.contains(res.statusCode) ??
        (res.statusCode >= 200 && res.statusCode < 300);

    logger.d('$method $uri status=${res.statusCode}');

    if (ok) return;

    logger.e('$method $uri failed: ${res.body}');
    throw Exception(
      'Request failed: $method $uri -> ${res.statusCode} ${res.body}',
    );
  }

  dynamic _decodeBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    return jsonDecode(trimmed);
  }

  List<dynamic> _extractItems(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      return (data is List<dynamic>) ? data : const <dynamic>[];
    }
    if (decoded is List<dynamic>) return decoded;
    return const <dynamic>[];
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _authHeaders() async {
    final token = await _getAccessToken();
    return {..._baseHeaders, 'Authorization': 'Bearer $token'};
  }

  Future<String> _getAccessToken() async {
    final now = DateTime.now();

    if (_accessToken != null &&
        _tokenExpiresAt != null &&
        now.isBefore(_tokenExpiresAt!)) {
      logger.d('Using cached access token');
      return _accessToken!;
    }

    logger.i('Requesting new access token');

    final res = await http
    .post(
      _tokenUri,
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'password',
        'client_id': _clientId,
        'username': _username,
        'password': _password,
      },
    )
    .timeout(_writeFastFailTimeout);

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

    if (token == null || token.isEmpty) {
      logger.e('Token response missing access_token');
      throw Exception('Token response missing access_token: ${res.body}');
    }

    _accessToken = token;

    // bisschen Puffer, damit der Token nicht “genau beim Request” abläuft
    final safeSeconds = ((expiresIn ?? 60) - 10).clamp(10, 24 * 60 * 60);
    _tokenExpiresAt = now.add(Duration(seconds: safeSeconds));

    logger.i('Access token stored, expires at $_tokenExpiresAt');
    return token;
  }

  // ---------------------------------------------------------------------------
  // URI helpers
  // ---------------------------------------------------------------------------

  Uri _entryUri(String id) => _entriesBaseUri.replace(
        path: '${_entriesBaseUri.path.replaceAll(RegExp(r'\/+$'), '')}/$id',
      );

  Uri _entryLikeUri(String id) => _entriesBaseUri.replace(
        path:
            '${_entriesBaseUri.path.replaceAll(RegExp(r'\/+$'), '')}/$id/like-info',
      );

  // ---------------------------------------------------------------------------
  // Small util
  // ---------------------------------------------------------------------------

  T? _tryGetConfig<T>(GlobalConfiguration cfg, String key) {
    try {
      final value = cfg.getValue<T>(key);
      logger.d('$key loaded from config: $value');
      return value;
    } catch (_) {
      logger.w('$key not found in config (using fallback)');
      return null;
    }
  }
}
