import 'dart:convert';
import 'dart:math';

import 'package:computing_blog/core/secure_store_data_source.dart';
import 'package:computing_blog/data/api/keycloak_data_source.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class AuthRepository {
  static final instance = AuthRepository._init();
  AuthRepository._init();

  final ValueNotifier<bool> isAuthenticated = ValueNotifier(false);
  final ValueNotifier<String?> username = ValueNotifier(null);

  // 1. PKCE Initialisierung
  Future<Uri> initAuthFlow() async {
    final verifier = _generateCodeVerifier();
    final challenge = _generateCodeChallenge(verifier);

    // WICHTIG: Verifier speichern, wir brauchen ihn nach dem Redirect wieder!
    await SecureStoreDataSource.instance.writeValue('code_verifier', verifier);

    return KeycloakDataSource.instance.getAuthorizationUri(challenge);
  }

  // 2. Login abschliessen (nach Redirect)
  Future<void> handleAuthCallback(String code) async {
    final verifier = await SecureStoreDataSource.instance.readValue(
      'code_verifier',
    );
    if (verifier == null) throw Exception("Code Verifier not found!");

    final tokens = await KeycloakDataSource.instance.exchangeCodeForToken(
      code,
      verifier,
    );
    
    // Tokens speichern
    await _saveTokens(tokens);
    isAuthenticated.value = true;
    username.value = "User";
  }

  Future<void> checkLoginStatus() async {
    final token = await SecureStoreDataSource.instance.readValue('access_token');
    if (token != null) {
      isAuthenticated.value = true;
      username.value = "User";
    } else {
      isAuthenticated.value = false;
      username.value = null;
    }
  }

  Future<void> _saveTokens(Map<String, dynamic> tokens) async {
    if (tokens['access_token'] != null) {
      await SecureStoreDataSource.instance.writeValue(
        'access_token',
        tokens['access_token'],
      );
    }
    if (tokens['refresh_token'] != null) {
      await SecureStoreDataSource.instance.writeValue(
        'refresh_token',
        tokens['refresh_token'],
      );
    }
    await SecureStoreDataSource.instance.removeValue('code_verifier');
  }

  // Helper: PKCE Generierung
  String _generateCodeVerifier() {
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  Future<String?> getAccessToken() =>
      SecureStoreDataSource.instance.readValue('access_token');

  Future<void> logout() async {
    await SecureStoreDataSource.instance.removeValue('access_token');
    await SecureStoreDataSource.instance.removeValue('refresh_token');
    isAuthenticated.value = false;
    username.value = null;
  }
}