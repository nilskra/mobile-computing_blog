import 'dart:convert';
import 'package:http/http.dart' as http;

class KeycloakDataSource {
  static final instance = KeycloakDataSource._init();
  KeycloakDataSource._init();

  static const String _baseUrl =
      'https://d-cap-keyclaok.kindbay-711f60b2.westeurope.azurecontainerapps.io/realms/blog';
  static const String _clientId = 'flutter-blog';
  static const String _redirectUri = 'blogapp://login-callback';

  // Erstellt die Login-URL für den Browser
  Uri getAuthorizationUri(String codeChallenge) {
    return Uri.parse('$_baseUrl/protocol/openid-connect/auth').replace(
      queryParameters: {
        'client_id': _clientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'scope':
            'openid profile email offline_access', // offline_access für Refresh Token
      },
    );
  }

  // Tauscht den Authorization Code gegen Tokens
  Future<Map<String, dynamic>> exchangeCodeForToken(
    String code,
    String codeVerifier,
  ) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/protocol/openid-connect/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': _clientId,
        'code': code,
        'redirect_uri': _redirectUri,
        'code_verifier': codeVerifier,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to exchange token: ${response.body}');
    }
  }
}