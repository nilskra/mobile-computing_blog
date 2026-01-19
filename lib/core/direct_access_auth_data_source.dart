import 'dart:async';
import 'dart:convert';

import 'package:computing_blog/core/secure_store_data_source.dart';
import 'package:computing_blog/domain/models/token.dart';

import 'package:http/http.dart' as http;

class DirectAccessAuthDataSource {
  static final instance = DirectAccessAuthDataSource._init();
  DirectAccessAuthDataSource._init();
  Timer? _refreshTokenTimer;

  static const refreshTokenStorageKey = "refreshToken";
  final secureStoreDataSource = SecureStoreDataSource.instance;

  final _authUri = Uri.parse(
      'https://d-cap-keyclaok.kindbay-711f60b2.westeurope.azurecontainerapps.io/realms/blog/protocol/openid-connect/token');

  Future<TokenModel?> loginWithStoredToken() async {
    var refreshToken = await secureStoreDataSource.readValue(refreshTokenStorageKey);
    if (refreshToken != null) {
      return await _refreshSession(refreshToken);
    } else {
      return null;
    }
  }

  Future<void> removeRefreshToken() {
    if (_refreshTokenTimer != null) {
      _refreshTokenTimer!.cancel();
    }
    return secureStoreDataSource.removeValue(refreshTokenStorageKey);
  }

  Future<TokenModel?> authenticateUser(String username, String password) async {
    // Add offline_access to scope to get a long-lived refresh token
    final body = {
      "username": username,
      "password": password,
      "client_id": "flutter-blog",
      "grant_type": "password",
      "scope": "offline_access"
    };
    return await _authOnIdentityProvider(body);
  }

  Future<TokenModel?> _refreshSession(String refreshToken) async {
    var body = {
      "refresh_token": refreshToken,
      "client_id": "flutter-blog",
      "grant_type": "refresh_token"
    };
    return await _authOnIdentityProvider(body);
  }

  Future<TokenModel?> _authOnIdentityProvider(Map<String, String> body) async {
    var res = await http.post(_authUri,
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: body);

    if (res.statusCode == 200) {
      TokenModel actualToken = _setupAuthSession(res);
      print("Successfully get a new token");
      return actualToken;
    } else {
      print(
          "An Error Occurred during loggin in. Status code: ${res.statusCode} , body: ${res.body.toString()}");
      return null;
    }
  }

  TokenModel _setupAuthSession(http.Response res) {
    final actualToken = TokenModel.fromJson(jsonDecode(res.body));
    secureStoreDataSource.writeValue(refreshTokenStorageKey, actualToken.refreshToken);

    // Setup a Refresh Timer on the first login
    _refreshTokenTimer ??= Timer.periodic(const Duration(minutes: 5),
        (Timer t) => _refreshSession(actualToken.refreshToken));
    return actualToken;
  }
}